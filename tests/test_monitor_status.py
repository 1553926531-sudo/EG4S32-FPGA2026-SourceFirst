import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from monitor_status import decode_line


class StatusMonitorTests(unittest.TestCase):
    def test_faults_do_not_masquerade_as_ready(self):
        text = decode_line(b'TFM 1F 05 FF 0000D7DF FA000\r\n')
        self.assertIn('Full image CRC failed', text)
        self.assertIn('frame store, video underrun, audio underrun', text)
        self.assertIn('Output pixel count: 1024000', text)
        text = decode_line(b'TFM 00 00 17 00000000 00000\r\n')
        self.assertIn('Not ready: card initialization', text)

    def test_engine_versions_are_distinguished(self):
        line = b'TFM 06 00 1F 00000001 00000\r\n'
        self.assertIn('Scheduling images and continuous audio', decode_line(line, 'v2'))
        self.assertIn('Waiting for frame buffer commit', decode_line(line, 'v1'))
        line = b'TFM 08 00 1F 00000001 00000\r\n'
        self.assertIn('Waiting for clocked audio buffer read', decode_line(line, 'v2'))
        self.assertIn('Holding standalone image', decode_line(line, 'v1'))

    def test_noise_and_partial_records_are_rejected(self):
        for line in (b'TFM 06 00 1F 00000001', b'garbage\r\n',
                     b'TFM FF 00 1F 00000001 00000\r\n',
                     b'noise TFM 06 00 1F 00000001 00000\r\n'):
            self.assertIsNone(decode_line(line))

    def test_native_waiting_and_storage_errors_are_decoded(self):
        self.assertIn('media selection', decode_line(b'TFM 00 00 1F 00000000 00000\r\n'))
        self.assertIn('neutral background', decode_line(b'TFM 20 00 1F 00000000 00000\r\n'))
        self.assertIn('header fields', decode_line(b'TFM 23 00 1F 00000000 00000\r\n'))
        self.assertIn('header validation result', decode_line(b'TFM 24 00 1F 00000000 00000\r\n'))
        self.assertIn('Invalid file-system geometry', decode_line(b'TFM 00 43 1F 00000000 00000\r\n'))
        self.assertIn('Invalid lyric timing or text', decode_line(b'TFM 06 58 1F 00000000 00000\r\n'))


if __name__ == '__main__':
    unittest.main()

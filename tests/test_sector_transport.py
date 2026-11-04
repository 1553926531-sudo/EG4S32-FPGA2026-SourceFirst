
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch
import warnings
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from reference_sector_io import SectorLink, SectorLinkError

DATA = bytes(range(256)) * 2


def reply(lba=23, status=0, marker=0x5a, corrupt=False):
    crc = zlib.crc32(DATA) ^ (1 if corrupt else 0)
    return bytes((marker, status)) + struct.pack('>I', lba) + DATA + struct.pack('>I', crc)


class FakeSerial:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.rx = bytearray()
        self.writes = []

    @property
    def in_waiting(self):
        return len(self.rx)

    def read(self, size):
        size = min(size, 17, len(self.rx))
        result = bytes(self.rx[:size])
        del self.rx[:size]
        return result

    def write(self, data):
        self.writes.append(data)
        self.rx.extend(next(self.responses))

    def reset_input_buffer(self):
        self.rx.clear()


class SectorTransportTests(unittest.TestCase):
    def test_fragmented_success_and_exact_request(self):
        port = FakeSerial([reply()])
        link = SectorLink(port)
        self.assertEqual(link.read_sector(23), DATA)
        self.assertEqual(port.writes, [b'\xa5\x01\0\0\0\x17'])
        self.assertEqual(link.read_recoveries, [])

    @patch('reference_sector_io.time.sleep', return_value=None)
    def test_corrupt_read_response_retries_and_records_recovery(self, _sleep):
        for bad in (reply(marker=0), reply(lba=24), reply(corrupt=True), reply()[:3]):
            with self.subTest(bad=bad[:6].hex()):
                port = FakeSerial([bad, reply()])
                link = SectorLink(port)
                with warnings.catch_warnings(record=True) as caught:
                    warnings.simplefilter('always')
                    self.assertEqual(link.read_sector(23, timeout=.002), DATA)
                self.assertEqual(len(port.writes), 2)
                self.assertEqual(port.writes[0], port.writes[1])
                self.assertEqual(len(link.read_recoveries), 1)
                self.assertIn('Serial read recovered after retry', str(caught[0].message))

    @patch('reference_sector_io.time.sleep', return_value=None)
    def test_read_retry_limit_is_three(self, _sleep):
        port = FakeSerial([reply(corrupt=True)] * 3)
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with self.assertRaisesRegex(SectorLinkError, 'CRC32 mismatch'):
                SectorLink(port).read_sector(23)
        self.assertEqual(len(port.writes), 3)

    def test_sd_status_and_write_failures_are_not_retried(self):
        port = FakeSerial([reply(status=7)])
        with self.assertRaisesRegex(SectorLinkError, 'FPGA read failed'):
            SectorLink(port).read_sector(23)
        self.assertEqual(len(port.writes), 1)
        for response in (reply(status=7), reply(marker=0)):
            port = FakeSerial([response])
            with self.assertRaises(SectorLinkError):
                SectorLink(port).write_sector(23, DATA)
            self.assertEqual(len(port.writes), 1)
            self.assertEqual(port.writes[0][:6], b'\xa5\x02\0\0\0\x17')


if __name__ == '__main__':
    unittest.main()

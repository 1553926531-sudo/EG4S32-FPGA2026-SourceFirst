
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from package_delivery import create_archive
from td_timing import parse_timing, REQUIRED_CLOCKS


def report():
    return '\n'.join('Timing constraint: ' + name + '\n'
                     '0 errors detected : 0 setup errors (TNS = 0), 0 hold errors (TNS = 0)\n'
                     'Slack (setup check): 0.2 ns\nSlack (hold check): 0.1 ns\n'
                     for name in sorted(REQUIRED_CLOCKS) + ['Input delay', 'Output delay'])


class TimingEvidenceTests(unittest.TestCase):
    def test_complete_positive_report(self):
        self.assertTrue(parse_timing(report(), 'eagle_s20\nmetadata\n0.2 0.1 media_player_top device')['timing_passed'])

    def test_aggregate_failure_overrides_positive_listed_paths(self):
        detail = report().replace('0 errors detected : 0 setup errors', '9 errors detected : 9 setup errors', 1)
        self.assertFalse(parse_timing(detail, 'device\nmetadata\n0.2 0.1 media_player_top')['timing_passed'])

    def test_negative_global_hold_is_not_hidden_by_detail(self):
        self.assertFalse(parse_timing(report(), 'device\nmetadata\n0.2 -0.033 media_player_top')['timing_passed'])

    def test_negative_path_is_rejected_even_with_zero_count(self):
        self.assertFalse(parse_timing(report().replace('0.1 ns', '-0.001 ns', 1),
                                      'device\nmetadata\n0.2 0.1 media_player_top')['timing_passed'])

    def test_missing_clock_and_summary_rejected(self):
        self.assertFalse(parse_timing(report(), '')['timing_passed'])
        self.assertFalse(parse_timing('Timing constraint: Input delay\n0 errors detected : 0 setup errors, 0 hold errors',
                                      'device\nmetadata\n0.2 0.1 media_player_top')['timing_passed'])

    def test_malformed_section_rejected(self):
        self.assertFalse(parse_timing(report() + 'Timing constraint: missing\n',
                                      'device\nmetadata\n0.2 0.1 media_player_top')['timing_passed'])


class ArchiveEvidenceTests(unittest.TestCase):
    def test_unicode_binary_readback_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            source = root / '中文素材.bin'
            source.write_bytes(bytes(range(256)) * 17)
            archive = root / '新交付.zip'
            result = create_archive({'素材/中文素材.bin': source}, archive)
            self.assertEqual(result['files'], 1)
            with zipfile.ZipFile(archive) as zf:
                self.assertEqual(zf.read('素材/中文素材.bin'), source.read_bytes())
            original = archive.read_bytes()
            with self.assertRaises(FileExistsError):
                create_archive({'素材/中文素材.bin': source}, archive)
            self.assertEqual(archive.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()

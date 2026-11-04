
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EnglishCliTests(unittest.TestCase):
    def execute(self, script, *args, expected=2):
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / script), *args],
                                cwd=ROOT, capture_output=True, text=True, encoding='utf-8',
                                env={**os.environ, 'PYTHONUTF8': '1'}, timeout=30)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        output = result.stdout + result.stderr
        self.assertNotRegex(output, r'[\u3400-\u9fff\ufffd]')
        self.assertNotRegex(output, r'Traceback|\ufffd')
        return output

    def test_help(self):
        for script in ('media_pack.py', 'export_map.py', 'prepare_card.py', 'build.py', 'run_sim.py'):
            with self.subTest(script=script):
                self.assertIn('show this help message and exit', self.execute(script, '--help', expected=0))

    def test_invalid_arguments(self):
        cases = (
            ('media_pack.py',),
            ('media_pack.py', '--unknown-option'),
            ('media_pack.py', '--frame-ms', 'not-a-number'),
            ('media_pack.py', '--image', 'a', '--images', 'b'),
            ('export_map.py',),
            ('export_map.py', '--image', 'a', '--port', 'b'),
            ('export_map.py', '--port', 'unused', '--volume-offset-sectors', '2048'),
            ('prepare_card.py',),
            ('build.py', '--unknown-option'),
            ('build.py', '--map', 'missing.v', '--validation-map'),
            ('run_sim.py', 'unknown_test'),
            ('run_sim.py', 'fifo', '--timeout', '0'),
        )
        for script, *args in cases:
            with self.subTest(script=script, args=args):
                self.assertIn('argument error', self.execute(script, *args))

    def test_missing_file_is_english_without_traceback(self):
        output = self.execute('media_pack.py', '--verify', '__nonexistent_test_file__.pak', expected=1)
        self.assertIn('File or path not found', output)


if __name__ == '__main__':
    unittest.main()


from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_ui_font


class UiGenerationTests(unittest.TestCase):
    def test_regeneration_preserves_validated_rtl_and_glyphs(self):
        self.maxDiff = 1200
        with tempfile.TemporaryDirectory(prefix='tf_ui_generation_') as work:
            temporary = Path(work)
            (temporary / 'rtl').mkdir()
            (temporary / 'verification').mkdir()
            layout = ROOT / 'rtl/ui_osd_layout.v'
            (temporary / 'rtl/ui_osd_layout.v').write_bytes(layout.read_bytes())
                                                                            
            with patch.object(gen_ui_font, 'ROOT', temporary), redirect_stdout(io.StringIO()):
                gen_ui_font.generate()
            for name in ('rtl/ui_font_zh.v', 'rtl/ui_font_zh_sync.v',
                         'rtl/ui_font_0.mif', 'rtl/ui_font_1.mif',
                         'rtl/ui_osd_layout.v', 'verification/ui_font.json'):
                with self.subTest(file=name):
                    self.assertEqual((temporary / name).read_text(encoding='utf-8'),
                                     (ROOT / name).read_text(encoding='utf-8'),
                                     'Regeneration differs from the validated source: ' + name)


if __name__ == '__main__':
    unittest.main()

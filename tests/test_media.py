
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from tfm_format import *
from media_pack import pack
from export_map import ReadOnlySectors, coalesce, emit_rom, export


def bmp(path, top_down=False):
    rows = []
    for y in range(HEIGHT):
        row = bytearray(WIDTH * 3)
        for x in range(WIDTH):
            row[x*3:x*3+3] = bytes(((x ^ y) & 255, y & 255, x & 255))
        rows.append(bytes(row))
    payload = b''.join(rows if top_down else reversed(rows))
    head = b'BM' + struct.pack('<IHHI', 54+len(payload), 0, 0, 54)
    head += struct.pack('<IiiHHIIiiII', 40, WIDTH, -HEIGHT if top_down else HEIGHT,
                        1, 24, 0, len(payload), 0, 0, 0, 0)
    path.write_bytes(head + payload)
    expected = bytearray(FRAME_BYTES)
    src = b''.join(rows)
    expected[0::4] = src[0::3]
    expected[1::4] = src[1::3]
    expected[2::4] = src[2::3]
    return bytes(expected)


class MediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='tfm_offline_')
        cls.d = Path(cls.temp.name)
        cls.bottom = cls.d / 'bottom.bmp'
        cls.top = cls.d / 'top.bmp'
        cls.expected = bmp(cls.bottom)
        assert cls.expected == bmp(cls.top, True)
        cls.wav = cls.d / 'stereo.wav'
        cls.pcm = b''.join(struct.pack('<hh', i-150, 150-i) for i in range(300))
        with wave.open(str(cls.wav), 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
            w.writeframes(cls.pcm)
        cls.package = cls.d / 'DEMO.PAK'
        cls.header = pack([cls.bottom], cls.top, cls.wav, cls.package)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_all_1024000_pixels_and_bmp_orientation(self):
        self.assertEqual(read_bmp(self.bottom), self.expected)
        self.assertEqual(read_bmp(self.top), self.expected)
                                                                      
        self.assertEqual(len(self.expected), 4096000)
        self.assertFalse(any(self.expected[3::4]))

    def test_package_video_image_and_exact_audio_samples(self):
        raw = self.package.read_bytes()
        h = self.header
        self.assertEqual(raw[512:512+FRAME_BYTES], self.expected)
        at = h['image_lba'] * 512
        self.assertEqual(raw[at:at+FRAME_BYTES], self.expected)
        pcm = bytearray()
        for at in range(h['audio_lba']*512, len(raw), 512):
            validate_sector(raw[at:at+512]); pcm += raw[at:at+508]
        self.assertEqual(bytes(pcm[:len(self.pcm)]), self.pcm)
        self.assertFalse(any(pcm[len(self.pcm):]))

    def test_reject_crop_resize_and_wrong_wav(self):
        raw = bytearray(self.top.read_bytes())
        struct.pack_into('<i', raw, 18, 1279)
        wrong = self.d / 'wrong_size.bmp'; wrong.write_bytes(raw)
        with self.assertRaises(ValueError): read_bmp(wrong)
        with wave.open(str(self.d / 'wrong.wav'), 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100); w.writeframes(b'\0\0')
        with self.assertRaises(ValueError):
            pack([self.bottom], self.top, self.d / 'wrong.wav', self.d / 'wrong.pak')

    def test_detect_corruption_in_all_media_sections(self):
        raw = self.package.read_bytes()
        h = self.header
        for offset in (0, 512, (1+FRAME_SECTORS)*512+8,
                       h['image_lba']*512+73, h['audio_lba']*512+19, len(raw)-1):
            bad = bytearray(raw); bad[offset] ^= 1
            path = self.d / 'corrupted.pak'; path.write_bytes(bad)
            with self.assertRaises(ValueError): verify_package(path)

    def test_no_overwrite(self):
        with self.assertRaises(FileExistsError):
            pack([self.bottom], self.top, self.wav, self.package)

    def test_fragmented_extents_and_boundary_translation(self):
        lbas = [2048,2049,2050,9000,9001,77]
        e = coalesce(lbas)
        self.assertEqual(e, [(0,2048,3),(3,9000,2),(5,77,1)])
        for logical, physical in enumerate(lbas):
            hits = [b+logical-a for a,b,n in e if a <= logical < a+n]
            self.assertEqual(hits, [physical])
        with self.assertRaises(ValueError): coalesce(range(0,130,2))
        with self.assertRaises(ValueError): coalesce([-1])
        out = self.d / 'map.v'; emit_rom(e, 6, 123, out)
        self.assertIn("logical_lba < 32'd3", out.read_text())

    def test_read_only_backend_and_missing_files(self):
        link = ReadOnlySectors(io.BytesIO(b'x'*1024))
        self.assertEqual(link.read_sector(1), b'x'*512)
        with self.assertRaises(PermissionError): link.write_sector(0,b'\0'*512)
        with self.assertRaises(ValueError): link.read_sector(2)
        class NoFile:
            def __init__(self, link): pass
            def find(self, name): return None
        with patch('reference_exfat.ExfatVolume', NoFile):
            with self.assertRaises(FileNotFoundError): export(link,'missing',self.d/'m.v')


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(MediaTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    (ROOT / 'verification').mkdir(exist_ok=True)
    (ROOT / 'verification/host_tests.json').write_text(json.dumps(dict(
        tests=result.testsRun, failures=len(result.failures), errors=len(result.errors),
        passed=result.wasSuccessful(), full_pixels_compared=1024000), indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)

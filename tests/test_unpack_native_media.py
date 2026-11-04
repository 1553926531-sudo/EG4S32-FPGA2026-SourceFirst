import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
import wave

from tfm3 import pack_v3
from tfm_format import parse_header, validate_sector, verify_package
from unpack_native_media import extract


class NativeExtractionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.raw = self.root / 'movie.bgr'
        self.raw.write_bytes(bytes(range(36)))
        self.picture = self.root / 'source.bmp'
        h = bytearray(54)
        struct.pack_into('<2sI4xI', h, 0, b'BM', 70, 54)
        struct.pack_into('<IiiHHII', h, 14, 40, 2, 2, 1, 24, 0, 16)
        self.picture.write_bytes(h + bytes([10, 20, 30, 40, 50, 60, 0, 0,
                                          70, 80, 90, 100, 110, 120, 0, 0]))
        self.tracks = []
        self.samples = []
        for n, count in enumerate((11520, 5000)):
            pcm = b''.join(struct.pack('<hh', (i*29 + n) % 32768,
                                      -((i*41 + n) % 32768)) for i in range(count))
            path = self.root / f'{n}.wav'
            with wave.open(str(path), 'wb') as f:
                f.setparams((2, 2, 48000, 0, 'NONE', 'PCM'))
                f.writeframes(pcm)
            self.samples.append(pcm)
            self.tracks.append(dict(wav=path, background=0,
                                    cues=[] if n == 0 else [(0, 'FIRST'), (4800, 'SECOND')]))

    def test_independent_files_preserve_pixels_pcm_and_cue_times(self):
        source = self.root / 'source.PAK'
        original = pack_v3(self.raw, (2, 2), [self.picture], self.tracks, source, frame_ms=80)
        report = extract(source, self.root / 'TF')
        movie = self.root / 'TF/00_INTOUCHABLE.TFV'
        converted = verify_package(movie)
        self.assertEqual((converted['image_count'], converted['music_count']), (0, 0))
        self.assertEqual(converted['video_frames'], original['video_frames'])
        with source.open('rb') as old, movie.open('rb') as new:
            for n in range(3):
                old.seek((n+1)*512); a = validate_sector(old.read(512))
                new.seek((n+1)*512); b = validate_sector(new.read(512))
                self.assertEqual(a[:4], b[:4])
                self.assertEqual(a[5:8], b[5:8])
                old.seek(a[4]*512); new.seek(b[4]*512)
                self.assertEqual(old.read(a[6]*512), new.read(b[6]*512))
            old.seek(original['audio_lba']*512)
            new.seek(converted['audio_lba']*512)
            size = (11520+126)//127*512
            self.assertEqual(old.read(size), new.read(size))
        bmp = (self.root / 'TF/01_IMAGE.bmp').read_bytes()
        self.assertEqual(struct.unpack_from('<ii', bmp, 18), (2, -2))
        self.assertEqual(bmp[54:], bytes([70,80,90,0,100,110,120,0,10,20,30,0,40,50,60,0]))
        with wave.open(str(self.root / 'TF/01_AUDIO.wav'), 'rb') as f:
            self.assertEqual((f.getnchannels(), f.getsampwidth(), f.getframerate()), (2,2,48000))
            self.assertEqual(f.readframes(f.getnframes()), self.samples[1])
        self.assertEqual((self.root/'TF/01_AUDIO.lrc').read_bytes(),
                         b'[00:00.000]FIRST\n[00:00.100]SECOND\n')
        for item in report['files']:
            self.assertEqual(hashlib.sha256((self.root/'TF'/item['name']).read_bytes()).hexdigest(), item['sha256'])
        with self.assertRaises(FileExistsError):
            extract(source, self.root/'TF')

    def test_pack_video_without_bundled_images_or_songs(self):
        path = self.root / 'movie.TFV'
        h = pack_v3(self.raw, (2,2), [], self.tracks[:1], path, frame_ms=80)
        self.assertEqual((h['image_count'], h['music_count'], h['audio_count']), (0,0,1))
        self.assertEqual(verify_package(path), h)
        with path.open('rb') as f:
            self.assertEqual(parse_header(f.read(512))['payload_lba'], 5)

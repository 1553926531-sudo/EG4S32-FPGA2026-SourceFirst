import json
from pathlib import Path
import struct
import tempfile
import unittest
import wave
import zlib

from tfm3 import pack_v3, cue_sector
from tfm_format import verify_package, validate_sector


class FinalMediaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.raw = self.root / 'video.bgr24'
        self.raw.write_bytes(bytes([1, 2, 3, 4, 5, 6]) * 3)
        self.picture = self.root / 'picture.bmp'
        header = bytearray(54)
        struct.pack_into('<2sI4xI', header, 0, b'BM', 62, 54)
        struct.pack_into('<IiiHHI', header, 14, 40, 2, 1, 1, 24, 0)
        self.picture.write_bytes(header + bytes([21, 22, 23, 24, 25, 26, 0, 0]))
        self.tracks = []
        for i, samples in enumerate((11520, 5000, 7777)):
            path = self.root / f'{i}.wav'
            with wave.open(str(path), 'wb') as f:
                f.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
                f.writeframes(struct.pack('<hh', i * 101 - 123, i * 99 + 321) * samples)
            self.tracks.append({'wav': path, 'background': 0,
                                'cues': [] if i == 0 else [(0, 'TRACK ' + str(i)), (1000, 'SECOND LINE')]})
        self.output = self.root / 'DEMO.PAK'

    def build(self):
        return pack_v3(self.raw, (2, 1), [self.picture], self.tracks, self.output, frame_ms=80)

    def test_complete_video_separate_songs_and_timed_cues(self):
        h = self.build()
        self.assertEqual((h['video_frames'], h['music_count'], h['image_count']), (3, 2, 1))
        self.assertEqual([t['samples'] for t in h['tracks']], [11520, 5000, 7777])
        self.assertEqual([t['cues'] for t in h['tracks']], [0, 2, 2])
        with self.output.open('rb') as f:
            f.seek(512)
            frame = validate_sector(f.read(512))
            f.seek(frame[4] * 512)
            self.assertEqual(f.read(8), b'\x01\x02\x03\x00\x04\x05\x06\x00')
            for i in range(3):
                f.seek((h['audio_index_lba'] + i) * 512)
                track = validate_sector(f.read(512))
                f.seek(track[2] * 512)
                self.assertEqual(struct.unpack('<hh', f.read(4)), (i * 101 - 123, i * 99 + 321))
        self.assertEqual(verify_package(self.output), h)

    def test_movie_over_600_frames_is_not_truncated(self):
        self.raw.write_bytes(bytes([1, 2, 3, 4, 5, 6]) * 601)
        result = self.build()
        self.assertEqual(result['video_frames'], 601)

    def test_recomputed_crc_does_not_bypass_extent_and_lyric_validation(self):
        h = self.build()
        original = self.output.read_bytes()
        for mutation in ('extent', 'cue_time', 'cue_ascii'):
            data = bytearray(original)
            if mutation == 'extent':
                offset = 512
                struct.pack_into('<I', data, offset + 16, h['audio_lba'])
            else:
                offset = (h['audio_index_lba'] + h['audio_count']) * 512
                if mutation == 'cue_time':
                    struct.pack_into('<I', data, offset + 4, 5000)
                else:
                    data[offset + 16] = 255
            struct.pack_into('<I', data, offset + 508, zlib.crc32(data[offset:offset + 508]))
            self.output.write_bytes(data)
            with self.assertRaises(ValueError, msg=mutation):
                verify_package(self.output)

    def test_invalid_source_cues_and_existing_outputs_are_rejected(self):
        with self.assertRaises(ValueError):
            cue_sector(0, 0, '非ASCII')
        self.tracks[1]['cues'] = [(100, 'ONE'), (99, 'TWO')]
        with self.assertRaises(ValueError):
            self.build()
        self.tracks[1]['cues'] = [(0, 'VALID')]
        self.build()
        with self.assertRaises(FileExistsError):
            self.build()

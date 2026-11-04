import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import wave
import zlib

from PIL import Image
from media_convert import convert_video, executable, ffmpeg_run, inspect_media, inspect_wav, parse_lyrics


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tool = Path(__file__).resolve().parents[1] / 'tools/media_convert.py'

    def cli(self, *args, success=True):
        result = subprocess.run([sys.executable, str(self.tool), *map(str, args)], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return json.loads(result.stdout) if success else result

    def wav(self, name='track.wav', count=48000):
        path = self.root / name
        with wave.open(str(path), 'wb') as stream:
            stream.setparams((2, 2, 48000, 0, 'NONE', 'PCM'))
            stream.writeframes(struct.pack('<hh', 1234, -2345) * count)
        return path

    def video(self, name='input.mkv', sound=True):
        path = self.root / name
        args = ['-f', 'lavfi', '-i', 'color=c=red:s=16x12:r=8:d=0.25']
        if sound:
            args += ['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100:duration=0.125']
        args += ['-c:v', 'ffv1']
        if sound:
            args += ['-c:a', 'pcm_s16le']
        ffmpeg_run(executable(None), args + [path])
        return path

    def test_image_pixels_bgr_orientation_and_no_unrequested_resize(self):
        source, output = self.root / 'image.png', self.root / 'image.bmp'
        image = Image.new('RGB', (3, 2))
        image.putdata([(255, 0, 0), (0, 255, 0), (0, 0, 255), (12, 34, 56), (78, 90, 123), (255, 255, 255)])
        image.save(source)
        result = self.cli('image', source, output)
        self.assertEqual((result['width'], result['height'], result['bits']), (3, 2, 24))
        with Image.open(output) as actual:
            self.assertEqual(actual.tobytes(), image.tobytes())
        raw = output.read_bytes()
        self.assertEqual(raw[54:57], bytes((56, 34, 12)))
        self.assertEqual(len(raw), 54 + 12 * 2)

    def test_alpha_background_and_size_limit(self):
        source, output = self.root / 'alpha.png', self.root / 'small.bmp'
        Image.new('RGBA', (4096, 2048), (255, 0, 0, 0)).save(source)
        self.cli('image', source, output, '--background', '123456')
        with Image.open(output) as actual:
            self.assertEqual(actual.size, (2048, 1024))
            self.assertEqual(actual.getpixel((0, 0)), (18, 52, 86))

    def test_audio_resampling_from_mono_flac(self):
        source, output = self.root / 'mono.flac', self.root / 'stereo.wav'
        ffmpeg_run(executable(None), ['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100:duration=0.25', source])
        result = self.cli('audio', source, output)
        self.assertEqual((result['rate'], result['bits'], result['channels'], result['samples']), (48000, 16, 2, 12000))
        with wave.open(str(output), 'rb') as actual:
            pcm = actual.readframes(12000)
        self.assertTrue(any(pcm))
        self.assertEqual(pcm[0::4], pcm[2::4])
        self.assertEqual(pcm[1::4], pcm[3::4])

    def test_lyrics_multitag_offset_sorted_and_wrapped(self):
        sound = self.wav()
        source, output = self.root / 'raw.lrc', self.root / 'track.lrc'
        source.write_text('[ti:Track]\n[offset:10]\n[00:00.4][00:00.2]A SHORT LINE\n[00:00.1]ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN\n', encoding='utf-8')
        result = self.cli('lyrics', source, output, '--wav', sound)
        self.assertEqual(result['cues'], 3)
        lines = output.read_text(encoding='ascii').splitlines()
        self.assertTrue(lines[0].startswith('[00:00.110]'))
        self.assertEqual(lines[0][11:50].strip(), 'ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT')
        self.assertTrue(lines[1].startswith('[00:00.210]'))
        self.assertTrue(lines[2].startswith('[00:00.410]'))

    def test_non_ascii_lyrics_are_rejected_without_partial_output(self):
        source, output = self.root / 'raw.lrc', self.root / 'track.lrc'
        source.write_text('[00:00.100]\u4e2d\u6587\n', encoding='utf-8')
        self.cli('lyrics', source, output, '--wav', self.wav(), success=False)
        self.assertFalse(output.exists())

    def test_conflicting_lyrics_and_out_of_track_are_rejected(self):
        source = self.root / 'bad.lrc'
        for content in ['[00:00.1]ONE\n[00:00.1]TWO\n', '[00:01.000]END\n', '[60:00.0]BAD\n']:
            source.write_text(content, encoding='ascii')
            with self.assertRaises(ValueError):
                parse_lyrics(source, samples=48000)

    def test_unsorted_converted_lyrics_are_rejected_by_inspector(self):
        source = self.root / 'track.lrc'
        source.write_text('[00:00.200]LATE\n[00:00.100]EARLY\n', encoding='ascii')
        with self.assertRaises(ValueError):
            inspect_media(source, self.wav())

    def test_existing_output_and_source_are_preserved(self):
        source, output = self.root / 'image.png', self.root / 'image.bmp'
        Image.new('RGB', (2, 2)).save(source)
        before = source.read_bytes()
        output.write_bytes(b'KEEP')
        self.cli('image', source, output, success=False)
        self.assertEqual(output.read_bytes(), b'KEEP')
        self.assertEqual(source.read_bytes(), before)

    def test_invalid_parameters_wrong_extension_and_missing_input(self):
        source = self.root / 'image.png'
        Image.new('RGB', (2, 2)).save(source)
        for extra in [('--max-width', '2049'), ('--background', 'bad')]:
            self.cli('image', source, self.root / 'out.bmp', *extra, success=False)
        self.cli('image', source, self.root / 'out.jpg', success=False)
        self.cli('audio', self.root / 'missing.mp3', self.root / 'out.wav', success=False)

    def test_unsupported_and_truncated_wav(self):
        source = self.wav()
        raw = source.read_bytes()
        source.write_bytes(raw[:-1])
        with self.assertRaises(ValueError):
            inspect_wav(source)
        source.write_bytes(raw[:20] + struct.pack('<I', 44100) + raw[24:])
        with self.assertRaises(ValueError):
            inspect_wav(source)

    def test_wav_trailing_duplicate_and_missing_odd_chunk_padding(self):
        source = self.wav()
        raw = source.read_bytes()
        for extra in (raw[12:36], b'JUNK' + struct.pack('<I', 1) + b'X'):
            corrupted = bytearray(raw + extra)
            struct.pack_into('<I', corrupted, 4, len(corrupted) - 8)
            source.write_bytes(corrupted)
            with self.assertRaises(ValueError):
                inspect_wav(source)

    def test_video_rejects_duration_beyond_temporary_riff_limit(self):
        args = SimpleNamespace(width=1, height=1, frame_ms=60000, ffmpeg=None, source=self.root / 'input.mkv')
        def decode(binary, arguments):
            Path(arguments[-1]).write_bytes(bytes(3 * 361))
            return []
        with patch('media_convert.ffmpeg_run', side_effect=decode):
            with self.assertRaisesRegex(ValueError, 'six hours'):
                convert_video(args, self.root / 'movie.tfv', self.root)

    def test_video_independent_layout_pcm_sync_pixels_and_crc(self):
        source, output = self.video(), self.root / 'movie.tfv'
        result = self.cli('video', source, output, '--width', 16, '--height', 12)
        self.assertEqual((result['video_frames'], result['frame_ms'], result['audio_samples']), (2, 125, 12000))
        self.assertEqual((result['image_count'], result['music_count'], result['audio_count']), (0, 0, 1))
        raw = output.read_bytes()
        header = struct.unpack('<128I', raw[:512])
        self.assertEqual(header[:10], (0x314d4654, 3, 1280, 800, 1, 1024000, 2, 125, 1, 1))
        self.assertEqual(header[21:24], (3, 1, 4))
        for index in (1, 2):
            descriptor = struct.unpack_from('<128I', raw, index * 512)
            self.assertEqual(descriptor[:4], (0x32474d49, index - 1, 16, 12))
            pixels = raw[descriptor[4]*512:(descriptor[4]+descriptor[6])*512]
            self.assertEqual(zlib.crc32(pixels), descriptor[7])
            self.assertEqual(pixels[3::4], bytes(len(pixels)//4))
            self.assertGreater(pixels[2], 240)
            self.assertLess(pixels[0], 10)
        audio = raw[header[11]*512:]
        decoded = b''.join(audio[start:start+508] for start in range(0, len(audio), 512))[:12000*4]
        self.assertTrue(any(decoded[:6000*4]))
        self.assertFalse(any(decoded[7000*4:]))
        self.cli('inspect', output)

    def test_video_corruption_is_rejected(self):
        output = self.root / 'movie.tfv'
        self.cli('video', self.video(), output, '--width', 16, '--height', 12)
        raw = bytearray(output.read_bytes())
        raw[4*512] ^= 1
        output.write_bytes(raw)
        self.cli('inspect', output, success=False)

    def test_video_without_audio_requires_explicit_silence(self):
        source, output = self.video(sound=False), self.root / 'silent.tfv'
        self.cli('video', source, output, '--width', 16, '--height', 12, success=False)
        self.assertFalse(output.exists())
        result = self.cli('video', source, output, '--width', 16, '--height', 12, '--silent')
        raw = output.read_bytes()
        audio = raw[result['audio_lba']*512:]
        for start in range(0, len(audio), 512):
            self.assertFalse(any(audio[start:start+508]))

    def test_report_and_output_paths_cannot_alias(self):
        source, output = self.root / 'image.png', self.root / 'image.bmp'
        Image.new('RGB', (2, 2)).save(source)
        self.cli('image', source, output, '--report', output, success=False)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()

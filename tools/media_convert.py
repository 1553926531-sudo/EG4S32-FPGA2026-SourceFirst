import argparse
from contextlib import redirect_stdout
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import textwrap
import wave

from tfm3 import pack_v3
from tfm_format import parse_header, verify_package


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(8 * 1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def executable(value):
    if value:
        found = shutil.which(value) or (str(Path(value).resolve()) if Path(value).is_file() else None)
    else:
        found = shutil.which('ffmpeg')
        if not found:
            try:
                import imageio_ffmpeg
                found = imageio_ffmpeg.get_ffmpeg_exe()
            except ImportError:
                found = None
    if not found:
        raise ValueError('FFmpeg not found. Install tools/requirements-media.txt or pass --ffmpeg PATH.')
    return found


def ffmpeg_run(binary, args):
    command = [binary, '-nostdin', '-hide_banner', '-loglevel', 'error', '-xerror', '-n'] + list(map(str, args))
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        message = result.stderr.decode('utf-8', errors='replace')[-6000:]
        raise ValueError('FFmpeg failed: ' + message)
    return command


def inspect_bmp(path):
    from PIL import Image
    with Path(path).open('rb') as source:
        raw = source.read(138)
    if len(raw) < 54 or raw[:2] != b'BM':
        raise ValueError('Invalid BMP signature/header')
    dib, width, signed_height, planes, bits, compression = struct.unpack_from('<IiiHHI', raw, 14)
    offset = struct.unpack_from('<I', raw, 10)[0]
    height = abs(signed_height)
    stride = (width * (bits // 8) + 3) & ~3
    if not (40 <= dib <= 124 and 1 <= width <= 2048 and 1 <= height <= 2048
            and planes == 1 and bits in (24, 32) and compression == 0
            and offset >= 14 + dib and offset + stride * height <= Path(path).stat().st_size):
        raise ValueError('Unsupported or truncated BMP: requires BI_RGB, 24/32 bits, axes 1..2048')
    with Image.open(path) as image:
        image.load()
    return dict(kind='image', width=width, height=height, bits=bits, compression='BI_RGB',
                row_bytes=stride, top_down=signed_height < 0)


def inspect_wav(path, max_samples=172800000):
    with Path(path).open('rb') as source:
        header = source.read(12)
        if len(header) != 12 or header[:4] != b'RIFF' or header[8:] != b'WAVE':
            raise ValueError('Requires ordinary RIFF WAVE, not RF64')
        end = struct.unpack_from('<I', header, 4)[0] + 8
        if end > Path(path).stat().st_size or end < 44:
            raise ValueError('Truncated RIFF WAVE')
        position = 12
        fmt = data_bytes = None
        chunks = 0
        while position < end:
            chunks += 1
            if chunks > 4096 or position > end - 8:
                raise ValueError('Too many WAV chunks or incomplete chunk header')
            source.seek(position)
            tag, size = struct.unpack('<4sI', source.read(8))
            next_position = position + 8 + size + (size & 1)
            if next_position > end:
                raise ValueError('WAV chunk exceeds RIFF bounds')
            if tag == b'fmt ':
                if fmt is not None or size < 16:
                    raise ValueError('Invalid duplicate/short fmt chunk')
                fmt = struct.unpack('<HHIIHH', source.read(16))
            elif tag == b'data':
                if data_bytes is not None or not size or size % 4:
                    raise ValueError('Invalid duplicate/empty/unaligned data chunk')
                data_bytes = size
            position = next_position
        if fmt != (1, 2, 48000, 192000, 4, 16) or data_bytes is None:
            raise ValueError('Requires format tag 1, 48000 Hz, signed 16-bit stereo PCM')
    with wave.open(str(path), 'rb') as sound:
        samples = sound.getnframes()
        if not 1 <= samples <= max_samples or samples * 4 != data_bytes:
            raise ValueError('Invalid WAV duration or sample count')
        remaining = samples
        while remaining:
            count = min(65536, remaining)
            if len(sound.readframes(count)) != count * 4:
                raise ValueError('Truncated WAV PCM')
            remaining -= count
    return dict(kind='audio', rate=48000, bits=16, channels=2, samples=samples, seconds=samples / 48000)


def parse_lyrics(path, encoding='utf-8-sig', wrap=True, samples=None):
    text = Path(path).read_text(encoding=encoding)
    offset = 0
    offsets = re.findall(r'^\[offset:([+-]?\d+)\]\s*$', text, flags=re.I | re.M)
    if len(offsets) > 1:
        raise ValueError('Multiple LRC offset tags')
    if offsets:
        offset = int(offsets[0])
    cues = {}
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or re.fullmatch(r'\[(?:ar|ti|al|by|re|ve|length|offset):[^\]]*\]\s*', line, re.I):
            continue
        tags = re.match(r'(?:\[\d{1,2}:\d{2}(?:\.\d{1,3})?\])+', line)
        if not tags:
            raise ValueError(f'LRC line {number}: unsupported syntax')
        content = line[tags.end():]
        if any(ord(character) < 32 or ord(character) > 126 for character in content):
            raise ValueError(f'LRC line {number}: text must be printable ASCII. Supply a translation; text is never silently removed.')
        if wrap:
            parts = textwrap.wrap(content, width=39, break_long_words=False, break_on_hyphens=False)
            if len(parts) > 2 or any(len(part) > 39 for part in parts):
                raise ValueError(f'LRC line {number}: text does not fit two 39-character rows')
            content = parts[0].ljust(39) + parts[1] if len(parts) == 2 else (parts[0] if parts else '')
        if len(content) > 78:
            raise ValueError(f'LRC line {number}: exceeds 78 characters')
        for minute, second, fraction in re.findall(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]', tags[0]):
            if int(minute) >= 60 or int(second) >= 60:
                raise ValueError(f'LRC line {number}: minute/second outside 0..59')
            milliseconds = (int(minute) * 60 + int(second)) * 1000 + int((fraction or '0').ljust(3, '0')) + offset
            if milliseconds < 0 or milliseconds >= 3600000 or (samples is not None and milliseconds * 48 >= samples):
                raise ValueError(f'LRC line {number}: time outside track or one-hour limit')
            if milliseconds in cues and cues[milliseconds] != content:
                raise ValueError(f'LRC line {number}: conflicting text at the same timestamp')
            cues[milliseconds] = content
    result = sorted(cues.items())
    if not 1 <= len(result) <= 4096:
        raise ValueError('LRC requires 1..4096 cues')
    return result


def inspect_media(path, wav_path=None):
    suffix = Path(path).suffix.lower()
    if suffix == '.bmp':
        return inspect_bmp(path)
    if suffix == '.wav':
        return inspect_wav(path)
    if suffix == '.lrc':
        if wav_path is None:
            raise ValueError('LRC inspection requires --wav with the matching converted WAV')
        sound = inspect_wav(wav_path)
        if Path(path).stat().st_size > 1048576:
            raise ValueError('LRC exceeds 1 MiB')
        previous = -1
        lines = Path(path).read_text(encoding='ascii').splitlines()
        for line in lines:
            match = re.fullmatch(r'\[(\d{2}):(\d{2})\.(\d{3})\]([ -~]{0,78})', line)
            if not match:
                raise ValueError('Converted LRC requires one canonical timestamp and printable ASCII per line')
            minute, second, fraction = map(int, match.groups()[:3])
            milliseconds = (minute * 60 + second) * 1000 + fraction
            if minute >= 60 or second >= 60 or milliseconds <= previous or milliseconds * 48 >= sound['samples']:
                raise ValueError('Converted LRC times must be unique, increasing and inside the track')
            previous = milliseconds
        cues = parse_lyrics(path, encoding='ascii', wrap=False, samples=sound['samples'])
        return dict(kind='lyrics', cues=len(cues), first_ms=cues[0][0], last_ms=cues[-1][0])
    if suffix in ('.tfv', '.pak'):
        with Path(path).open('rb') as source:
            header = parse_header(source.read(512))
        if header.get('version') != 3:
            raise ValueError('Current FPGA profile requires TFM3 version 3')
        if suffix == '.tfv' and (header['image_count'] or header['music_count']):
            raise ValueError('Independent TFV must contain zero slideshow images and zero music tracks')
        return dict(kind='video' if suffix == '.tfv' else 'legacy_package', full_readback=True,
                    **verify_package(path))
    raise ValueError('Inspect supports BMP, WAV, LRC, TFV and TFM3 PAK')


def convert_image(args, target):
    from PIL import Image, ImageOps
    if not 1 <= args.max_width <= 2048 or not 1 <= args.max_height <= 2048:
        raise ValueError('Image limits must be in 1..2048')
    if not re.fullmatch('[0-9a-fA-F]{6}', args.background):
        raise ValueError('--background requires six RGB hexadecimal digits')
    background = tuple(bytes.fromhex(args.background))
    with Image.open(args.source) as original:
        image = ImageOps.exif_transpose(original).convert('RGBA')
    original_size = list(image.size)
    canvas = Image.new('RGBA', image.size, background + (255,))
    canvas.alpha_composite(image)
    image = canvas.convert('RGB')
    image.thumbnail((args.max_width, args.max_height), Image.Resampling.LANCZOS)
    image.save(target, 'BMP')
    return dict(**inspect_bmp(target), source_size=original_size, aspect_preserved=True, upscaled=False)


def convert_audio(args, target):
    binary = executable(args.ffmpeg)
    command = ffmpeg_run(binary, ['-i', args.source, '-map', '0:a:0', '-vn', '-sn', '-dn',
        '-ac', 2, '-ar', 48000, '-c:a', 'pcm_s16le', '-map_metadata', -1, '-rf64', 'never', target])
    return dict(**inspect_wav(target), command=command)


def convert_video(args, target, temporary):
    if not 1 <= args.width <= 2048 or not 1 <= args.height <= 2048 or not 80 <= args.frame_ms <= 60000:
        raise ValueError('Video dimensions must be 1..2048 and frame period 80..60000 ms')
    binary = executable(args.ffmpeg)
    raw, audio = temporary / 'video.bgr24', temporary / 'audio.wav'
    filters = (f'fps=1000/{args.frame_ms},scale={args.width}:{args.height}:'
               f'force_original_aspect_ratio=decrease:flags=lanczos,pad={args.width}:{args.height}:(ow-iw)/2:(oh-ih)/2:black,setsar=1')
    commands = [ffmpeg_run(binary, ['-i', args.source, '-map', '0:v:0', '-an', '-sn', '-dn',
        '-vf', filters, '-pix_fmt', 'bgr24', '-f', 'rawvideo', raw])]
    frame_bytes = args.width * args.height * 3
    raw_bytes = raw.stat().st_size
    if not raw_bytes or raw_bytes % frame_bytes:
        raise ValueError('Decoded raw video has zero or incomplete frames')
    frames = raw_bytes // frame_bytes
    samples = frames * args.frame_ms * 48
    if frames > 1000000 or samples > 2073600000:
        raise ValueError('Video exceeds one million frames or 12 hours')
    if samples > 1036800000:
        raise ValueError('This converter uses RIFF WAV temporary audio: video must not exceed six hours')
    sectors = frames + 2 + frames * ((args.width + 127) // 128) * args.height + (samples + 126) // 127
    if sectors > 200000000:
        raise ValueError('TFV would exceed 200,000,000 sectors')
    duration = f'{frames * args.frame_ms // 1000}.{frames * args.frame_ms % 1000:03d}'
    audio_input = ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'] if args.silent else ['-i', args.source]
    commands.append(ffmpeg_run(binary, audio_input + ['-map', '0:a:0', '-vn', '-sn', '-dn', '-af', 'apad',
        '-t', duration, '-ac', 2, '-ar', 48000, '-c:a', 'pcm_s16le', '-map_metadata', -1, '-rf64', 'never', audio]))
    sound = inspect_wav(audio, 2073600000)
    if sound['samples'] != samples:
        raise ValueError('Converted video PCM is not exactly aligned to the frame timeline')
    with redirect_stdout(sys.stderr):
        result = pack_v3(raw, (args.width, args.height), [], [{'wav': audio}], target,
                         frame_ms=args.frame_ms, image_ms=5000)
    return dict(kind='video', **result, full_readback=True, pcm_aligned_to_video=True,
                encoded_frame_dimensions=[args.width, args.height], silent=args.silent, commands=commands)


def publish(source, destination):
    if os.name == 'nt':
        os.rename(source, destination)
    else:
        os.link(source, destination)
        Path(source).unlink()


def main():
    parser = argparse.ArgumentParser(description='Convert arbitrary assets to the current FPGA media profile; never overwrites files.')
    parser.add_argument('--version', action='version', version='media_convert 1.0 / TFM3 profile 2026-11-04')
    sub = parser.add_subparsers(dest='action', required=True)
    for action, help_text in [('image', 'JPG/PNG/WebP/TIFF/GIF to 24-bit BMP'),
                              ('audio', 'FFmpeg audio to 48 kHz / 16-bit / stereo PCM WAV'),
                              ('video', 'FFmpeg video to a single-video TFM3 TFV'),
                              ('lyrics', 'Timed LRC to ordered ASCII LRC for a matching WAV'),
                              ('inspect', 'Read-only full validation of an existing converted file')]:
        item = sub.add_parser(action, help=help_text)
        item.add_argument('source', type=Path)
        if action != 'inspect':
            item.add_argument('output', type=Path)
        item.add_argument('--report', type=Path, help='Optional new JSON evidence file; never overwritten')
        if action in ('audio', 'video'):
            item.add_argument('--ffmpeg', help='FFmpeg executable; otherwise use PATH or imageio-ffmpeg')
        if action in ('lyrics', 'inspect'):
            item.add_argument('--wav', type=Path, required=action == 'lyrics', help='Matching converted WAV for lyric timing validation')
        if action == 'lyrics':
            item.add_argument('--encoding', default='utf-8-sig')
            item.add_argument('--layout', choices=('two39', 'keep'), default='two39')
        if action == 'image':
            item.add_argument('--max-width', type=int, default=2048)
            item.add_argument('--max-height', type=int, default=2048)
            item.add_argument('--background', default='000000')
        if action == 'video':
            item.add_argument('--width', type=int, default=384)
            item.add_argument('--height', type=int, default=208)
            item.add_argument('--frame-ms', type=int, default=125)
            item.add_argument('--silent', action='store_true', help='Generate silence instead of decoding the source audio')
    args = parser.parse_args()
    if not args.source.is_file():
        raise ValueError('Source file not found: ' + str(args.source))
    if args.report and args.report.exists():
        raise FileExistsError(args.report)
    if args.action == 'inspect':
        result = inspect_media(args.source, args.wav)
        output = args.source
    else:
        output = args.output
        required_suffix = dict(image='.bmp', audio='.wav', video='.tfv', lyrics='.lrc')[args.action]
        if output.suffix.lower() != required_suffix:
            raise ValueError('Output extension must be ' + required_suffix)
        if output.exists():
            raise FileExistsError(output)
        if args.report and args.report.resolve() == output.resolve():
            raise ValueError('Report and media output must have different paths')
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.tf_convert_', dir=output.parent) as directory:
            temporary = Path(directory)
            target = temporary / ('output' + required_suffix)
            if args.action == 'image':
                result = convert_image(args, target)
            elif args.action == 'audio':
                result = convert_audio(args, target)
            elif args.action == 'video':
                result = convert_video(args, target, temporary)
            else:
                sound = inspect_wav(args.wav)
                cues = parse_lyrics(args.source, encoding=args.encoding, wrap=args.layout == 'two39', samples=sound['samples'])
                lines = [f'[{ms // 60000:02d}:{ms // 1000 % 60:02d}.{ms % 1000:03d}]{text}\n' for ms, text in cues]
                target.write_text(''.join(lines), encoding='ascii', newline='\n')
                result = inspect_media(target, args.wav)
            publish(target, output)
    result.update(passed=True, tool_version='1.0', source=str(args.source.resolve()),
                  output=str(output.resolve()), bytes=output.stat().st_size, sha256=digest(output))
    encoded = json.dumps(result, indent=2, ensure_ascii=False)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open('x', encoding='utf-8') as report:
            report.write(encoded + '\n')
    print(encoded)


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    try:
        main()
    except (ValueError, OSError, UnicodeError, wave.Error) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)

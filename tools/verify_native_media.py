
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import struct
import time
import wave
import zlib

from tfm_format import parse_header, validate_sector


def checked(condition, message):
    if not condition:
        raise ValueError(message)


def sector(stream, lba):
    stream.seek(lba * 512)
    return validate_sector(stream.read(512))


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(source, folder, manifest):
    started = time.monotonic()
    records = manifest['files']
    checked({p.name for p in folder.iterdir()} == {r['name'] for r in records}, 'Unexpected or missing files')
    video = next(r for r in records if r['kind'] == 'video')
    with source.open('rb') as old, (folder / video['name']).open('rb') as new:
        a, b = parse_header(old.read(512)), parse_header(new.read(512))
        checked(a['version'] == b['version'] == 3, 'Version mismatch')
        for key in ['video_frames', 'frame_ms', 'audio_samples', 'image_ms']:
            checked(a[key] == b[key], 'Movie ' + key)
        checked(b['image_count'] == b['music_count'] == 0 and b['audio_count'] == 1, 'Movie contains unrelated media')
        checked((folder / video['name']).stat().st_size == b['sectors'] * 512, 'Movie length')
        old_desc = [sector(old, n + 1) for n in range(a['video_frames'] + a['image_count'])]
        new_desc = [sector(new, n + 1) for n in range(b['video_frames'])]
        next_lba = b['payload_lba']
        for n, (x, y) in enumerate(zip(old_desc, new_desc)):
            checked(x[:4] == y[:4] and x[5:8] == y[5:8] and y[1] == n, f'Frame descriptor {n}')
            checked(y[4] == next_lba and y[5] == (y[2] + 127) // 128 and y[6] == y[5] * y[3], f'Frame layout {n}')
            old.seek(x[4] * 512); new.seek(y[4] * 512)
            original, extracted = old.read(x[6] * 512), new.read(y[6] * 512)
            checked(original == extracted and len(extracted) == y[6] * 512, f'Frame bytes {n}')
            checked(zlib.crc32(extracted) == y[7] and not any(extracted[3::4]), f'Frame CRC/channels {n}')
            checked(all(not any(extracted[row * y[5] * 512 + y[2] * 4:(row + 1) * y[5] * 512])
                        for row in range(y[3])), f'Frame row padding {n}')
            next_lba += y[6]
            if n % 8192 == 0:
                print(f'Verified frames {n}/{b["video_frames"]}', flush=True)
        checked(next_lba == b['audio_lba'], 'Movie payload end')
        old_tracks = [sector(old, a['audio_index_lba'] + n) for n in range(a['audio_count'])]
        new_track = sector(new, b['audio_index_lba'])
        checked(new_track[0:2] == old_tracks[0][0:2] and new_track[2] == next_lba and
                new_track[3:5] == old_tracks[0][3:5] and new_track[5:8] == (0, 0, 0), 'Movie PCM descriptor')
        original_track = old_tracks[0]
        checked(original_track[4] == (original_track[3] + 126) // 127, 'Movie PCM sector count')
        old.seek(original_track[2] * 512); new.seek(new_track[2] * 512)
        remaining = original_track[3]
        for n in range(original_track[4]):
            x, y = old.read(512), new.read(512)
            checked(x == y, f'Movie PCM bytes {n}')
            validate_sector(y)
            used = min(127, remaining)
            checked(not any(y[used * 4:508]), f'Movie PCM padding {n}')
            remaining -= used
        checked(remaining == 0 and new.tell() == b['sectors'] * 512 and new.read(1) == b'', 'Movie PCM end')
        images = [r for r in records if r['kind'] == 'image']
        checked(len(images) == a['image_count'], 'Image count')
        for n, record in enumerate(images):
            d = old_desc[a['video_frames'] + n]
            raw = (folder / record['name']).read_bytes()
            checked(raw[:2] == b'BM' and struct.unpack_from('<I', raw, 2)[0] == len(raw), 'BMP signature/size')
            checked(struct.unpack_from('<IiiHHI', raw, 14) == (40, d[2], -d[3], 1, 32, 0), 'BMP format')
            checked(struct.unpack_from('<I', raw, 10)[0] == 54 and len(raw) == 54 + d[2] * d[3] * 4, 'BMP pixel bounds')
            old.seek(d[4] * 512); pixels = old.read(d[6] * 512)
            checked(zlib.crc32(pixels) == d[7], 'Source BMP CRC')
            for row in range(d[3]):
                checked(pixels[row * d[5] * 512:row * d[5] * 512 + d[2] * 4] ==
                        raw[54 + row * d[2] * 4:54 + (row + 1) * d[2] * 4], f'BMP row {n}/{row}')
        songs = [r for r in records if r['kind'] == 'audio']
        checked(len(songs) == a['music_count'], 'Song count')
        for record, d in zip(songs, old_tracks[1:]):
            with wave.open(str(folder / record['name']), 'rb') as wav:
                checked((wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes(), wav.getcomptype()) ==
                        (2, 2, 48000, d[3], 'NONE'), 'WAV format/length')
                old.seek(d[2] * 512); remaining = d[3]
                while remaining:
                    raw = old.read(512); validate_sector(raw); used = min(127, remaining)
                    checked(wav.readframes(used) == raw[:used * 4], 'WAV PCM samples')
                    remaining -= used
                checked(wav.readframes(1) == b'', 'WAV end')
            if d[7]:
                lines = (folder / record['name']).with_suffix('.lrc').read_text(encoding='ascii').splitlines()
                checked(len(lines) == d[7], 'LRC cue count')
                for n, line in enumerate(lines):
                    c = sector(old, d[6] + n)
                    old.seek((d[6] + n) * 512 + 16); text = old.read(c[3]).decode('ascii')
                    m = re.fullmatch(r'\[(\d+):(\d{2})\.(\d{3})\](.*)', line)
                    checked(m is not None, 'LRC syntax')
                    sample = ((int(m[1]) * 60 + int(m[2])) * 1000 + int(m[3])) * 48
                    checked(sample == c[1] and m[4] == text, 'LRC time/text')
    files = []
    for record in records:
        path = folder / record['name']
        checked(path.stat().st_size == record['bytes'], 'Manifest size ' + path.name)
        digest = sha(path)
        checked(digest == record['sha256'], 'Manifest SHA ' + path.name)
        files.append(dict(name=path.name, bytes=path.stat().st_size, sha256=digest, passed=True))
    source_sha = sha(source)
    checked(source_sha == manifest['source_sha256'], 'Original package SHA')
    return dict(passed=True, completed=datetime.now().astimezone().isoformat(),
                seconds=round(time.monotonic() - started, 3), source_sha256=source_sha,
                video_frames=b['video_frames'], movie_pcm_samples=b['audio_samples'], files=files,
                all_video_pixels_exact=True, all_audio_samples_exact=True, all_image_pixels_exact=True,
                all_cue_times_and_text_exact=True)


def main():
    parser = argparse.ArgumentParser(description='Read every extracted media byte back and compare with the original package.')
    parser.add_argument('source', type=Path)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.source, args.folder, json.loads(args.manifest.read_text(encoding='utf-8')))
    result['verifier_sha256'] = sha(Path(__file__))
    args.report.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

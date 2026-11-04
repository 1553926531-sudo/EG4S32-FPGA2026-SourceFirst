
from pathlib import Path
import struct
import wave
import zlib

from tfm_format import MAGIC, WIDTH, HEIGHT, PIXELS, checked_sector, validate_sector, read_bmp_source

IMAGE_MAGIC = int.from_bytes(b'IMG2', 'little')
AUDIO_MAGIC = int.from_bytes(b'AUD3', 'little')
CUE_MAGIC = int.from_bytes(b'CUE3', 'little')
MAX_SAMPLES = 48000 * 43200


def parse_header_v3(w):
    if w[:6] != (MAGIC, 3, WIDTH, HEIGHT, 1, PIXELS):
        raise ValueError('Invalid TFM3 header')
    if not 1 <= w[6] <= 1000000 or not 80 <= w[7] <= 60000 or not 1000 <= w[16] <= 60000:
        raise ValueError('Invalid TFM3 video length or frame period')
    if not 0 <= w[18] <= 600 or not 0 <= w[20] <= 600:
        raise ValueError('Invalid image or music count')
    if w[8:11] != (1, 1, 1 + w[6]) or w[19] != 1:
        raise ValueError('Invalid video/image index layout')
    if w[21] != 1 + w[6] + w[18] or w[22] != w[20] + 1:
        raise ValueError('Invalid audio index layout')
    if not w[21] + w[22] <= w[23] < w[11] < w[17] <= 200000000:
        raise ValueError('Invalid TFM3 metadata/payload bounds')
    if w[13:16] != (48000, 16, 2) or not 1 <= w[12] <= MAX_SAMPLES:
        raise ValueError('Invalid movie PCM format or length')
    return dict(version=3, video_frames=w[6], frame_ms=w[7], video_lba=1, frame_stride=1,
          image_lba=w[10], audio_lba=w[11], audio_samples=w[12], image_ms=w[16],
          sectors=w[17], image_count=w[18], music_count=w[20], audio_index_lba=w[21],
          audio_count=w[22], payload_lba=w[23], header_crc=w[127])


def cue_sector(index, sample, text):
    encoded = text.encode('ascii')
    if len(encoded) > 78 or any(c < 32 or c > 126 for c in encoded):
        raise ValueError('Each lyric cue must contain at most 78 printable ASCII characters')
    data = bytearray(checked_sector([CUE_MAGIC, sample, index, len(encoded)]))
    data[16:96] = encoded.ljust(80, b' ')
    struct.pack_into('<I', data, 508, zlib.crc32(data[:508]))
    return bytes(data)


def pack_v3(raw_video, video_size, pictures, tracks, output, frame_ms=125, image_ms=5000):
    
    raw_video, output = Path(raw_video), Path(output)
    width, height = video_size
    if not 1 <= width <= 2048 or not 1 <= height <= 2048:
        raise ValueError('Invalid raw source dimensions')
    frame_bytes = width * height * 3
    raw_bytes = raw_video.stat().st_size
    if raw_bytes == 0 or raw_bytes % frame_bytes:
        raise ValueError('Incomplete raw BGR24 video')
    frames = raw_bytes // frame_bytes
    audio_index = 1 + frames + len(pictures)
    next_lba = audio_index + len(tracks)
    audio_meta = []
    for track in tracks:
        with wave.open(str(track['wav']), 'rb') as w:
            if (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getcomptype()) != (2, 2, 48000, 'NONE'):
                raise ValueError('PCM must be 48 kHz / 16 bit / stereo')
            samples = w.getnframes()
        cues = track.get('cues', [])
        previous = -1
        for idx, (sample, text) in enumerate(cues):
            if not previous < sample < samples:
                raise ValueError('Lyric times must be ordered, unique and inside the track')
            cue_sector(idx, sample, text)
            previous = sample
        if not 0 <= track.get('background', 0) < max(1, len(pictures)) or len(cues) > 4096:
            raise ValueError('Invalid track background or lyric count')
        audio_meta.append(dict(samples=samples, sectors=(samples + 126) // 127,
                        lyric_lba=next_lba if cues else 0, cues=cues,
                        background=track.get('background', 0), wav=Path(track['wav'])))
        next_lba += len(cues)
    payload_lba = next_lba
    stride = (width + 127) // 128
    next_lba += frames * stride * height
    image_meta = []
    for path in pictures:
        w, h, payload = read_bmp_source(Path(path))
        image_meta.append((Path(path), w, h, next_lba, len(payload) // 512, zlib.crc32(payload)))
        next_lba += len(payload) // 512
    audio_lba = next_lba
    for track in audio_meta:
        track['lba'] = next_lba
        next_lba += track['sectors']
    header = checked_sector([MAGIC, 3, WIDTH, HEIGHT, 1, PIXELS, frames, frame_ms, 1, 1,
              1 + frames, audio_lba, audio_meta[0]['samples'], 48000, 16, 2, image_ms, next_lba,
              len(pictures), 1, len(tracks) - 1, audio_index, len(tracks), payload_lba])
    parse_header_v3(validate_sector(header))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('xb+') as f, raw_video.open('rb') as video:
        f.write(header)
                                                                      
        f.seek(payload_lba * 512)
        for idx in range(frames):
            raw = video.read(frame_bytes)
            if len(raw) != frame_bytes:
                raise ValueError('Raw video changed/truncated during packing')
            payload = bytearray(stride * 512 * height)
            for y in range(height):
                row = raw[y * width * 3:(y + 1) * width * 3]
                off = y * stride * 512
                payload[off:off + width * 4:4] = row[0::3]
                payload[off + 1:off + width * 4:4] = row[1::3]
                payload[off + 2:off + width * 4:4] = row[2::3]
            lba = f.tell() // 512
            f.write(payload)
            end = f.tell()
            f.seek((1 + idx) * 512)
            f.write(checked_sector([IMAGE_MAGIC, idx, width, height, lba, stride,
                                   stride * height, zlib.crc32(payload)]))
            f.seek(end)
            if idx % 4096 == 0:
                print(f'Packed video frame {idx}/{frames}', flush=True)
        if video.read(1):
            raise ValueError('Raw video grew during packing')
        for idx, (path, w, h, lba, sectors, crc) in enumerate(image_meta):
            _, _, payload = read_bmp_source(path)
            if zlib.crc32(payload) != crc or f.tell() != lba * 512:
                raise ValueError('Picture changed during packing')
            f.write(payload)
            end = f.tell()
            f.seek((1 + frames + idx) * 512)
            f.write(checked_sector([IMAGE_MAGIC, 0x80000000 | idx, w, h, lba, (w + 127) // 128, sectors, crc]))
            f.seek(end)
        for idx, track in enumerate(audio_meta):
            if f.tell() != track['lba'] * 512:
                raise ValueError('PCM layout mismatch')
            with wave.open(str(track['wav']), 'rb') as w:
                remaining = track['samples']
                while remaining:
                    used = min(127, remaining)
                    block = w.readframes(used)
                    if len(block) != used * 4:
                        raise ValueError('Truncated source PCM')
                    block = block.ljust(508, b'\0')
                    f.write(block + struct.pack('<I', zlib.crc32(block)))
                    remaining -= used
            end = f.tell()
            f.seek((audio_index + idx) * 512)
            f.write(checked_sector([AUDIO_MAGIC, idx, track['lba'], track['samples'], track['sectors'],
                    track['background'], track['lyric_lba'], len(track['cues'])]))
            if track['cues']:
                f.seek(track['lyric_lba'] * 512)
                for cue_idx, (sample, text) in enumerate(track['cues']):
                    f.write(cue_sector(cue_idx, sample, text))
            f.seek(end)
    return verify_package_v3(output, parse_header_v3(validate_sector(header)))


def verify_package_v3(path, h):
    next_lba = h['payload_lba']
    dimensions = []
    with Path(path).open('rb') as f:
        if Path(path).stat().st_size != h['sectors'] * 512:
            raise ValueError('TFM3 file length mismatch')
        for i in range(h['video_frames'] + h['image_count']):
            f.seek((1 + i) * 512)
            d = validate_sector(f.read(512))
            identity = i if i < h['video_frames'] else 0x80000000 | (i - h['video_frames'])
            if d[0] != IMAGE_MAGIC or d[1] != identity or not 1 <= d[2] <= 2048 or not 1 <= d[3] <= 2048:
                raise ValueError('Invalid TFM3 picture descriptor')
            if d[4] != next_lba or d[5] != (d[2] + 127) // 128 or d[6] != d[5] * d[3] or d[4] + d[6] > h['audio_lba']:
                raise ValueError('Invalid/overlapping TFM3 pixel extent')
            f.seek(d[4] * 512)
            payload = f.read(d[6] * 512)
            if zlib.crc32(payload) != d[7] or any(payload[3::4]):
                raise ValueError('TFM3 pixel CRC/X mismatch')
            stride = d[5] * 512
            if any(any(payload[y * stride + d[2] * 4:(y + 1) * stride]) for y in range(d[3])):
                raise ValueError('Nonzero source row padding')
            if i >= h['video_frames']:
                dimensions.append([d[2], d[3]])
            next_lba += d[6]
        if next_lba != h['audio_lba']:
            raise ValueError('Undefined pixel data')
        next_cue = h['audio_index_lba'] + h['audio_count']
        tracks = []
        for idx in range(h['audio_count']):
            f.seek((h['audio_index_lba'] + idx) * 512)
            d = validate_sector(f.read(512))
            if d[0] != AUDIO_MAGIC or d[1] != idx or d[2] != next_lba or not 1 <= d[3] <= MAX_SAMPLES:
                raise ValueError('Invalid TFM3 audio descriptor')
            if d[4] != (d[3] + 126) // 127 or d[4] > h['sectors'] - d[2] or d[5] >= max(1, h['image_count']) or d[7] > 4096:
                raise ValueError('Invalid PCM extent/background/lyric length')
            if idx == 0 and (d[2], d[3]) != (h['audio_lba'], h['audio_samples']):
                raise ValueError('Movie PCM disagrees with header')
            if (d[7] == 0 and d[6] != 0) or (d[7] and d[6] != next_cue):
                raise ValueError('Invalid lyric extent')
            previous = -1
            for cue_idx in range(d[7]):
                f.seek((d[6] + cue_idx) * 512)
                block = f.read(512)
                c = validate_sector(block)
                if c[0] != CUE_MAGIC or c[2] != cue_idx or not previous < c[1] < d[3] or c[3] > 78:
                    raise ValueError('Invalid/unsorted lyric cue')
                if any(x < 32 or x > 126 for x in block[16:96]) or block[16+c[3]:96].strip(b' '):
                    raise ValueError('Invalid lyric text/padding')
                previous = c[1]
            next_cue += d[7]
            if next_cue > h['payload_lba']:
                raise ValueError('Lyrics overlap pixels')
            f.seek(d[2] * 512)
            remaining = d[3]
            while remaining:
                block = f.read(512)
                validate_sector(block)
                used = min(127, remaining)
                if any(block[used * 4:508]):
                    raise ValueError('Nonzero PCM tail padding')
                remaining -= used
            tracks.append(dict(samples=d[3], cues=d[7], background=d[5]))
            next_lba += d[4]
        if next_lba != h['sectors'] or next_cue != h['payload_lba']:
            raise ValueError('Undefined trailing PCM/metadata')
    return dict(h, source_dimensions=dimensions, tracks=tracks)

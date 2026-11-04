
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import struct
import wave
import zlib

from tfm_format import checked_sector, parse_header, validate_sector
from tfm3 import IMAGE_MAGIC, AUDIO_MAGIC, CUE_MAGIC


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_at(f, lba):
    f.seek(lba * 512)
    return validate_sector(f.read(512))


def read_pixels(f, descriptor):
    d = descriptor
    if d[0] != IMAGE_MAGIC or not 1 <= d[2] <= 2048 or not 1 <= d[3] <= 2048:
        raise ValueError('Invalid pixel descriptor')
    if d[5] != (d[2] + 127) // 128 or d[6] != d[5] * d[3]:
        raise ValueError('Invalid pixel stride')
    f.seek(d[4] * 512)
    data = f.read(d[6] * 512)
    if len(data) != d[6] * 512 or zlib.crc32(data) != d[7] or any(data[3::4]):
        raise ValueError('Invalid source pixels or CRC')
    return data


def pcm_blocks(f, d):
    if d[0] != AUDIO_MAGIC or d[4] != (d[3] + 126) // 127:
        raise ValueError('Invalid audio descriptor')
    f.seek(d[2] * 512)
    remaining = d[3]
    while remaining:
        raw = f.read(512)
        validate_sector(raw)
        used = min(127, remaining)
        if any(raw[used * 4:508]):
            raise ValueError('Nonzero final PCM padding')
        yield raw, used
        remaining -= used


def extract(source, output, image_names=None, song_names=None):
    source, output = Path(source), Path(output)
    output.mkdir(parents=True, exist_ok=False)
    records = []
    with source.open('rb') as f:
        h = parse_header(f.read(512))
        if h.get('version') != 3 or source.stat().st_size != h['sectors'] * 512:
            raise ValueError('Requires a complete TFM3 package')
        descriptors = [read_at(f, 1 + n) for n in range(h['video_frames'] + h['image_count'])]
        tracks = [read_at(f, h['audio_index_lba'] + n) for n in range(h['audio_count'])]
        image_names = image_names or [f'{n+1:02d}_IMAGE.bmp' for n in range(h['image_count'])]
        song_names = song_names or [f'{n+1:02d}_AUDIO.wav' for n in range(h['music_count'])]
        if len(image_names) != h['image_count'] or len(song_names) != h['music_count']:
            raise ValueError('Name counts disagree with source media')
        movie = output / '00_INTOUCHABLE.TFV'
        payload_lba = h['video_frames'] + 2
        next_lba = payload_lba
        movie_descriptors = []
        for n, old in enumerate(descriptors[:h['video_frames']]):
            if old[1] != n:
                raise ValueError('Invalid source movie index')
            d = list(old[:8]); d[4] = next_lba
            movie_descriptors.append(checked_sector(d))
            next_lba += d[6]
        audio_lba = next_lba
        movie_audio = tracks[0]
        if movie_audio[1] != 0 or movie_audio[3] != h['audio_samples']:
            raise ValueError('Invalid movie sound identity')
        header = checked_sector([int.from_bytes(b'TFM1', 'little'), 3, 1280, 800, 1, 1024000,
            h['video_frames'], h['frame_ms'], 1, 1, 1 + h['video_frames'], audio_lba,
            movie_audio[3], 48000, 16, 2, h['image_ms'], audio_lba + movie_audio[4],
            0, 1, 0, 1 + h['video_frames'], 1, payload_lba])
        parse_header(header)
        movie_audio_descriptor = checked_sector([AUDIO_MAGIC, 0, audio_lba,
            movie_audio[3], movie_audio[4], 0, 0, 0])
        with movie.open('xb') as out:
            out.write(header)
            for d in movie_descriptors:
                out.write(d)
            out.write(movie_audio_descriptor)
            for n, d in enumerate(descriptors[:h['video_frames']]):
                out.write(read_pixels(f, d))
                if n % 4096 == 0:
                    print(f'Video {n}/{h["video_frames"]}', flush=True)
            for raw, _ in pcm_blocks(f, movie_audio):
                out.write(raw)
        records.append(dict(name=movie.name, kind='video', frames=h['video_frames'],
                            pcm_samples=movie_audio[3], exact_source_pixels=True, exact_source_pcm=True))
        for n, (d, name) in enumerate(zip(descriptors[h['video_frames']:], image_names)):
            if d[1] != (0x80000000 | n):
                raise ValueError('Invalid image identity')
            raw = read_pixels(f, d)
            pixels = b''.join(raw[y*d[5]*512:y*d[5]*512+d[2]*4] for y in range(d[3]))
            header = bytearray(54)
            struct.pack_into('<2sI4xI', header, 0, b'BM', 54 + len(pixels), 54)
            struct.pack_into('<IiiHHII', header, 14, 40, d[2], -d[3], 1, 32, 0, len(pixels))
            path = output / name
            with path.open('xb') as out:
                out.write(header); out.write(pixels)
            records.append(dict(name=name, kind='image', dimensions=[d[2],d[3]],
                                pixel_sha256=hashlib.sha256(pixels).hexdigest(), exact_source_pixels=True))
        for n, (d, name) in enumerate(zip(tracks[1:], song_names)):
            path = output / name
            sound_hash = hashlib.sha256()
            with wave.open(str(path), 'wb') as out:
                out.setparams((2,2,48000,0,'NONE','PCM'))
                for raw, used in pcm_blocks(f, d):
                    pcm = raw[:used*4]; out.writeframesraw(pcm); sound_hash.update(pcm)
            records.append(dict(name=name, kind='audio', samples=d[3],
                                pcm_sha256=sound_hash.hexdigest(), exact_source_pcm=True))
            if d[7]:
                lines = []
                previous = -1
                for cue in range(d[7]):
                    f.seek((d[6]+cue)*512); raw=f.read(512); c=validate_sector(raw)
                    if c[0] != CUE_MAGIC or c[2] != cue or not previous < c[1] < d[3] or c[3] > 78:
                        raise ValueError('Invalid cue identity/time/length')
                    text=raw[16:16+c[3]].decode('ascii')
                    if any(ord(ch)<32 or ord(ch)>126 for ch in text) or c[1]%48:
                        raise ValueError('Cue cannot be represented exactly by millisecond ASCII LRC')
                    milliseconds=c[1]//48; minutes=milliseconds//60000
                    lines.append(f'[{minutes:02d}:{milliseconds//1000%60:02d}.{milliseconds%1000:03d}]{text}\n')
                    previous=c[1]
                lrc=path.with_suffix('.lrc'); lrc.write_text(''.join(lines),encoding='ascii',newline='\n')
                records.append(dict(name=lrc.name,kind='lyrics',cues=d[7],exact_source_cues=True))
    for record in records:
        path=output/record['name']; record.update(bytes=path.stat().st_size,sha256=digest(path))
    return dict(created=datetime.now().astimezone().isoformat(),source=str(source),
                source_bytes=source.stat().st_size,source_sha256=digest(source),
                output=str(output),files=records)


def main():
    parser=argparse.ArgumentParser(description='Extract exact source pixels, PCM and timed cues into independently playable files.')
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--final-names',action='store_true')
    args=parser.parse_args()
    images=['01_CAMPUS.bmp','02_LANDSCAPE.bmp','03_MAPLE.bmp','04_SNOW.bmp','05_LOGO.bmp'] if args.final_names else None
    songs=['01_DU_KOU.wav','02_HOTEL_CALIFORNIA.wav'] if args.final_names else None
    result=extract(args.source,args.output,images,songs)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()

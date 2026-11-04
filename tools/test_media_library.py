
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import time
import zlib

from test_file_system import Disk
from test_file_adapter import bmp, wave, install

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/library'


def sector(words):
    raw = struct.pack('<' + 'I' * len(words), *words).ljust(508, b'\0')
    return raw + struct.pack('<I', zlib.crc32(raw))


def container(legacy=False):
    frames = 4
    pictures = 2 if legacy else 0
    songs = 1 if legacy else 0
    lengths = [15360] + ([52000] if legacy else [])
    index = 1 + frames + pictures
    payload = index + songs + 1
    audio = payload + frames + pictures
    ends = [audio]
    for n in lengths:
        ends.append(ends[-1] + (n + 126) // 127)
    header = sector([0x314d4654, 3, 1280, 800, 1, 1024000, frames, 80,
                     1, 1, 1 + frames, audio, lengths[0], 48000, 16, 2,
                     5000, ends[-1], pictures, 1, songs, index, songs + 1, payload])
    colors = [769 * (n + 1) for n in range(frames)] + [0x112233, 0x44aa55][:pictures]
    blocks = [struct.pack('<I', color).ljust(512, b'\0') for color in colors]
    desc = [sector([0x32474d49, n if n < frames else 0x80000000 | (n - frames),
                    1, 1, payload + n, 1, 1, zlib.crc32(block)]) for n, block in enumerate(blocks)]
    tracks = [sector([0x33445541, n, ends[n], count, ends[n + 1] - ends[n], 0, 0, 0])
              for n, count in enumerate(lengths)]
    sound = []
    for track, count in enumerate(lengths):
        _, words = wave(count)
        for start in range(0, count, 127):
            sound.append(sector(words[start:start + 127]))
    return header + b''.join(desc + tracks + blocks + sound)


def fixture(exfat, mode):
    d = Disk(exfat, 2048 if exfat else 0, 0)
    entries = []
    if mode != 'empty':
        if mode == 'legacy':
            files = [('Old compatible.PAK', b'OLD     PAK', 511, 20, container(True))]
        else:
            b0, _ = bmp(1, 1, 24)
            b1, _ = bmp(1, 1, 32, True)
            b0 = b0[:54] + struct.pack('<I', 0x112233)
            b1 = b1[:54] + struct.pack('<I', 0x44aa55)
            bad = bytearray(b0)
            struct.pack_into('<I', bad, 30, 1)
            pcm, _ = wave(52000)
            bad_movie = bytearray(container())
            bad_movie[508] ^= 1
            files = [('Movie.TFV', b'MOVIE   TFV', 0, 20, container()),
                     ('Broken movie.TFV', b'BROKEN  TFV', 1, 1600, bad_movie),
                     ('First image.bmp', b'FIRST   BMP', 128, 400, b0),
                     ('Second image.BMP', b'SECOND  BMP', 129, 410, b1),
                     ('Broken image.bmp', b'BROKEN  BMP', 130, 420, bad),
                     ('A song.wav', b'ASONG   WAV', 256, 500, pcm),
                     ('A song.lrc', b'ASONG   LRC', 384, 1400,
                      b'[00:00.000]FIRST\n[00:01.000]SECOND\n[00:01.060]TAIL\n')]
        for name, alias, fid, cluster, raw in files:
            entries += d.file(name, alias, fid, [cluster], len(raw))
            install(d, cluster, raw)
    d.directory([2, 9], entries)
    path = OUT / (('exfat_' if exfat else 'fat32_') + mode)
    path.mkdir(parents=True, exist_ok=True)
    lbas = sorted(d.sectors)
    (path / 'lbas.hex').write_text(''.join(f'{n:08x}\n' for n in lbas))
    (path / 'disk.hex').write_text(''.join(f'{v:08x}\n' for lba in lbas
                                         for v in struct.unpack('<128I', d.sectors[lba])))
    return path, len(lbas)


def main():
    parser = argparse.ArgumentParser(description='Exercise the real disk parser, format adapter and playback engine together.')
    parser.add_argument('--case', choices=['fat32_native', 'exfat_native', 'fat32_legacy', 'exfat_empty'])
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--simulator', choices=['icarus', 'verilator'], default='icarus')
    parser.add_argument('--pcm-period',type=int,default=256)
    parser.add_argument('--sd-gap',type=int,default=0)
    parser.add_argument('--production',action='store_true',help='Full 1280x800 frame writes with the production 2048-sample queue')
    args = parser.parse_args()
    global OUT
    OUT = OUT.with_name('library_production2048' if args.production else 'library_buffer2048')
    if args.simulator == 'verilator':
        OUT = OUT.with_name(OUT.name+'_fast')
    OUT.mkdir(parents=True, exist_ok=True)
    iv = ROOT / 'tools/_iverilog/bin/iverilog.exe'
    vv = iv.with_name('vvp.exe')
    sources = [ROOT / 'rtl' / name for name in ('eg_memory.v', 'image_scaler.v',
               'storage_cpu.v', 'media_storage.v',
               'media_sequencer_v2.v', 'media_library.v')]
    compiled = sources + [ROOT / 'tests/tb_media_library.v']
    sources = compiled + [Path(__file__).resolve(), ROOT / 'firmware/storage.c',
                          ROOT / 'firmware/start.S', ROOT / 'firmware/storage.ld']
    sources += [ROOT / f'rtl/storage_rom_{bank}.hex' for bank in range(3)]
    digest = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    target = OUT / 'library.vvp'
    if args.simulator == 'verilator':
        from run_verilated import compile_model
        target = compile_model('tb_media_library', compiled, OUT / 'compiled',
                               parameters={'DEST_WIDTH':1280,'DEST_HEIGHT':800} if args.production else None)
    else:
        subprocess.run([str(iv), '-g2005', '-s', 'tb_media_library', '-o', str(target),
                        *(['-Ptb_media_library.DEST_WIDTH=1280','-Ptb_media_library.DEST_HEIGHT=800'] if args.production else []),
                        *map(str, compiled)], check=True)
    results = []
    for exfat, mode in [(False, 'native'), (True, 'native'), (False, 'legacy'), (True, 'empty')]:
        case = ('exfat_' if exfat else 'fat32_') + mode
        if args.case and args.case != case:
            continue
        path, sectors = fixture(exfat, mode)
        for bank in range(3):
            shutil.copy2(ROOT / f'rtl/storage_rom_{bank}.hex', path / f'storage_rom_{bank}.hex')
        started = time.monotonic()
        timed_out = False
        returncode = None
        print('START', case, flush=True)
        with (path / 'run.log').open('w', encoding='utf-8') as log:
            try:
                result = subprocess.run(([str(target)] if args.simulator == 'verilator' else [str(vv), str(target)]) + [f'+sectors={sectors}',
                                         f'+mode={0 if mode == "native" else 1 if mode == "legacy" else 2}',
                                         f'+pcm_period={args.pcm_period}',f'+sd_gap={args.sd_gap}'],
                                        cwd=path, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=args.timeout)
                returncode = result.returncode
            except subprocess.TimeoutExpired:
                timed_out = True
        output = (path / 'run.log').read_text(encoding='utf-8')
        changed = [str(p) for p in sources if hashlib.sha256(p.read_bytes()).hexdigest() != digest[str(p.relative_to(ROOT))]]
        passed = not timed_out and returncode == 0 and 'PASS media library' in output and 'FAIL' not in output and not changed
        row = dict(case=path.name, simulator=args.simulator, production=args.production,pcm_period=args.pcm_period,sd_gap=args.sd_gap,
                   passed=passed, stdout=output, timed_out=timed_out,
                   source_sha256=digest, source_changed=changed, seconds=round(time.monotonic() - started, 3))
        results.append(row)
        result_path = OUT / ((args.case + '_result.json') if args.case else 'results.json')
        result_path.write_text(json.dumps(results, indent=2))
        print(path.name, 'PASS' if passed else 'FAIL', output.strip(), flush=True)
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    sys.exit(main())

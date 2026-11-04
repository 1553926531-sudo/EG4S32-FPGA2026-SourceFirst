from pathlib import Path
import json
import struct
import subprocess
import sys
import hashlib

from test_file_system import Disk, OUT as FS_OUT

ROOT = Path(__file__).resolve().parents[1]
OUT = FS_OUT.parent / 'adapter'
PIXELS = 8192
AUDIO = 0x100000


def bmp(width, height, bits, top_down=False):
    stride = (width * (bits // 8) + 3) & ~3
    header = struct.pack('<2sIHHI', b'BM', 54 + stride * height, 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, width, -height if top_down else height, 1, bits, 0,
                          stride * height, 2835, 2835, 0, 0)
    pixels = [[((x * 11 + y) & 255) | (((x + y * 27) & 255) << 8) |
               (((x * 3 + y * 2) & 255) << 16) for x in range(width)] for y in range(height)]
    rows = []
    for y in (range(height) if top_down else reversed(range(height))):
        row = b''.join(struct.pack('<I', p | (0xaa000000 if bits == 32 else 0))[:bits // 8] for p in pixels[y])
        rows.append(row.ljust(stride, b'\x99'))
    return header + b''.join(rows), pixels


def wave(samples, malformed=False):
    raw = b''.join(struct.pack('<hh', (n * 29) % 32768, -((n * 41) % 32768)) for n in range(samples))
    chunks = b'JUNK' + struct.pack('<I', 1) + b'a\0'
    chunks += b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 2, 44100 if malformed else 48000, 192000, 4, 16)
    chunks += b'LIST' + struct.pack('<I', 3) + b'ABC\0'
    chunks += b'data' + struct.pack('<I', len(raw)) + raw
    return b'RIFF' + struct.pack('<I', len(chunks) + 4) + b'WAVE' + chunks, list(struct.unpack('<' + 'I' * samples, raw))


def install(d, cluster, raw):
    clusters = []
    required = (len(raw) + 511) // 512
    for i in range(required):
        c = cluster + i * 2
        clusters.append(c)
        d.sectors[d.cluster_lba(c)] = bytearray(raw[i * 512:i * 512 + 512].ljust(512, b'\0'))
    d.chain(clusters)


def header(samples, cues):
    audio_sectors = (samples + 126) // 127
    values = [0x314d4654, 3, 1280, 800, 1, 1024000, 1, 1000, 1, 1, 2, AUDIO,
              samples, 48000, 16, 2, 5000, AUDIO + audio_sectors, 1, 1, 1, 3, 2, 32 + cues]
    return values + [0] * (128 - len(values))


def descriptor(lba, width, height):
    stride = (width + 127) // 128
    return [0x32474d49, 0 if lba == 1 else 0x80000000, width, height, PIXELS, stride, stride * height] + [0] * 121


def make_case(exfat, malformed=''):
    d = Disk(exfat, 2048 if exfat else 0, 0)
    image0, pixels0 = bmp(131, 3, 24)
    image1, pixels1 = bmp(3, 2, 32, True)
    pcm, samples = wave(1000, malformed == 'wav')
    cues = [(0, 'First line'), (480, 'Two lines can contain a long but bounded ASCII sentence.'), (960, '')]
    lrc = b'[ar:RTL fixture]\r\n' + b''.join(f'[{time // 2880000:02d}:{(time // 48000) % 60:02d}.{(time // 48) % 1000:03d}]{text}\r\n'.encode() for time, text in cues)
    entries = []
    for name, alias, fid, cluster, raw in [
            ('Image one.bmp', b'IMAGE1  BMP', 128, 20, image0),
            ('Image two.BMP', b'IMAGE2  BMP', 129, 50, image1),
            ('A song.WAV', b'ASONG   WAV', 256, 70, pcm),
            ('A song.LRC', b'ASONG   LRC', 384, 100, lrc)]:
        entries += d.file(name, alias, fid, [cluster], len(raw))
        install(d, cluster, raw)
    if malformed == 'bmp':
        struct.pack_into('<I', d.sectors[d.cluster_lba(20)], 30, 1)
    d.directory([2, 9], entries)
    path = OUT / ('exfat' if exfat else 'fat32') / (malformed or 'valid')
    path.mkdir(parents=True, exist_ok=True)
    lbas = sorted(d.sectors)
    (path / 'lbas.hex').write_text(''.join(f'{v:08x}\n' for v in lbas))
    (path / 'disk.hex').write_text(''.join(f'{v:08x}\n' for lba in lbas for v in struct.unpack('<128I', d.sectors[lba])))
    commands, golden = [], []
    for fid, kind, width, height, pixels, audio in [(128, 1, 131, 3, pixels0, [0]),
                                                   (129, 1, 3, 2, pixels1, [0]),
                                                   (256, 2, 1, 1, [[0x101820]], samples)]:
        ccount = len(cues) if kind == 2 else 0
        stride = (width + 127) // 128
        queries = [0, 1, 2]
        queries += list(range(PIXELS, PIXELS + stride * height))
        if kind == 2:
            queries += [3, 4] + list(range(AUDIO, AUDIO + (len(audio) + 126) // 127))
            queries += [32, 33, 34, 32, 34, 33]
        for lba in queries:
            commands.extend([fid, kind, lba])
            if lba == 0:
                words = header(len(audio), ccount)
            elif lba in (1, 2):
                words = descriptor(lba, width, height)
            elif lba in (3, 4):
                words = [0x33445541, lba - 3, AUDIO, len(audio), (len(audio) + 126) // 127, 0, 32, ccount] + [0] * 120
            elif lba >= AUDIO:
                start = (lba - AUDIO) * 127
                block = audio[start:start + 127]
                words = block + [0] * (128 - len(block))
            elif lba >= PIXELS:
                row, chunk = divmod(lba - PIXELS, stride)
                words = pixels[row][chunk * 128:chunk * 128 + 128]
                words += [0] * (128 - len(words))
            else:
                time, text = cues[lba - 32]
                words = [0x33455543, time, lba - 32, len(text)]
                words += list(struct.unpack('<20I', text.encode().ljust(80, b' ')))
                words += [0] * (128 - len(words))
            golden.extend(words)
    (path / 'commands.hex').write_text(''.join(f'{v:08x}\n' for v in commands))
    (path / 'golden.hex').write_text(''.join(f'{v:08x}\n' for v in golden))
    return path, len(lbas), len(commands) // 3


def main():
    import shutil,hashlib
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('--simulator',choices=['icarus','verilator'],default='icarus')
    args=parser.parse_args()
    out = ROOT / 'verification/revision_20261103_native_files/storage'
    if args.simulator=='verilator':out=out.with_name('storage_fast')
    out.mkdir(parents=True, exist_ok=True)
    iv=ROOT/'tools/_iverilog/bin/iverilog.exe'
    vv=iv.with_name('vvp.exe')
    target=out/'storage.vvp'
    names=('eg_memory.v','storage_cpu.v','media_storage.v')
    sources=[ROOT/'rtl'/name for name in names]+[ROOT/'tests/tb_media_storage.v']
    compiled=list(sources)
    sources += [Path(__file__).resolve(), ROOT/'firmware/storage.c',ROOT/'firmware/start.S',ROOT/'firmware/storage.ld']
    sources += list((ROOT/'rtl').glob('storage_rom_*.hex'))
    hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
    if args.simulator=='verilator':
        from run_verilated import compile_model
        target=compile_model('tb_media_storage',compiled,out/'compiled')
    else:
        subprocess.run([str(iv),'-g2005','-s','tb_media_storage','-o',str(target),*map(str,compiled)],check=True)
    results=[]
    for exfat,malformed in [(False,''),(True,''),(False,'bmp'),(True,'wav')]:
        fixture,nsectors,ncommands=make_case(exfat,malformed)
        path=out/('exfat' if exfat else 'fat32')/(malformed or 'valid')
        path.mkdir(parents=True,exist_ok=True)
        for f in fixture.glob('*.hex'):shutil.copy2(f,path/f.name)
        for f in (ROOT/'rtl').glob('storage_rom_*.hex'):shutil.copy2(f,path/f.name)
        error=0x54 if malformed=='bmp' else 0x56 if malformed=='wav' else 0
        r=subprocess.run(([str(target)] if args.simulator=='verilator' else [str(vv),str(target)])+[f'+sectors={nsectors}',f'+commands={ncommands}',f'+error={error}'],
                         cwd=path,capture_output=True,text=True,timeout=900)
        changed=[str(f.relative_to(ROOT)) for f in sources if hashlib.sha256(f.read_bytes()).hexdigest()!=hashes[str(f.relative_to(ROOT))]]
        passed=not changed and r.returncode==0 and 'PASS media storage' in r.stdout and 'FAIL' not in r.stdout
        item=dict(path=str(path),simulator=args.simulator,passed=passed,stdout=r.stdout,stderr=r.stderr,
                  source_sha256=hashes,source_changed=changed)
        results.append(item)
        (path/'run.log').write_text(r.stdout+r.stderr)
        (out/'results.json').write_text(json.dumps(results,indent=2))
        print(path, 'PASS' if passed else 'FAIL',r.stdout+r.stderr,flush=True)
    return 0 if all(r['passed'] for r in results) else 1


if __name__=='__main__':
    raise SystemExit(main())

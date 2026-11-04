
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import argparse
import os
import shutil

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description='Build the RV32 storage firmware ROMs')
    parser.add_argument('--zig', type=Path)
    args = parser.parse_args()
    out = ROOT / 'verification/firmware'
    out.mkdir(parents=True, exist_ok=True)
    zig = args.zig or Path(os.environ.get('TF_ZIG') or shutil.which('zig') or str(ROOT/'tools/_zig/ziglang/zig.exe'))
    if not zig.is_file():
        parser.error('Specify Zig 0.13.0 with --zig or TF_ZIG')
    if subprocess.check_output([str(zig), 'version'], text=True).strip() != '0.13.0':
        parser.error('Zig 0.13.0 is required for reproducible ROMs')
    elf = out / 'storage.elf'
    sources = [ROOT / 'firmware' / name for name in ('start.S', 'storage.c', 'storage.ld')]
    command = [str(zig), 'cc', '-target', 'riscv32-freestanding-none', '-mcpu=baseline_rv32+m-a-f-d-c-zicsr', '-mabi=ilp32',
               '-Oz', '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-fno-unwind-tables',
               '-fno-asynchronous-unwind-tables', '-nostdlib', '-mno-relax',
               '-Wl,--gc-sections',
               '-T', str(sources[2]), str(sources[0]), str(sources[1]), '-o', str(elf)]
    subprocess.run(command, check=True)
    data = elf.read_bytes()
    assert data[:6] == b'\x7fELF\x01\x01'
    phoff = struct.unpack_from('<I', data, 28)[0]
    phsize, phcount = struct.unpack_from('<HH', data, 42)
    rom = bytearray(12 * 1024)
    used = 0
    for index in range(phcount):
        kind, offset, virtual, physical, filesz, memsz, flags, align = struct.unpack_from('<8I', data, phoff + index * phsize)
        if kind == 1 and filesz:
            if physical + filesz > len(rom):
                raise ValueError('ROM overflow')
            rom[physical:physical + filesz] = data[offset:offset + filesz]
            used = max(used, physical + filesz)
    for bank in range(3):
        block = rom[bank * 4096:(bank + 1) * 4096]
        words = struct.unpack('<1024I', block)
        (ROOT / 'rtl' / f'storage_rom_{bank}.hex').write_text(''.join(f'{n:08x}\n' for n in words), encoding='ascii')
        mif = 'DEPTH = 1024;\nWIDTH = 32;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n'
        mif += ''.join(f'{i:03X} : {n:08X};\n' for i, n in enumerate(words)) + 'END;\n'
        (ROOT / 'rtl' / f'storage_rom_{bank}.mif').write_text(mif, encoding='ascii')
    manifest = dict(rom_bytes=used, capacity=len(rom), rom_sha256=hashlib.sha256(rom).hexdigest(),
                    command=command, sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()

from pathlib import Path
import json
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/fs'


def u32(buf, off, value):
    struct.pack_into('<I', buf, off, value)


def short_entry(name, cluster, size, directory=False):
    b = bytearray(32)
    b[:11] = name
    b[11] = 0x10 if directory else 0x20
    struct.pack_into('<H', b, 20, cluster >> 16)
    struct.pack_into('<H', b, 26, cluster & 65535)
    u32(b, 28, size)
    return b


def fat_name(name, alias, cluster, size, directory=False):
    checksum = 0
    for byte in alias:
        checksum = (((checksum & 1) << 7) | (checksum >> 1)) + byte
        checksum &= 255
    chars = list(struct.unpack('<' + 'H' * len(name), name.encode('utf-16le')))
    chars.append(0)
    entries = []
    groups = (len(chars) + 12) // 13
    for seq in range(groups, 0, -1):
        b = bytearray(32)
        b[0] = seq | (0x40 if seq == groups else 0)
        b[11] = 0x0f
        b[13] = checksum
        for i, off in enumerate([1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]):
            index = (seq - 1) * 13 + i
            struct.pack_into('<H', b, off, chars[index] if index < len(chars) else 65535)
        entries.append(b)
    return entries + [short_entry(alias, cluster, size, directory)]


def ex_name(name, cluster, size, contiguous=False, directory=False):
    words = list(struct.unpack('<' + 'H' * len(name), name.encode('utf-16le')))
    b = bytearray(32)
    b[0] = 0x85
    b[1] = 1 + (len(words) + 14) // 15
    struct.pack_into('<H', b, 4, 0x10 if directory else 0x20)
    stream = bytearray(32)
    stream[0] = 0xc0
    stream[1] = 3 if contiguous else 1
    stream[3] = len(words)
    struct.pack_into('<Q', stream, 8, size)
    u32(stream, 20, cluster)
    struct.pack_into('<Q', stream, 24, size)
    entries = [b, stream]
    for start in range(0, len(words), 15):
        e = bytearray(32)
        e[0] = 0xc1
        for i, word in enumerate(words[start:start + 15]):
            struct.pack_into('<H', e, 2 + 2 * i, word)
        entries.append(e)
    checksum = 0
    for i, byte in enumerate(b''.join(entries)):
        if i not in (2, 3):
            checksum = ((((checksum & 1) << 15) | (checksum >> 1)) + byte) & 65535
    struct.pack_into('<H', b, 2, checksum)
    return entries


class Disk:
    def __init__(self, exfat, partition, shift):
        self.sectors = {}
        self.exfat = exfat
        self.shift = shift
        self.start = partition
        self.fat = partition + 32
        self.heap = self.fat + 1024
        self.files = []
        boot = bytearray(512)
        if partition:
            mbr = bytearray(512)
            mbr[450] = 7 if exfat else 12
            u32(mbr, 454, partition)
            mbr[510:512] = b'\x55\xaa'
            self.sectors[0] = mbr
        if exfat:
            boot[:11] = b'\xeb\x76\x90EXFAT   '
            struct.pack_into('<Q', boot, 64, partition)
            struct.pack_into('<Q', boot, 72, 1056 + (70000 << shift))
            struct.pack_into('<IIIII', boot, 80, 32, 1024, 1056, 70000, 2)
            boot[108:111] = bytes([9, shift, 1])
        else:
            boot[:3] = b'\xeb\x58\x90'
            struct.pack_into('<HBHBHH', boot, 11, 512, 1 << shift, 32, 1, 0, 0)
            u32(boot, 32, 1056 + (70000 << shift))
            u32(boot, 36, 1024)
            u32(boot, 44, 2)
            boot[82:90] = b'FAT32   '
        boot[510:512] = b'\x55\xaa'
        self.sectors[partition] = boot
        self.chain([2, 9])
        self.chain([15])

    def chain(self, clusters):
        for i, cluster in enumerate(clusters):
            lba = self.fat + cluster // 128
            b = self.sectors.setdefault(lba, bytearray(512))
            u32(b, (cluster % 128) * 4, clusters[i + 1] if i + 1 < len(clusters) else 0xffffffff)

    def cluster_lba(self, c):
        return self.heap + ((c - 2) << self.shift)

    def directory(self, clusters, entries):
        data = b''.join(entries) + bytes(32)
        capacity = len(clusters) * (512 << self.shift)
        if len(data) > capacity:
            raise ValueError('directory overflow')
        data = data.ljust(capacity, b'\0')
        for ci, c in enumerate(clusters):
            for s in range(1 << self.shift):
                off = (ci * (1 << self.shift) + s) * 512
                self.sectors[self.cluster_lba(c) + s] = bytearray(data[off:off + 512])

    def file(self, name, alias, fid, clusters, size, contiguous=False, parent=2):
        self.chain(clusters)
        raw = bytes(((fid * 7 + pos * 13 + (pos >> 8)) & 255) for pos in range(size))
        for ci, c in enumerate(clusters):
            for s in range(1 << self.shift):
                off = (ci * (1 << self.shift) + s) * 512
                self.sectors[self.cluster_lba(c) + s] = bytearray(raw[off:off + 512].ljust(512, b'\0'))
        self.files.append((fid, name, raw))
        if self.exfat:
            return ex_name(name, clusters[0], size, contiguous)
        if alias is None:
            base, ext = name.split('.')
            return [short_entry((base.ljust(8) + ext.ljust(3)).encode(), clusters[0], size)]
        return fat_name(name, alias, clusters[0], size)


def make_case(name, exfat, partition, shift, corrupt=''):
    d = Disk(exfat, partition, shift)
    size = (512 << shift) * 3 - 37
    entries = d.file('MOVIE.TFV', None, 0, [40, 55, 43], size)
    entries += d.file('A picture with a longer name.bmp', b'APIC~1  BMP', 128, [60, 61, 62], size, True)
    entries += d.file('Song with a long title.WaV', b'SONG~1  WAV', 256, [70, 72, 75], size)
    entries += d.file('Song with a long title.lrc', b'SONG~1  LRC', 384, [80], 99)
    entries += d.file('TF2026_FINAL.PAK', b'TF2026~1PAK', 511, [90, 94, 93], size)
    if exfat:
        entries += ex_name('Sub directory', 15, 512 << shift, False, True)
    else:
        entries += fat_name('Sub directory', b'SUBDIR     ', 15, 0, True)
    sub = d.file('OTHER.BMP', None, 129, [100], 17)
    sub += d.file('other track.wav', b'OTHER~1 WAV', 257, [105], 811 if shift else 511)
    d.directory([2, 9], entries)
    d.directory([15], sub)
    if corrupt == 'signature':
        d.sectors[partition][510] = 0
    elif corrupt == 'geometry':
        u32(d.sectors[partition], 88 if exfat else 32, 33)
    elif corrupt == 'checksum':
        d.sectors[d.cluster_lba(2)][2] ^= 1
    elif corrupt == 'filechain':
        u32(d.sectors[d.fat], 40 * 4, 40)
    directory = OUT / name
    directory.mkdir(parents=True, exist_ok=True)
    lbas = sorted(d.sectors)
    (directory / 'lbas.hex').write_text(''.join(f'{v:08x}\n' for v in lbas))
    (directory / 'disk.hex').write_text(''.join(f'{v:08x}\n' for lba in lbas for v in struct.unpack('<128I', d.sectors[lba])))
    commands, golden, names = [], [], []
    for fid, filename, raw in d.files:
        display = ''.join(c if 32 <= ord(c) <= 126 else '?' for c in filename[:32]).ljust(32)
        names.append(display)
        for index, sector in enumerate([0, 1, (len(raw) - 1) // 512, 0, len(raw) // 512 + 1]):
            fail = sector * 512 >= len(raw) or (corrupt == 'filechain' and fid == 0 and sector >= (1 << shift))
            commands.extend([fid, sector, len(raw), 0, int(fail), index % 4, len(names) - 1])
            golden.extend(struct.unpack('<128I', raw[sector * 512:sector * 512 + 512].ljust(512, b'\0')))
    commands.extend([510, 0, 0, 0, 1, 0, len(names)])
    names.append(' ' * 32)
    golden.extend([0] * 128)
    for filename, values in [('commands.hex', commands), ('golden.hex', golden)]:
        (directory / filename).write_text(''.join(f'{v:08x}\n' for v in values))
    (directory / 'names.hex').write_text(''.join(f'{ord(c):02x}\n' for line in names for c in line))
    expected_error = {'signature': 0x42, 'geometry': 0x43, 'checksum': 0x45}.get(corrupt, 0)
    return directory, len(lbas), len(commands) // 7, expected_error


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    iv = ROOT / 'tools/_iverilog/bin/iverilog.exe'
    vv = iv.with_name('vvp.exe')
    compiled = OUT / 'fs.vvp'
    command = [str(iv), '-g2005', '-s', 'tb_file_system', '-o', str(compiled),
               str(ROOT / 'rtl/eg_memory.v'), str(ROOT / 'rtl/sd_file_system.v'),
               str(ROOT / 'tests/tb_file_system.v')]
    subprocess.run(command, check=True)
    results = []
    cases = [('fat32_short_lfn_fragment', False, 2048, 0, ''),
             ('fat32_superfloppy_large_cluster', False, 0, 3, ''),
             ('exfat_partition_fragment', True, 4096, 0, ''),
             ('exfat_superfloppy_contiguous', True, 0, 2, ''),
             ('bad_signature', False, 0, 0, 'signature'),
             ('bad_geometry', True, 0, 0, 'geometry'),
             ('bad_exfat_checksum', True, 0, 0, 'checksum'),
             ('bad_file_chain', False, 2048, 0, 'filechain')]
    for name, exfat, partition, shift, corrupt in cases:
        path, sectors, commands, error = make_case(name, exfat, partition, shift, corrupt)
        result = subprocess.run([str(vv), str(compiled), f'+sectors={sectors}',
                                 f'+commands={commands}', f'+error={error}'], cwd=path,
                                capture_output=True, text=True, timeout=60)
        passed = result.returncode == 0 and 'PASS file system' in result.stdout and 'FAIL' not in result.stdout
        record = {'case': name, 'passed': passed, 'stdout': result.stdout, 'stderr': result.stderr}
        results.append(record)
        print(name, 'PASS' if passed else 'FAIL', result.stdout.strip(), flush=True)
        (path / 'run.log').write_text(result.stdout + result.stderr)
    (OUT / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())


from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from cli_zh import EnglishArgumentParser, run
from export_map import ReadOnlySectors, export
from tfm_format import verify_package


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for piece in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(piece)
    return result.hexdigest()


def removable_exfat(drive):
    if os.name != 'nt' or not re.fullmatch('[D-Zd-z]:?', drive):
        raise ValueError('Specify a removable Windows drive letter D-Z, for example E:')
    letter = drive[0].upper()
                                                                              
    command = (
        f"$v=Get-Volume -DriveLetter {letter} -ErrorAction Stop; "
        f"$p=Get-Partition -DriveLetter {letter} -ErrorAction Stop; "
        "$d=$p | Get-Disk -ErrorAction Stop; "
        "[pscustomobject]@{Drive=$v.DriveLetter;FileSystem=$v.FileSystem;"
        "DriveType=[string]$v.DriveType;Size=$v.Size;Free=$v.SizeRemaining;"
        "DiskNumber=$d.Number;BusType=[string]$d.BusType;IsBoot=$d.IsBoot;"
        "IsSystem=$d.IsSystem;IsReadOnly=$d.IsReadOnly;PartitionOffset=$p.Offset}"
        " | ConvertTo-Json -Compress"
    )
    reply = subprocess.run(['powershell.exe', '-NoProfile', '-Command', command],
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
    if reply.returncode:
        raise ValueError('Cannot verify drive information; check the card reader and drive letter')
    info = json.loads(reply.stdout)
    if (info.get('FileSystem') != 'exFAT' or info.get('DriveType') != 'Removable'
            or info.get('BusType') != 'USB' or info.get('IsBoot') is not False
            or info.get('IsSystem') is not False or info.get('IsReadOnly') is not False
            or not isinstance(info.get('DiskNumber'), int)):
        raise ValueError('Target must be a writable removable USB exFAT card, not a boot or system disk')
    return letter, info


def verify_physical_file(stream, source, extents, volume_offset_sectors=0):
    
    actual = hashlib.sha256()
    with source.open('rb') as expected:
        for logical, physical, sectors in extents:
            if expected.tell() != logical * 512:
                raise ValueError('Logical map addresses are not contiguous')
            if physical < volume_offset_sectors:
                raise ValueError('Physical map begins before the partition')
            stream.seek((physical - volume_offset_sectors) * 512)
            remaining = sectors * 512
            while remaining:
                size = min(remaining, 65536)
                data = stream.read(size)
                if len(data) != size or data != expected.read(size):
                    raise ValueError(f'Physical map readback differs from source at logical byte {expected.tell()-size}')
                actual.update(data)
                remaining -= size
        if expected.read(1):
            raise ValueError('Physical map does not cover the complete media file')
    return actual.hexdigest()


def main():
    parser = EnglishArgumentParser(description='Add a media file to a specified removable USB exFAT card and export its map; refuses to overwrite.')
    parser.add_argument('--drive', required=True, help='User-confirmed USB card reader drive letter, for example E:')
    parser.add_argument('--source', type=Path, required=True, help='Existing TFM1/TFM2/TFM3 media container')
    parser.add_argument('--name', default='TF2026_V2.PAK', help='New filename in the card root; refuses to overwrite')
    parser.add_argument('--out', type=Path, required=True, help='Local map .v output; also generates .json and .card.json')
    args = parser.parse_args()
    if (Path(args.name).name != args.name or not args.name or args.name in ('.', '..')
            or any(ch in args.name for ch in '\\/:*?"<>|') or args.name.endswith((' ', '.'))):
        parser.error('Card filename must be a single valid filename')
    if args.out.suffix.lower() != '.v':
        parser.error('Map output must end in .v')
    for path in (args.out, args.out.with_suffix('.json'), args.out.with_suffix('.card.json')):
        if path.exists():
            raise FileExistsError(f'Local output exists; choose a new name: {path}')
    header = verify_package(args.source)
    source_hash = digest(args.source)
    letter, info = removable_exfat(args.drive)
    if info['Free'] < args.source.stat().st_size:
        raise ValueError('Insufficient free space on card')
    target = Path(f'{letter}:/') / args.name
                                                                             
                                                                                
    copied = not target.exists()
    if copied:
        with args.source.open('rb') as source, target.open('xb') as destination:
            shutil.copyfileobj(source, destination, 1024 * 1024)
            destination.flush()
            os.fsync(destination.fileno())
    elif digest(target) != source_hash:
        raise FileExistsError(f'Card file exists with different contents; refusing to overwrite: {target}')
    mounted_hash = digest(target)
    if mounted_hash != source_hash or digest(args.source) != source_hash:
        raise ValueError('Copy verification failed or source changed; no valid map was generated')
    print('New file copy verified. Reading back all mapped physical sectors...', flush=True)
                                                                              
                                                                                
                                                                               
    offset_bytes = info.get('PartitionOffset')
    if not isinstance(offset_bytes, int) or offset_bytes < 0 or offset_bytes % 512:
        raise ValueError('Windows partition offset is not aligned to 512 bytes')
    volume_offset = offset_bytes // 512
    device = chr(92) * 2 + '.' + chr(92) + letter + ':'
    with open(device, 'rb', buffering=0) as stream:
        mapping = export(ReadOnlySectors(stream), args.name, args.out, volume_offset)
        raw_hash = verify_physical_file(stream, args.source, mapping['extents'], volume_offset)
    if raw_hash != source_hash:
        raise ValueError('Full physical map readback SHA256 mismatch')
    record = dict(created=datetime.now().astimezone().isoformat(), drive=info,
                  source=str(args.source.resolve()), target=str(target),
                  bytes=args.source.stat().st_size, source_sha256=source_hash,
                  mounted_sha256=mounted_hash, mapped_physical_sha256=raw_hash,
                  header=header, mapping_sha256=digest(args.out),
                  mapping_json_sha256=digest(args.out.with_suffix('.json')),
                  all_mapped_bytes_compared=True, new_file_only=True, copied_this_run=copied,
                  raw_device_open_mode='rb', raw_device_scope='partition_volume',
                  fpga_downloaded=False,
                  note='Re-export the map and rebuild if file allocation changes. This is not FPGA hardware acceptance.')
    args.out.with_suffix('.card.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Media and all mapped sectors verified: {target}')
    print(f'Local map: {args.out.resolve()}')
    print(f'SHA256: {source_hash}')


if __name__ == '__main__':
    run(main)

import argparse
import hashlib
from pathlib import Path
import struct
import zlib


def sector(words):
    raw = bytearray(512)
    for index, value in enumerate(words):
        struct.pack_into('<I', raw, index * 4, value)
    struct.pack_into('<I', raw, 508, zlib.crc32(raw[:508]))
    return bytes(raw)


def main():
    parser = argparse.ArgumentParser(description='Create the deterministic 17,920-byte TFM3 single-video conformance example.')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    pixels = bytes.fromhex('0000ff00 ff000000') + bytes(504)
    header = sector([0x314d4654, 3, 1280, 800, 1, 1024000, 1, 80, 1, 1,
                     2, 4, 3840, 48000, 16, 2, 5000, 35, 0, 1, 0, 2, 1, 3])
    image = sector([0x32474d49, 0, 2, 1, 3, 1, 1, zlib.crc32(pixels)])
    audio = sector([0x33445541, 0, 4, 3840, 31, 0, 0, 0])
    result = header + image + audio + pixels + sector([]) * 31
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('xb') as target:
        target.write(result)
    print('bytes=' + str(len(result)))
    print('sha256=' + hashlib.sha256(result).hexdigest())
    print('header_crc32=' + hex(struct.unpack_from('<I', header, 508)[0]))
    print('pixel_crc32=' + hex(zlib.crc32(pixels)))


if __name__ == '__main__':
    main()

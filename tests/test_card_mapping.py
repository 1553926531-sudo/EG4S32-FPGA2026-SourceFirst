
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from export_map import ReadOnlySectors, export
from media_pack import pack_v2
from prepare_card import verify_physical_file
from reference_exfat import checksum32, entry_checksum, rotate_add


def exfat_fixture(payload, fragmented):
    
    count = len(payload) // 512
    clusters = [5 + (i // 2) * 7 + i % 2 for i in range(count)] if fragmented else list(range(5, 5 + count))
    volume = bytearray(160 * 512)
    boot = bytearray(512)
    boot[3:11] = b'EXFAT   '
    struct.pack_into('<QIIIII', boot, 72, 160, 24, 2, 32, 128, 2)
    boot[108:111] = bytes((9, 0, 1))
    boot[510:512] = b'\x55\xaa'
    region = bytearray(12 * 512)
    region[:512] = boot
    value = 0
    for offset, byte in enumerate(region[:11 * 512]):
        if offset not in (106, 107, 112):
            value = rotate_add(value, byte, 32)
    region[11 * 512:] = struct.pack('<128I', *([value] * 128))
    volume[:12 * 512] = region
    volume[12 * 512:24 * 512] = region
    for cluster in (2, 3, 4):
        struct.pack_into('<I', volume, 24 * 512 + cluster * 4, 0xffffffff)
    for index, cluster in enumerate(clusters):
        following = clusters[index + 1] if index + 1 < count else 0xffffffff
        struct.pack_into('<I', volume, 24 * 512 + cluster * 4, following)
        start = (32 + cluster - 2) * 512
        volume[start:start + 512] = payload[index * 512:(index + 1) * 512]
    for cluster in (2, 3, 4, *clusters):
        at, bit = divmod(cluster - 2, 8)
        volume[33 * 512 + at] |= 1 << bit
                                                                    
    upcase = struct.pack('<HHH', 0xffff, 0xffff, 0xffff)
    volume[34 * 512:34 * 512 + len(upcase)] = upcase
    root = bytearray(512)
    root[0] = 0x81
    struct.pack_into('<IQ', root, 20, 3, 16)
    root[32] = 0x82
    struct.pack_into('<I', root, 36, checksum32(upcase))
    struct.pack_into('<IQ', root, 52, 4, len(upcase))
    name = 'TF2026_V2.PAK'
    entry = bytearray(96)
    entry[:2] = bytes((0x85, 2))
    entry[32:36] = bytes((0xc0, 1 if fragmented else 3, 0, len(name)))
    name_hash = 0
    for byte in name.encode('utf-16le'):
        name_hash = rotate_add(name_hash, byte, 16)
    struct.pack_into('<H', entry, 36, name_hash)
    struct.pack_into('<Q', entry, 40, len(payload))
    struct.pack_into('<IQ', entry, 52, clusters[0], len(payload))
    entry[64] = 0xc1
    entry[66:66 + len(name) * 2] = name.encode('utf-16le')
    struct.pack_into('<H', entry, 2, entry_checksum(entry))
    root[64:160] = entry
    volume[32 * 512:33 * 512] = root
    return bytes(volume), [32 + cluster - 2 for cluster in clusters]


class CardMappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='card_map_')
        cls.d = Path(cls.temp.name)
        image = cls.d / 'one.bmp'
        image.write_bytes(b'BM' + struct.pack('<IHHI', 58, 0, 0, 54)
                          + struct.pack('<IiiHHIIiiII', 40, 1, 1, 1, 24, 0, 4, 0, 0, 0, 0)
                          + b'\x12\x34\x56\0')
        wav = cls.d / 'one.wav'
        with wave.open(str(wav), 'wb') as stream:
            stream.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
            stream.writeframes(struct.pack('<hh', -123, 456))
        cls.source = cls.d / 'source.pak'
        pack_v2([image], [image], wav, cls.source)
        cls.payload = cls.source.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_whole_disk_and_partition_volume_give_same_absolute_extents(self):
        for fragmented in (False, True):
            with self.subTest(fragmented=fragmented):
                volume, lbas = exfat_fixture(self.payload, fragmented)
                prefix = bytearray(2048 * 512)
                prefix[450] = 7
                struct.pack_into('<I', prefix, 454, 2048)
                prefix[510:512] = b'\x55\xaa'
                disk = bytes(prefix) + volume
                volume_io, disk_io = io.BytesIO(volume), io.BytesIO(disk)
                a = export(ReadOnlySectors(volume_io), 'TF2026_V2.PAK', self.d / 'volume.v', 2048)
                b = export(ReadOnlySectors(disk_io), 'TF2026_V2.PAK', self.d / 'disk.v')
                self.assertEqual(a['extents'], b['extents'])
                self.assertEqual((self.d / 'volume.v').read_bytes(), (self.d / 'disk.v').read_bytes())
                translated = [physical + n for _, physical, count in a['extents'] for n in range(count)]
                self.assertEqual(translated, [lba + 2048 for lba in lbas])
                first = verify_physical_file(volume_io, self.source, a['extents'], 2048)
                self.assertEqual(first, verify_physical_file(disk_io, self.source, b['extents']))
                self.assertEqual(volume_io.getvalue(), volume)
                self.assertEqual(disk_io.getvalue(), disk)

    def test_bad_offsets_and_out_of_range_lba_are_rejected_before_output(self):
        volume, _ = exfat_fixture(self.payload, True)
        for index, offset in enumerate((-1, 0.5, 2**32)):
            target = self.d / f'invalid{index}.v'
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                export(ReadOnlySectors(io.BytesIO(volume)), 'TF2026_V2.PAK', target, offset)
            self.assertFalse(target.exists())

    def test_full_mapped_readback_rejects_wrong_offset_or_late_corruption(self):
        volume, lbas = exfat_fixture(self.payload, True)
        result = export(ReadOnlySectors(io.BytesIO(volume)), 'TF2026_V2.PAK', self.d / 'good.v', 2048)
        wrong = bytearray(volume)
        wrong[lbas[-1] * 512 + 499] ^= 1
        with self.assertRaises(ValueError):
            verify_physical_file(io.BytesIO(wrong), self.source, result['extents'], 2048)
        with self.assertRaises(ValueError):
            verify_physical_file(io.BytesIO(volume), self.source, result['extents'], 2047)


if __name__ == '__main__':
    unittest.main()

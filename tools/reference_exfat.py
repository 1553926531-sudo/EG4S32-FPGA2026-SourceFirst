






from __future__ import annotations

import hashlib
import json
import math
import struct
from datetime import datetime
from pathlib import Path


def rotate_add(value, byte, width):
    return (((value >> 1) | ((value & 1) << (width - 1))) + byte) & ((1 << width) - 1)


def checksum32(data):
    value = 0
    for byte in data:
        value = rotate_add(value, byte, 32)
    return value


def entry_checksum(data):
    value = 0
    for offset, byte in enumerate(data):
        if offset not in (2, 3):
            value = rotate_add(value, byte, 16)
    return value


class ExfatVolume:
    def __init__(self, link, journal_dir=None):
        self.link = link
        self.journal_dir = Path(journal_dir) if journal_dir else None
        if self.journal_dir:
            self.journal_dir.mkdir(parents=True, exist_ok=True)
        self.write_sequence = 0
        self.read_count = 0
        self.write_count = 0
        self.fat_cache = {}
        mbr = self.read(0)
        if mbr[3:11] == b"EXFAT   ":
            self.start = 0
        else:
            if mbr[510:512] != b"\x55\xaa":
                raise ValueError("MBR or exFAT signature not found")
            starts = [int.from_bytes(mbr[454 + i * 16:458 + i * 16], "little")
                      for i in range(4) if mbr[450 + i * 16] == 7]
            if len(starts) != 1:
                raise ValueError(f"Exactly one type-07 exFAT partition is required: {starts}")
            self.start = starts[0]
        boot = self.read(self.start)
        if boot[3:11] != b"EXFAT   " or boot[510:512] != b"\x55\xaa":
            raise ValueError("Invalid exFAT volume")
        self.volume_sectors = int.from_bytes(boot[72:80], "little")
        self.fat_offset, self.fat_length, self.heap_offset, self.cluster_count, self.root_cluster = (
            struct.unpack_from("<IIIII", boot, 80))
        if boot[108] != 9 or boot[109] > 8 or boot[110] != 1:
            raise ValueError("Only 512-byte sectors and single-FAT volumes are supported")
        if int.from_bytes(boot[106:108], "little") & 0x01:
            raise ValueError("Single-FAT volume ActiveFat must be zero")
        self.spc = 1 << boot[109]
        self.cluster_bytes = self.spc * 512
        self.boot_checksums = [self.validate_boot_region(self.start + offset)
                               for offset in (0, 12)]
        self.root_chain = self.chain(self.root_cluster)
        self.root_lbas = [self.cluster_lba(c) + s for c in self.root_chain
                          for s in range(self.spc)]
        self.refresh_directory()
        special = {entry[0]: entry for entry in self.entries_until_end()
                   if entry[0] in (0x81, 0x82)}
        if set(special) != {0x81, 0x82}:
            raise ValueError("Missing allocation bitmap or upcase table entry")
        bitmap_entry = special[0x81]
        if bitmap_entry[1] & 1:
            raise ValueError("Allocation bitmap does not belong to FAT 0")
        self.bitmap_first = int.from_bytes(bitmap_entry[20:24], "little")
        self.bitmap_length = int.from_bytes(bitmap_entry[24:32], "little")
        self.bitmap_chain = self.chain(self.bitmap_first)
        self.bitmap_lbas = [self.cluster_lba(c) + s for c in self.bitmap_chain
                            for s in range(self.spc)]
        if len(self.bitmap_lbas) * 512 < self.bitmap_length:
            raise ValueError("Allocation bitmap cluster chain is too short")
        self.bitmap = bytearray(b"".join(self.read(lba) for lba in self.bitmap_lbas)
                                [:self.bitmap_length])
        if self.bitmap_length < (self.cluster_count + 7) // 8:
            raise ValueError("Allocation bitmap is too short")
        upcase_entry = special[0x82]
        upcase_first = int.from_bytes(upcase_entry[20:24], "little")
        upcase_length = int.from_bytes(upcase_entry[24:32], "little")
        raw_upcase = self.read_chain(self.chain(upcase_first), upcase_length)
        if checksum32(raw_upcase) != int.from_bytes(upcase_entry[4:8], "little"):
            raise ValueError("Upcase table checksum failed")
        self.upcase = self.expand_upcase(raw_upcase)

    def read(self, lba):
        data = self.link.read_sector(lba)
        self.read_count += 1
        return data

    def write(self, lba, data, kind="data"):
        if len(data) != 512:
            raise ValueError("Exactly one sector of data is required")
        if not self.start <= lba < self.start + self.volume_sectors:
            raise ValueError(f"Write exceeds exFAT partition: {lba}")
        before = self.read(lba)
        if before == data:
            return
        self.write_sequence += 1
        if self.journal_dir:
            prefix = f"{self.write_sequence:06d}_lba{lba}_{kind}"
            (self.journal_dir / f"{prefix}_before.bin").write_bytes(before)
            (self.journal_dir / f"{prefix}_after.bin").write_bytes(data)
            with (self.journal_dir / "writes.jsonl").open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"sequence": self.write_sequence, "lba": lba,
                                         "kind": kind,
                                         "before_sha256": hashlib.sha256(before).hexdigest(),
                                         "after_sha256": hashlib.sha256(data).hexdigest()}) + "\n")
        self.link.write_sector(lba, data)
        self.write_count += 1
        if self.read(lba) != data:
            raise IOError(f"Write readback mismatch, LBA {lba}")

    def validate_boot_region(self, lba):
        region = b"".join(self.read(lba + i) for i in range(12))
        checksum = 0
        for offset, byte in enumerate(region[:11 * 512]):
            if offset not in (106, 107, 112):
                checksum = rotate_add(checksum, byte, 32)
        if any(value != checksum for value in struct.unpack("<128I", region[11 * 512:])):
            raise ValueError(f"exFAT boot region checksum failed, LBA {lba}")
        return checksum

    def cluster_lba(self, cluster):
        if not 2 <= cluster < self.cluster_count + 2:
            raise ValueError(f"Cluster number out of range: {cluster}")
        return self.start + self.heap_offset + (cluster - 2) * self.spc

    def fat(self, cluster):
        sector, offset = divmod(cluster * 4, 512)
        if sector not in self.fat_cache:
            self.fat_cache[sector] = self.read(self.start + self.fat_offset + sector)
        return int.from_bytes(self.fat_cache[sector][offset:offset + 4], "little")

    def chain(self, first):
        result = []
        seen = set()
        cluster = first
        while 2 <= cluster < self.cluster_count + 2:
            if cluster in seen:
                raise ValueError("FAT cluster chain contains a loop")
            seen.add(cluster)
            result.append(cluster)
            cluster = self.fat(cluster)
            if cluster >= 0xFFFFFFF8:
                return result
        raise ValueError(f"Invalid FAT end-of-chain marker: {cluster:08x}")

    def read_chain(self, clusters, length):
        data = bytearray()
        for cluster in clusters:
            for sector in range(self.spc):
                if len(data) >= length:
                    return bytes(data[:length])
                data.extend(self.read(self.cluster_lba(cluster) + sector))
        if len(data) < length:
            raise ValueError("Cluster chain is shorter than file length")
        return bytes(data[:length])

    def refresh_directory(self):
        self.root = bytearray(b"".join(self.read(lba) for lba in self.root_lbas))

    def entries_until_end(self):
        for offset in range(0, len(self.root), 32):
            entry = self.root[offset:offset + 32]
            if not entry[0]:
                return
            yield entry

    @staticmethod
    def expand_upcase(raw):
        words = list(struct.unpack(f"<{len(raw) // 2}H", raw))
        result = list(range(65536))
        char = 0
        i = 0
        while i < len(words) and char < 65536:
            if words[i] == 0xFFFF and char != 0xFFFF:
                i += 1
                if i >= len(words):
                    raise ValueError("Incomplete upcase table skip entry")
                char += words[i]
            else:
                result[char] = words[i]
                char += 1
            i += 1
        if char != 65536 or i != len(words):
            raise ValueError(f"Invalid upcase table coverage: {char} characters")
        return result

    def name_hash(self, name):
        words = struct.unpack(f"<{len(name.encode('utf-16le')) // 2}H", name.encode("utf-16le"))
        value = 0
        for word in words:
            upper = self.upcase[word]
            value = rotate_add(value, upper & 255, 16)
            value = rotate_add(value, upper >> 8, 16)
        return value

    def files(self):
        result = []
        offset = 0
        while offset < len(self.root):
            primary = self.root[offset:offset + 32]
            if primary[0] == 0:
                break
            if primary[0] != 0x85:
                offset += 32
                continue
            secondary_count = primary[1]
            entry_set = self.root[offset:offset + (secondary_count + 1) * 32]
            if len(entry_set) != (secondary_count + 1) * 32:
                raise ValueError("Incomplete file directory entry set")
            if entry_checksum(entry_set) != int.from_bytes(primary[2:4], "little"):
                raise ValueError(f"File directory entry checksum failed at root offset {offset}")
            stream = entry_set[32:64]
            if stream[0] != 0xC0:
                raise ValueError("Missing stream extension entry")
            names = b"".join(entry_set[i + 2:i + 32]
                             for i in range(64, len(entry_set), 32) if entry_set[i] == 0xC1)
            name = names[:stream[3] * 2].decode("utf-16le")
            if self.name_hash(name) != int.from_bytes(stream[4:6], "little"):
                raise ValueError(f"Filename hash mismatch: {name!r}")
            result.append({"name": name, "offset": offset, "entries": secondary_count + 1,
                           "attributes": int.from_bytes(primary[4:6], "little"),
                           "flags": stream[1],
                           "first_cluster": int.from_bytes(stream[20:24], "little"),
                           "valid_length": int.from_bytes(stream[8:16], "little"),
                           "length": int.from_bytes(stream[24:32], "little")})
            offset += len(entry_set)
        return result

    def find(self, name):
        return next((file for file in self.files() if file["name"] == name), None)

    def file_clusters(self, file):
        needed = math.ceil(file["length"] / self.cluster_bytes)
        if not needed:
            return []
        first = file["first_cluster"]
        clusters = list(range(first, first + needed)) if file["flags"] & 2 else self.chain(first)
        if len(clusters) < needed:
            raise ValueError("File cluster chain is shorter than DataLength")
        for cluster in clusters:
            if not self.is_allocated(cluster):
                raise ValueError(f"File cluster {cluster} is not allocated in the bitmap")
        return clusters[:needed]

    def read_file(self, name):
        file = self.find(name)
        if file is None:
            raise FileNotFoundError(f"File not found: {name}")
        if file["attributes"] & 0x10:
            raise IsADirectoryError(f"Target is a directory: {name}")
        if file["valid_length"] != file["length"]:
            raise ValueError("ValidDataLength must equal DataLength")
        return self.read_chain(self.file_clusters(file), file["length"])

    def is_allocated(self, cluster):
        bit = cluster - 2
        return bool(self.bitmap[bit // 8] & (1 << (bit % 8)))

    def allocate(self, count, fragmented=False):
        if count == 0:
            return []
        result = []
        previous = None
        for cluster in range(2, self.cluster_count + 2):
            if self.is_allocated(cluster):
                if not fragmented:
                    result = []
                continue
            if fragmented and previous is not None and cluster == previous + 1:
                continue
            result.append(cluster)
            previous = cluster
            if len(result) == count:
                return result
        raise IOError("Insufficient allocatable space")

    def directory_slot(self, entries):
        run_start = 0
        run_length = 0
        for offset in range(0, len(self.root), 32):
            if not self.root[offset] & 0x80:
                if not run_length:
                    run_start = offset
                run_length += 1
                if run_length == entries:
                    return run_start
            else:
                run_length = 0
        raise IOError("Root directory lacks sufficient contiguous free entries")

    def set_dirty(self, dirty):
        for offset in (0, 12):
            lba = self.start + offset
            boot = bytearray(self.read(lba))
            flags = int.from_bytes(boot[106:108], "little")
            flags = (flags | 2) if dirty else (flags & ~2)
            struct.pack_into("<H", boot, 106, flags)
            if not dirty:
                used = sum(self.is_allocated(c) for c in range(2, self.cluster_count + 2))
                boot[112] = min(100, used * 100 // self.cluster_count)
            self.write(lba, bytes(boot), "boot_flags")

    @staticmethod
    def timestamp():
        now = datetime.now().astimezone()
        stamp = (((now.year - 1980) << 25) | (now.month << 21) | (now.day << 16)
                 | (now.hour << 11) | (now.minute << 5) | (now.second // 2))
        quarters = int(now.utcoffset().total_seconds() // 900)
        timezone = 0x80 | (quarters & 0x7F)
        return stamp, (now.second % 2) * 100 + now.microsecond // 10000, timezone

    def make_entries(self, name, clusters, length, fragmented):
        encoded = name.encode("utf-16le")
        char_count = len(encoded) // 2
        if not 1 <= char_count <= 255 or any(c in name for c in '\\/:*?"<>|'):
            raise ValueError("Invalid filename")
        names = math.ceil(char_count / 15)
        entries = bytearray((2 + names) * 32)
        entries[0] = 0x85
        entries[1] = 1 + names
        struct.pack_into("<H", entries, 4, 0x20)
        stamp, increment, timezone = self.timestamp()
        struct.pack_into("<III", entries, 8, stamp, stamp, stamp)
        entries[20] = increment
        entries[21] = increment
        entries[22:25] = bytes((timezone, timezone, timezone))
        entries[32] = 0xC0
                                                              
        entries[33] = 1 if fragmented or not length else 3
        entries[35] = char_count
        struct.pack_into("<H", entries, 36, self.name_hash(name))
        struct.pack_into("<Q", entries, 40, length)
        struct.pack_into("<I", entries, 52, clusters[0] if clusters else 0)
        struct.pack_into("<Q", entries, 56, length)
        for index in range(names):
            offset = 64 + index * 32
            entries[offset] = 0xC1
            piece = encoded[index * 30:(index + 1) * 30]
            entries[offset + 2:offset + 2 + len(piece)] = piece
        struct.pack_into("<H", entries, 2, entry_checksum(entries))
        return entries

    def create_file(self, name, data, fragmented=False, progress=None):
        if self.find(name) is not None:
            raise FileExistsError(f"File exists; refusing to overwrite: {name}")
        clusters = self.allocate(math.ceil(len(data) / self.cluster_bytes), fragmented)
        entries = self.make_entries(name, clusters, len(data), fragmented)
        slot = self.directory_slot(len(entries) // 32)
        sectors = math.ceil(len(data) / 512)
        self.set_dirty(True)
        for index in range(sectors):
            cluster_index, sector = divmod(index, self.spc)
            lba = self.cluster_lba(clusters[cluster_index]) + sector
            piece = data[index * 512:(index + 1) * 512].ljust(512, b"\x00")
            self.write(lba, piece, "file_data")
            if progress and ((index + 1) % 128 == 0 or index + 1 == sectors):
                progress(index + 1, sectors)
        changed_bitmap_sectors = set()
        changed_fat_sectors = {}
        for index, cluster in enumerate(clusters):
            bit = cluster - 2
            self.bitmap[bit // 8] |= 1 << (bit % 8)
            changed_bitmap_sectors.add(bit // (512 * 8))
            if fragmented:
                sector, offset = divmod(cluster * 4, 512)
                if sector not in changed_fat_sectors:
                    changed_fat_sectors[sector] = bytearray(
                        self.read(self.start + self.fat_offset + sector))
                next_cluster = clusters[index + 1] if index + 1 < len(clusters) else 0xFFFFFFFF
                struct.pack_into("<I", changed_fat_sectors[sector], offset, next_cluster)
        for sector, contents in sorted(changed_fat_sectors.items()):
            self.write(self.start + self.fat_offset + sector, bytes(contents), "fat")
            self.fat_cache[sector] = bytes(contents)
        for sector in sorted(changed_bitmap_sectors):
            lba = self.bitmap_lbas[sector]
            before = bytearray(self.read(lba))
            piece = self.bitmap[sector * 512:(sector + 1) * 512]
            before[:len(piece)] = piece
            self.write(lba, bytes(before), "bitmap")
                                                                           
                                                                               
        inactive = bytearray(entries)
        inactive[0] &= 0x7F
        pending = bytearray(self.root)
        pending[slot:slot + len(inactive)] = inactive
        first_sector = slot // 512
        last_sector = (slot + len(entries) - 1) // 512
        for sector in range(first_sector, last_sector + 1):
            self.write(self.root_lbas[sector], bytes(pending[sector * 512:(sector + 1) * 512]),
                       "directory_prepare")
        pending[slot] = 0x85
        self.write(self.root_lbas[first_sector],
                   bytes(pending[first_sector * 512:(first_sector + 1) * 512]),
                   "directory_commit")
        self.root = pending
        self.set_dirty(False)
        return {"name": name, "length": len(data), "clusters": clusters,
                "fragmented": fragmented, "directory_offset": slot,
                "sha256": hashlib.sha256(data).hexdigest()}

    def overwrite_file(self, name, data, progress=None):
        file = self.find(name)
        if file is None or len(data) != file["length"]:
            raise ValueError("Overwrite requires an existing target of equal length")
        clusters = self.file_clusters(file)
        sectors = math.ceil(len(data) / 512)
        self.set_dirty(True)
        for index in range(sectors):
            cluster_index, sector = divmod(index, self.spc)
            lba = self.cluster_lba(clusters[cluster_index]) + sector
            self.write(lba, data[index * 512:(index + 1) * 512].ljust(512, b"\x00"), "overwrite")
            if progress and ((index + 1) % 128 == 0 or index + 1 == sectors):
                progress(index + 1, sectors)
        self.set_dirty(False)

    def geometry(self):
        return {"partition_lba": self.start, "volume_sectors": self.volume_sectors,
                "fat_offset": self.fat_offset, "fat_length": self.fat_length,
                "heap_offset": self.heap_offset, "cluster_count": self.cluster_count,
                "sectors_per_cluster": self.spc, "root_clusters": self.root_chain,
                "bitmap_clusters": self.bitmap_chain, "bitmap_length": self.bitmap_length,
                "boot_checksums": [f"{c:08x}" for c in self.boot_checksums]}

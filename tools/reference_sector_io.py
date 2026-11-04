





from __future__ import annotations

import struct
import time
import warnings
import zlib


SYNC_REQUEST = 0xA5
SYNC_RESPONSE = 0x5A
OP_READ = 0x01
OP_WRITE = 0x02
SECTOR_SIZE = 512


class SectorLinkError(RuntimeError):
    pass


class SectorLink:
    def __init__(self, serial_port):
        self.serial = serial_port
        self.read_recoveries = []
        self.high_speed_switches = []
        self.transport_failures = []
        self.receive_buffer_bytes = None
        if hasattr(serial_port, "set_buffer_size"):
            serial_port.set_buffer_size(rx_size=65536, tx_size=65536)
            self.receive_buffer_bytes = 65536

    def wait_ready(self, timeout=120):
        deadline = time.monotonic() + timeout
        tail = bytearray()
        marker = b"TF EXFAT IO READY"
        while time.monotonic() < deadline:
            part = self.serial.read(256)
            if part:
                tail.extend(part)
                if marker in tail:
                    return bytes(tail)
                if len(tail) > 8192:
                    del tail[:-len(marker)]
        raise SectorLinkError(
            f"FPGA did not report exFAT ready within {timeout} seconds; "
            f"Serial tail data={bytes(tail[-512:])!r}"
        )

    def _read_exact(self, size, timeout=15):
        deadline = time.monotonic() + timeout
        result = bytearray()
        while len(result) < size and time.monotonic() < deadline:
            part = self.serial.read(size - len(result))
            if part:
                result.extend(part)
        if len(result) != size:
            raise SectorLinkError(
                f"Incomplete serial response: expected {size} bytes, received {len(result)} bytes"
            )
        return bytes(result)

    def _request_header(self, op, lba):
        if not 0 <= lba <= 0xFFFFFFFF:
            raise ValueError("LBA must be an unsigned 32-bit integer")
        return bytes((SYNC_REQUEST, op)) + struct.pack(">I", lba)

    def _read_ack(self, lba, timeout=15):
        response = self._read_exact(6, timeout)
        if response[0] != SYNC_RESPONSE:
            raise SectorLinkError(f"Invalid response marker: {response[:8].hex()}")
        echoed_lba = struct.unpack(">I", response[2:6])[0]
        if echoed_lba != lba:
            raise SectorLinkError(f"Response LBA mismatch: requested {lba}, received {echoed_lba}")
        return response[1]

    def read_sector(self, lba, timeout=15):
                                                                               
                                                                             
                                                                             
        for attempt in range(3):
            try:
                return self._read_sector_once(lba, timeout)
            except SectorLinkError as exc:
                error = str(exc)
                transport_failure = error.startswith(("Incomplete serial response:",
                    "Invalid response marker:", "Response LBA mismatch:", "Serial data CRC32 mismatch"))
                if not transport_failure or attempt == 2:
                    raise
                time.sleep(.05)
                discarded = self.serial.read(self.serial.in_waiting)
                self.serial.reset_input_buffer()
                record = {"lba": lba, "attempt": attempt + 1, "error": error,
                          "discarded_bytes": len(discarded)}
                self.read_recoveries.append(record)
                warnings.warn(f"Serial read recovered after retry: {record}", RuntimeWarning)

    def _read_sector_once(self, lba, timeout=15):
        self.serial.write(self._request_header(OP_READ, lba))
        status = self._read_ack(lba, timeout)
        if status != 0:
            raise SectorLinkError(f"FPGA read failed, status 0x{status:02x}, LBA {lba}")
        response = self._read_exact(SECTOR_SIZE + 4, timeout)
        data = response[:SECTOR_SIZE]
        expected_crc = struct.unpack(">I", response[-4:])[0]
        actual_crc = zlib.crc32(data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise SectorLinkError(
                f"Serial data CRC32 mismatch, LBA {lba}: "
                f"FPGA={expected_crc:08x}, host={actual_crc:08x}"
            )
        return data

    def write_sector(self, lba, data, timeout=15):
        if len(data) != SECTOR_SIZE:
            raise ValueError(f"A sector must contain exactly {SECTOR_SIZE} bytes")
        crc = zlib.crc32(data) & 0xFFFFFFFF
        frame = self._request_header(OP_WRITE, lba) + data + struct.pack(">I", crc)
        self.serial.write(frame)
        status = self._read_ack(lba, timeout)
        if status != 0:
            raise SectorLinkError(f"FPGA write failed, status 0x{status:02x}, LBA {lba}")

    def debug_word(self, index):
        
        self.serial.write(self._request_header(3, index))
        reply = self._read_exact(6)
        if reply[:2] != b"\x5a\x00":
            raise SectorLinkError(f"Diagnostic register response failed: {reply.hex()}")
        return struct.unpack(">I", reply[2:])[0]

    def set_clock_divider(self, half_period):
        
        if not (0 <= half_period <= 249 or half_period == 255):
            raise ValueError("Half-period divider must be 0-249; firmware v29 or later uses 255 for 50 MHz")
        if half_period == 255:
            revision = self.debug_word(0)
            if revision < 29:
                raise SectorLinkError("50 MHz mode requires firmware v29 or later")
                                                                            
                                                                             
            self.set_clock_divider(24)
            capability = self.switch_function(0x00FFFFF1)
            if not capability[13] & 2 or int.from_bytes(capability[28:30], "big") & 2:
                raise SectorLinkError("Card high-speed function unavailable or busy")
            selected = self.switch_function(0x80FFFFF1)
            record = {"revision": revision, "check_hex": capability.hex(),
                      "switch_hex": selected.hex(), "selected": selected[16] & 15}
            self.high_speed_switches.append(record)
            if record["selected"] != 1:
                raise SectorLinkError("Card rejected high-speed switch; 50 MHz was not enabled")
        self.serial.write(self._request_header(5, half_period))
        status = self._read_ack(half_period)
        if status:
            raise SectorLinkError(f"Clock configuration request rejected: 0x{status:02x}")
        if half_period == 255:
            if self.debug_word(18) != 255 or self.debug_word(38) != 1:
                raise SectorLinkError("FPGA has not enabled forwarded 50 MHz clock")
            return 50_000_000
        return 50_000_000 / (2 * (half_period + 1))

    def card_status(self):
        
        self.serial.write(self._request_header(6, 0))
        response = self._read_exact(6)
        if response[:2] != b"\x5a\x00":
            raise SectorLinkError(f"CMD13 response failed: {response.hex()}")
        return struct.unpack(">I", response[2:])[0]

    def reinitialize(self, timeout=120):
        
        self.serial.reset_input_buffer()
        self.serial.write(bytes((SYNC_REQUEST, 7)))
        return self.wait_ready(timeout)

    def card_registers(self):
        
        return {name: b"".join(struct.pack(">I", self.debug_word(i))
                              for i in range(first, first + 4))
                for name, first in (("cid", 26), ("csd", 30))}

    def busy_diagnostics(self):
        
        words = [self.debug_word(index) for index in range(34, 38)]
        return {"last_write_busy_sys_cycles": words[0],
                "max_write_busy_sys_cycles": words[1],
                "last_write_busy_ms": words[0] / 50_000,
                "max_write_busy_ms": words[1] / 50_000,
                "write_busy_timeouts": words[2],
                "card_wait_limit_ms": words[3] / 50_000}

    def switch_function(self, argument=0x00FFFFF1):
        
        self.serial.write(self._request_header(8, argument))
        status = self._read_ack(argument)
        if status:
            raise SectorLinkError(f"CMD6 failed: 0x{status:02x}")
        packet = self._read_exact(68)
        if zlib.crc32(packet[:64]) & 0xFFFFFFFF != struct.unpack(">I", packet[64:])[0]:
            raise SectorLinkError("CMD6 serial CRC32 mismatch")
        return packet[:64]

    def read_blocks(self, lba, count, timeout=15):
        
        if not 1 <= count <= 65535 or lba + count - 1 > 0xFFFFFFFF:
            raise ValueError("Invalid multi-block read range")
        self.serial.write(self._request_header(4, lba) + struct.pack(">H", count))
        output = bytearray()
        for current in range(lba, lba + count):
            status = self._read_ack(current, timeout)
            if status:
                                                                           
                raise SectorLinkError(f"CMD18 failed, status 0x{status:02x}, LBA {current}")
            packet = self._read_exact(SECTOR_SIZE + 4, timeout)
            crc = struct.unpack(">I", packet[-4:])[0]
            if zlib.crc32(packet[:SECTOR_SIZE]) & 0xFFFFFFFF != crc:
                actual_crc = zlib.crc32(packet[:SECTOR_SIZE]) & 0xFFFFFFFF
                self.transport_failures.append({"operation": "CMD18", "lba": current,
                    "start_lba": lba, "count": count, "fpga_crc32": f"{crc:08x}",
                    "host_crc32": f"{actual_crc:08x}", "packet_hex": packet.hex()})
                raise SectorLinkError(f"CMD18 serial CRC32 mismatch, LBA {current}: "
                                      f"FPGA={crc:08x}, host={actual_crc:08x}")
            output.extend(packet[:SECTOR_SIZE])
        status = self._read_ack(lba + count - 1, timeout)
        if status:
            raise SectorLinkError(f"CMD12 stop transmission failed: 0x{status:02x}")
        return bytes(output)


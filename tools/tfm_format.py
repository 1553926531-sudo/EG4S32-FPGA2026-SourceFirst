
import struct
import zlib

SECTOR = 512
WIDTH, HEIGHT = 1280, 800
PIXELS = WIDTH * HEIGHT
FRAME_BYTES = PIXELS * 4
FRAME_SECTORS = FRAME_BYTES // SECTOR
FRAME_STRIDE = FRAME_SECTORS + 1
MAGIC = int.from_bytes(b"TFM1", "little")
TRAILER_MAGIC = int.from_bytes(b"FCRC", "little")


def checked_sector(words):
    b = bytearray(SECTOR)
    for index, value in enumerate(words):
        struct.pack_into("<I", b, index * 4, value)
    struct.pack_into("<I", b, 508, zlib.crc32(b[:508]))
    return bytes(b)


def validate_sector(data):
    if len(data) != 512 or zlib.crc32(data[:508]) != struct.unpack_from("<I", data, 508)[0]:
        raise ValueError("Sector length or CRC32 mismatch")
    return struct.unpack("<128I", data)


def parse_header(data):
    w = validate_sector(data)
    if w[0] == MAGIC and w[1] == 3:
        from tfm3 import parse_header_v3
        return parse_header_v3(w)
    if w[0] == MAGIC and w[1] == 2:
        return parse_header_v2(w)
    if w[:6] != (MAGIC, 1, WIDTH, HEIGHT, 1, PIXELS):
        raise ValueError("Invalid TFM1 version 1, 1280x800 XRGB8888 media container")
    if not 1 <= w[6] <= 600 or not 1000 <= w[7] <= 60000:
        raise ValueError("Video requires 1-600 frames with at least 1000 ms dwell per frame")
    if w[8:10] != (1, FRAME_STRIDE) or w[10] != 1 + w[6] * FRAME_STRIDE:
        raise ValueError("Video and image storage layouts disagree")
    if w[11] != w[10] + FRAME_STRIDE or w[13:16] != (48000, 16, 2):
        raise ValueError("Invalid audio layout or format")
    if not 1 <= w[12] <= 48_000 * 3600 or not 1000 <= w[16] <= 60000:
        raise ValueError("Invalid audio length or image dwell time")
    if w[17] != w[11] + (w[12] + 126) // 127:
        raise ValueError("Invalid media container length")
    return dict(video_frames=w[6], frame_ms=w[7], video_lba=w[8], frame_stride=w[9],
                image_lba=w[10], audio_lba=w[11], audio_samples=w[12], image_ms=w[16],
                sectors=w[17], header_crc=w[127])


def read_bmp(path):
    raw = path.read_bytes()
    if len(raw) < 54 or raw[:2] != b"BM":
        raise ValueError(f"{path}: requires an uncompressed 24-bit BMP")
    offset = struct.unpack_from("<I", raw, 10)[0]
    dib, width, height, planes, bits, compression = struct.unpack_from("<IiiHHI", raw, 14)
    if dib < 40 or width != WIDTH or abs(height) != HEIGHT or planes != 1 or bits != 24 or compression:
        raise ValueError(f"{path}: TFM1 requires a 1280x800, 24-bit BI_RGB BMP; no automatic scaling or cropping")
    stride = (width * 3 + 3) & ~3
    if offset < 14 + dib or len(raw) < offset + stride * HEIGHT:
        raise ValueError(f"{path}: invalid or incomplete BMP header or pixels")
    out = bytearray(FRAME_BYTES)
    for y in range(HEIGHT):
        src_y = HEIGHT - 1 - y if height > 0 else y
        row = raw[offset + src_y * stride: offset + src_y * stride + WIDTH * 3]
        base = y * WIDTH * 4
        out[base:base + WIDTH * 4:4] = row[0::3]
        out[base + 1:base + WIDTH * 4:4] = row[1::3]
        out[base + 2:base + WIDTH * 4:4] = row[2::3]
    return bytes(out)


def verify_package(path):
    with path.open("rb") as f:
        h = parse_header(f.read(512))
        if h.get('version') == 3:
            from tfm3 import verify_package_v3
            return verify_package_v3(path, h)
        if h.get('version') == 2:
            return verify_package_v2(path, h)
        if path.stat().st_size != h["sectors"] * 512:
            raise ValueError("Media container length mismatch")
        for index in range(h["video_frames"] + 1):
            payload = f.read(FRAME_BYTES)
            trailer = validate_sector(f.read(512))
            expected_id = index if index < h["video_frames"] else 0xFFFFFFFF
            if trailer[:3] != (TRAILER_MAGIC, expected_id, zlib.crc32(payload)):
                raise ValueError(f"Frame {index} CRC or index mismatch")
            if any(payload[3::4]):
                raise ValueError("Pixel X bytes must be zero")
        remaining = h["audio_samples"]
        while remaining:
            chunk = f.read(512)
            validate_sector(chunk)
            used = min(127, remaining)
            if any(chunk[used * 4:508]):
                raise ValueError("Audio trailing padding must be zero")
            remaining -= used
    return h


def parse_header_v2(w):
    if w[:6] != (MAGIC, 2, WIDTH, HEIGHT, 1, PIXELS):
        raise ValueError('TFM2 output must be 1280x800 XRGB8888')
    if not 1 <= w[6] <= 600 or not 1 <= w[18] <= 600:
        raise ValueError('Video and image counts must be 1-600')
    if not 1000 <= w[7] <= 60000 or not 1000 <= w[16] <= 60000:
        raise ValueError('Image dwell time must be 1000-60000 ms')
    if w[8:11] != (1, 1, 1+w[6]) or w[19] != 1:
        raise ValueError('Invalid TFM2 descriptor layout or loop flags')
    if w[13:16] != (48000, 16, 2) or not 1 <= w[12] <= 172800000:
        raise ValueError('Audio must be 48 kHz, 16-bit stereo PCM, at most one hour')
    if not 1+w[6]+w[18] < w[11] < w[17] <= 40000000:
        raise ValueError('Invalid TFM2 audio location or total length')
    if w[17] != w[11] + (w[12]+126)//127:
        raise ValueError('Invalid TFM2 audio sector length')
    return dict(version=2, video_frames=w[6], frame_ms=w[7], video_lba=w[8],
                frame_stride=w[9], image_lba=w[10], image_count=w[18],
                audio_lba=w[11], audio_samples=w[12], image_ms=w[16],
                sectors=w[17], header_crc=w[127], continuous=True)


def read_bmp_source(path):
    
    raw = path.read_bytes()
    if len(raw)<54 or raw[:2]!=b'BM':
        raise ValueError(f'{path}: requires an uncompressed 24-bit BMP')
    offset=struct.unpack_from('<I',raw,10)[0]
    dib,width,height,planes,bits,compression=struct.unpack_from('<IiiHHI',raw,14)
    if dib<40 or not 1<=width<=2048 or not 1<=abs(height)<=2048 or planes!=1 or bits!=24 or compression:
        raise ValueError(f'{path}: requires a 24-bit BI_RGB BMP with width and height in 1-2048')
    height_abs=abs(height)
    bmp_stride=(width*3+3)&~3
    if offset<14+dib or len(raw)<offset+bmp_stride*height_abs:
        raise ValueError(f'{path}: incomplete BMP header or pixels')
    stride=((width+127)//128)*128
    out=bytearray(stride*height_abs*4)
    for y in range(height_abs):
        source_y=height_abs-1-y if height>0 else y
        row=raw[offset+source_y*bmp_stride:offset+source_y*bmp_stride+width*3]
        base=y*stride*4
        out[base:base+width*4:4]=row[0::3]
        out[base+1:base+width*4:4]=row[1::3]
        out[base+2:base+width*4:4]=row[2::3]
    return width,height_abs,bytes(out)


def verify_package_v2(path,h):
    total=h['video_frames']+h['image_count']
    next_lba=1+total
    dimensions=[]
    with path.open('rb') as f:
        if path.stat().st_size!=h['sectors']*512:
            raise ValueError('TFM2 file length mismatch')
        for i in range(total):
            f.seek((1+i)*512)
            d=validate_sector(f.read(512))
            identity=i if i<h['video_frames'] else 0x80000000|(i-h['video_frames'])
            if d[0]!=int.from_bytes(b'IMG2','little') or d[1]!=identity or not 1<=d[2]<=2048 or not 1<=d[3]<=2048:
                raise ValueError(f'Image descriptor {i} is invalid')
            if d[4]!=next_lba or d[5]!=(d[2]+127)//128 or d[6]!=d[5]*d[3] or d[4]+d[6]>h['audio_lba']:
                raise ValueError(f'Image layout {i} is invalid or overlapping')
            f.seek(d[4]*512)
            payload=f.read(d[6]*512)
            if zlib.crc32(payload)!=d[7] or any(payload[3::4]):
                raise ValueError(f'Source image {i} has invalid CRC or X channel')
            stride=d[5]*512
            if any(any(payload[y*stride+d[2]*4:(y+1)*stride]) for y in range(d[3])):
                raise ValueError(f'Source image {i} row padding is nonzero')
            dimensions.append([d[2],d[3]])
            next_lba+=d[6]
        if next_lba!=h['audio_lba']:
            raise ValueError('Undefined data between image and audio areas')
        f.seek(h['audio_lba']*512)
        remaining=h['audio_samples']
        while remaining:
            block=f.read(512);validate_sector(block);used=min(127,remaining)
            if any(block[used*4:508]):
                raise ValueError('Audio trailing padding is nonzero')
            remaining-=used
    return dict(h, source_dimensions=dimensions)

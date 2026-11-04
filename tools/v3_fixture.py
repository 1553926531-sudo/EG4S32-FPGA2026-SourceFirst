
from pathlib import Path
import struct
import zlib


def sector(words):
    data = struct.pack('<' + 'I' * len(words), *words).ljust(508, b'\0')
    return data + struct.pack('<I', zlib.crc32(data))


def generate_one(out, name, frames, sample_lengths=None, cue_times=None):
    samples = sample_lengths or [frames * 3840, 6000, 8000]
    times = cue_times or [[], [0, 1000, 4500], [0, 2000, 7000]]
    index = 1 + frames + 2
    payload = index + 3 + 6
    audio = payload + frames + 2
    lbas = [audio]
    for count in samples:
        lbas.append(lbas[-1] + (count + 126) // 127)
    header = sector([0x314d4654, 3, 1280, 800, 1, 1024000, frames, 80,
                     1, 1, 1 + frames, audio, samples[0], 48000, 16, 2, 1000,
                     lbas[-1], 2, 1, 2, index, 3, payload])
    pixels = [((i + 1) * 769) & 0xffffff for i in range(frames)] + [0xaa1122, 0x33bb44]
    blocks = [struct.pack('<I', value).ljust(512, b'\0') for value in pixels]
    descs = [sector([0x32474d49, i if i < frames else 0x80000000 | (i - frames),
                     1, 1, payload + i, 1, 1, zlib.crc32(block)])
             for i, block in enumerate(blocks)]
    cues = []
    tracks = []
    for track in range(3):
        tracks.append(sector([0x33445541, track, lbas[track], samples[track],
                              lbas[track + 1] - lbas[track], max(0, track - 1),
                              index + 3 + len(cues) if times[track] else 0, len(times[track])]))
        for cue, sample in enumerate(times[track]):
            text = f'TRACK {track} CUE {cue}'.encode('ascii')
            data = bytearray(sector([0x33455543, sample, cue, len(text)]))
            data[16:96] = text.ljust(80, b' ')
            struct.pack_into('<I', data, 508, zlib.crc32(data[:508]))
            cues.append(bytes(data))
    prefix = header + b''.join(descs + tracks + cues + blocks)
    assert len(prefix) == audio * 512
    (out / f'{name}.hex').write_text(''.join(f'{v:08x}\n' for (v,) in struct.iter_unpack('<I', prefix)))
    (out / f'{name}.vh').write_text(
        f'localparam VIDEO_FRAMES={frames},PREFIX_WORDS={len(prefix)//4},FILE_SECTORS={lbas[-1]},'
        f'AUDIO_INDEX={index},CUE_LBA={index+3},PAYLOAD_LBA={payload},'
        f'MOVIE_LBA={lbas[0]},SONG1_LBA={lbas[1]},SONG2_LBA={lbas[2]},MOVIE_SAMPLES={samples[0]};\n')
    (out / f'{name}_map.v').write_text(f'''module media_extent_map(input [31:0] logical_lba,
output [31:0] physical_lba,output valid,output [31:0] expected_header_crc,output [31:0] file_sectors);
assign physical_lba=logical_lba;assign valid=logical_lba<{lbas[-1]};
assign file_sectors={lbas[-1]};assign expected_header_crc=32'h{struct.unpack_from('<I',header,508)[0]:08x};endmodule
''')


def generate(out):
    out.mkdir(exist_ok=True)
    generate_one(out, 'v3_fixture', 4)
    generate_one(out, 'v3_long', 1100)
    generate_one(out, 'v3_seek', 40, [153600, 173211, 130007], [[], [0, 48000, 96000], [0, 24000, 100000]])


if __name__ == '__main__':
    generate(Path(__file__).resolve().parents[1] / 'verification')

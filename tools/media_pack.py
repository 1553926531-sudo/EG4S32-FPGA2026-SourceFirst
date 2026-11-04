
from cli_zh import EnglishArgumentParser, run
import json
import wave
import zlib
from pathlib import Path
from tfm_format import *


def pack(frames, picture, wav, output, frame_ms=1000, image_ms=5000):
    frames = list(frames)
    if not 1 <= len(frames) <= 600 or not 1000 <= frame_ms <= 60000 or not 1000 <= image_ms <= 60000:
        raise ValueError("Video must contain 1-600 frames; frame and image dwell times must be 1000-60000 ms")
    with wave.open(str(wav), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getcomptype()) != (2, 2, 48000, "NONE"):
            raise ValueError("WAV must be 48000 Hz, signed 16-bit little-endian stereo PCM")
        samples = w.getnframes()
        if not 1 <= samples <= 48000 * 3600:
            raise ValueError("Audio duration must be positive and at most one hour")
        pcm = w.readframes(samples)
        if len(pcm) != samples * 4:
            raise ValueError("Incomplete WAV data")
    image_lba = 1 + len(frames) * FRAME_STRIDE
    audio_lba = image_lba + FRAME_STRIDE
    header = checked_sector([MAGIC, 1, WIDTH, HEIGHT, 1, PIXELS, len(frames), frame_ms,
                             1, FRAME_STRIDE, image_lba, audio_lba, samples,
                             48000, 16, 2, image_ms, audio_lba + (samples + 126) // 127])
                                                                 
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as f:
        f.write(header)
        for index, path in enumerate(frames + [picture]):
            payload = read_bmp(Path(path))
            f.write(payload)
            frame_id = index if index < len(frames) else 0xFFFFFFFF
            f.write(checked_sector([TRAILER_MAGIC, frame_id, zlib.crc32(payload)]))
        for off in range(0, len(pcm), 508):
            block = pcm[off:off + 508].ljust(508, b"\0")
            f.write(block + zlib.crc32(block).to_bytes(4, "little"))
    return verify_package(output)


def pack_v2(frames,pictures,wav,output,frame_ms=1000,image_ms=5000):
    frames,pictures=list(frames),list(pictures)
    if not 1<=len(frames)<=600 or not 1<=len(pictures)<=600:
        raise ValueError('Provide 1-600 video frames and 1-600 slideshow images')
    if not 1000<=frame_ms<=60000 or not 1000<=image_ms<=60000:
        raise ValueError('Dwell time must be 1000-60000 ms')
    with wave.open(str(wav),'rb') as w:
        if (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getcomptype())!=(2,2,48000,'NONE'):
            raise ValueError('WAV must be 48 kHz, 16-bit stereo PCM')
        samples=w.getnframes()
        if not 1<=samples<=172800000:
            raise ValueError('Audio duration must be positive and at most one hour')
        pcm=w.readframes(samples)
        if len(pcm)!=samples*4:
            raise ValueError('Incomplete WAV data')
    next_lba=1+len(frames)+len(pictures)
    metadata=[]
    for i,path in enumerate(frames+pictures):
        width,height,payload=read_bmp_source(Path(path))
        identity=i if i<len(frames) else 0x80000000|(i-len(frames))
        metadata.append((Path(path),checked_sector([int.from_bytes(b'IMG2','little'),identity,
                         width,height,next_lba,(width+127)//128,len(payload)//512,zlib.crc32(payload)])))
        next_lba+=len(payload)//512
    audio_lba=next_lba
    header=checked_sector([MAGIC,2,WIDTH,HEIGHT,1,PIXELS,len(frames),frame_ms,1,1,
                           1+len(frames),audio_lba,samples,48000,16,2,image_ms,
                           audio_lba+(samples+126)//127,len(pictures),1])
    output=Path(output);output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('xb') as f:
        f.write(header)
        for _,descriptor in metadata:f.write(descriptor)
        for path,descriptor in metadata:
            _,_,payload=read_bmp_source(path)
            if zlib.crc32(payload)!=validate_sector(descriptor)[7]:
                raise ValueError(f'{path}: source file changed during packing')
            f.write(payload)
        for off in range(0,len(pcm),508):
            block=pcm[off:off+508].ljust(508,b'\0')
            f.write(block+zlib.crc32(block).to_bytes(4,'little'))
    return verify_package(output)


def main():
    p = EnglishArgumentParser(description='Pack BMP frame sequences, images, and stereo WAV. TFM2 scaling runs on the FPGA.')
    p.add_argument("--frames", type=Path, help="Folder of 24-bit BMP video frames, sorted by filename; all frames are retained")
    images = p.add_mutually_exclusive_group()
    images.add_argument("--image", type=Path, help="TFM1: one 1280x800 BMP, compatible with the original demo format")
    images.add_argument("--images", type=Path, help="TFM2: folder of BMP slideshow images; scaling runs on the FPGA")
    p.add_argument("--wav", type=Path, help="48 kHz, 16-bit stereo PCM WAV")
    p.add_argument("--out", type=Path, help="New media container path; refuses to overwrite")
    p.add_argument("--frame-ms", type=int, default=1000, help="Minimum video frame dwell in ms (default: 1000)")
    p.add_argument("--image-ms", type=int, default=5000, help="Minimum image dwell in ms (default: 5000)")
    p.add_argument("--verify", type=Path, help="Verify an existing media container read-only")
    a = p.parse_args()
    if a.verify:
        h = verify_package(a.verify)
    else:
        if not all((a.frames, a.image or a.images, a.wav, a.out)):
            p.error("Packing requires --frames, --image or --images, --wav, and --out; use --verify for an existing container")
        frames = sorted(a.frames.glob("*.bmp"))
        if a.images:
            h=pack_v2(frames, sorted(a.images.glob('*.bmp')),a.wav,a.out,a.frame_ms,a.image_ms)
        else:
            h = pack(frames, a.image, a.wav, a.out, a.frame_ms, a.image_ms)
    print('Media verification passed. Machine-readable format parameters follow:')
    print(json.dumps(h, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    run(main)

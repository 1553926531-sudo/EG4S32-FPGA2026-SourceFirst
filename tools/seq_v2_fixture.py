
from pathlib import Path
import struct
import zlib
from tfm_format import checked_sector,MAGIC

DIMS=[(129,5),(3,3),(7,9),(2048,1),(1,16)]


def pixel(index,x,y):return ((index+1)<<20)|((y&255)<<8)|(x&255)


def generate(out):
    out.mkdir(exist_ok=True)
    lba=1+len(DIMS);descs=[];payloads=[]
    for i,(w,h) in enumerate(DIMS):
        row_words=((w+127)//128)*128
        data=b''.join(struct.pack('<I',pixel(i,x,y) if x<w else 0) for y in range(h) for x in range(row_words))
        descs.append(checked_sector([int.from_bytes(b'IMG2','little'),i if i<2 else 0x80000000|(i-2),
                                    w,h,lba,row_words//128,len(data)//512,zlib.crc32(data)]))
        payloads.append(data);lba+=len(data)//512
    audio_samples=5000
    pcm=[(i<<16)|((~i)&65535) for i in range(audio_samples)]
    audio=[]
    for start in range(0,audio_samples,127):
        block=b''.join(struct.pack('<I',v) for v in pcm[start:start+127]).ljust(508,b'\0')
        audio.append(block+struct.pack('<I',zlib.crc32(block)))
    head=checked_sector([MAGIC,2,1280,800,1,1024000,2,1000,1,1,3,lba,audio_samples,48000,16,2,1000,
                         lba+len(audio),3,1])
    package=head+b''.join(descs+payloads+audio)
    (out/'seq_v2_words.hex').write_text('\n'.join(f'{v:08x}' for (v,) in struct.iter_unpack('<I',package))+'\n')
    (out/'seq_v2_map.v').write_text(f'''module media_extent_map(input [31:0] logical_lba,
output [31:0] physical_lba,output valid,output [31:0] expected_header_crc,output [31:0] file_sectors);
assign physical_lba=logical_lba;assign valid=logical_lba<{len(package)//512};
assign expected_header_crc=32'h{struct.unpack_from('<I',head,508)[0]:08x};
assign file_sectors={len(package)//512};endmodule
''')
    lines=[]
    dw,dh=128,8
    for mode in range(4):
        for i,(w,h) in enumerate(DIMS):
            crop_x=crop_y=0
            if mode==3:
                rw, rh=min(w,dw),min(h,dh);sw,sh=rw,rh
                crop_x=max(0,(w-dw)//2);crop_y=max(0,(h-dh)//2)
            elif mode==2:rw,rh,sw,sh=dw,dh,w,h
            else:
                if w*dh>=h*dw:rw,rh=dw,max(1,h*dw//w)
                else:rw,rh=max(1,w*dh//h),dh
                sw,sh=w,h
            left,top=(dw-rw)//2,(dh-rh)//2
            for y in range(dh):
                for x in range(dw):
                    v=pixel(i,crop_x+(x-left)*sw//rw,crop_y+(y-top)*sh//rh) if left<=x<left+rw and top<=y<top+rh else 0
                    lines.append(f'{v:08x}')
    (out/'seq_v2_expected.hex').write_text('\n'.join(lines)+'\n')
    (out/'seq_v2_constants.vh').write_text(f'localparam TOTAL_WORDS={len(package)//4},AUDIO_LBA={lba};\n')


if __name__=='__main__':generate(Path(__file__).resolve().parents[1]/'verification')

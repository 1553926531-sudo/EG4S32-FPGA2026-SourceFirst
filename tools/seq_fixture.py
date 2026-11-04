
import array
from pathlib import Path
import struct
import sys
import zlib
from tfm_format import checked_sector, MAGIC, TRAILER_MAGIC


def generate(out):
    out.mkdir(exist_ok=True)
    def frame_crc(pattern):
        a=array.array('I',(i^pattern for i in range(1024000)))
        if sys.byteorder!='little':a.byteswap()
        return zlib.crc32(a.tobytes())
    crcs=[frame_crc(0x13579b),frame_crc(0x2468ac)]
    header=checked_sector([MAGIC,1,1280,800,1,1024000,1,1000,1,8001,
                           8002,16003,300,48000,16,2,1000,16006])
    trailer=[checked_sector([TRAILER_MAGIC,0,crcs[0]]),
             checked_sector([TRAILER_MAGIC,0xffffffff,crcs[1]])]
    audio=[]
    for sector in range(3):
        b=b''.join(struct.pack('<I',(i<<16)|((~i)&65535))
                   if i<300 else b'\0'*4 for i in range(sector*127,(sector+1)*127))
        audio.append(zlib.crc32(b))
    h=struct.unpack('<128I',header)
    lines=['// Offline test only; Python zlib independently computes CRCs.',
           'function [31:0] sector_word;input [31:0] lba;input [6:0] word;',
           'reg [31:0] n;begin sector_word=0;', 'case(lba)', '0:case(word)']
    for i,v in enumerate(h):
        if v:lines.append(f"7'd{i}:sector_word=32'h{v:08x};")
    lines+=['default:sector_word=0;endcase']
    for lba,t in zip([8001,16002],trailer):
        lines.append(f'{lba}:case(word)')
        for i,v in enumerate(struct.unpack('<128I',t)):
            if v:lines.append(f"7'd{i}:sector_word=32'h{v:08x};")
        lines.append('default:sector_word=0;endcase')
    lines+=['default:begin',
            "if(lba>=1 && lba<=8000)sector_word=((lba-1)*128+word)^32'h0013579b;",
            "else if(lba>=8002 && lba<=16001)sector_word=((lba-8002)*128+word)^32'h002468ac;",
            'else if(lba>=16003 && lba<=16005)begin',
            'n=(lba-16003)*127+word;',
            "if(word<127 && n<300)sector_word=(n<<16)|((~n)&65535);",
            'if(word==127)case(lba)']
    for i,c in enumerate(audio):lines.append(f"{16003+i}:sector_word=32'h{c:08x};")
    lines+=['default:sector_word=0;endcase','end','end','endcase','end endfunction']
    (out/'seq_words.vh').write_text('\n'.join(lines)+'\n')
    prefix=array.array('I',(i^0x13579b for i in range(1023872)))
    if sys.byteorder!='little':prefix.byteswap()
    (out/'seq_checkpoint.vh').write_text(
        '// Test checkpoint skips already-covered bulk pixels, then validates the last sector/trailer.\n'
        f"localparam [31:0] VIDEO_PREFIX_CRC=32'h{(zlib.crc32(prefix.tobytes())^0xffffffff):08x};\n")
    (out/'seq_map.v').write_text(f'''`timescale 1ns/1ps
module media_extent_map(input [31:0] logical_lba,output [31:0] physical_lba,
output valid,output [31:0] expected_header_crc,output [31:0] file_sectors);
assign physical_lba=logical_lba;assign valid=logical_lba<16006;
assign expected_header_crc=32'h{h[127]:08x};assign file_sectors=16006;endmodule
''')


if __name__=='__main__':generate(Path(__file__).resolve().parents[1]/'verification')

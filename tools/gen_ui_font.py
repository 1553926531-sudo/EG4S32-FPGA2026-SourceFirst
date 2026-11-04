
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = Path('C:/Windows/Fonts/consolab.ttf')
SUBTITLE = 'FPGA MEDIA PLAYER  REAL AUDIO WAVEFORM  USE KEYS TO ADJUST   '


def generate():
    font = ImageFont.truetype(str(FONT), 13)
    memory = [0] * 2048
    rows = {}
    reference = ['`timescale 1ns/1ps',
                 'module ui_font_zh(input wire [7:0] code,input wire [3:0] row,output reg [15:0] bits);',
                 'always @* begin bits=0;case({code,row})']
    for code in range(33, 127):
        char = chr(code)
        im = Image.new('1', (8, 16))
        box = font.getbbox(char)
                                                                        
                                                                          
        ImageDraw.Draw(im).text(((8-font.getlength(char))/2, 0), char, font=font, fill=1)
        bitmap = []
        for y in range(16):
            value = sum(int(im.getpixel((x, y))) << (7-x) for x in range(8))
            memory[code*16+y] = value
            bitmap.append(value << 8)
            if value:
                reference.append(f"12'h{code*16+y:03x}:bits=16'h{value<<8:04x};")
        rows[char] = bitmap
    reference += ['default:begin end', 'endcase end', 'endmodule', '']
    (ROOT/'rtl/ui_font_zh.v').write_text('\n'.join(reference), encoding='ascii')
    for bank in range(2):
        mif = ['DEPTH = 1024;', 'WIDTH = 8;', 'ADDRESS_RADIX = HEX;',
               'DATA_RADIX = HEX;', 'CONTENT', 'BEGIN']
        mif += [f'{addr:03x} : {memory[bank*1024+addr]:02x};' for addr in range(1024)]
        mif += ['END;', '']
        (ROOT/f'rtl/ui_font_{bank}.mif').write_text('\n'.join(mif), encoding='ascii')
    sync = '''`timescale 1ns/1ps
module ui_font_zh_sync(input wire clk,input wire [7:0] code,
 input wire [3:0] row,output wire [15:0] bits);
`ifdef __ICARUS__
 wire [15:0] reference_bits;reg [15:0] value;
 ui_font_zh reference(.code(code),.row(row),.bits(reference_bits));
 always @(posedge clk)value<=reference_bits;
 assign bits=value;
`else
 wire [7:0] low,high;reg bank,valid;
 always @(posedge clk)begin bank<=code[6];valid<=!code[7];end
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
  .DATA_WIDTH_B(8),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
  .MODE("SP"),.REGMODE_A("NOREG"),.IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),
  .INIT_FILE("ui_font_0.mif"),.FILL_ALL("NONE")) rom_low(
  .dia(8'd0),.addra({code[5:0],row}),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),
  .rsta(1'b0),.bea(1'b1),.doa(low),.dib(8'd0),.addrb(10'd0),.ceb(1'b0),.oceb(1'b0),
  .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
  .DATA_WIDTH_B(8),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
  .MODE("SP"),.REGMODE_A("NOREG"),.IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),
  .INIT_FILE("ui_font_1.mif"),.FILL_ALL("NONE")) rom_high(
  .dia(8'd0),.addra({code[5:0],row}),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),
  .rsta(1'b0),.bea(1'b1),.doa(high),.dib(8'd0),.addrb(10'd0),.ceb(1'b0),.oceb(1'b0),
  .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
 assign bits=valid?{bank?high:low,8'd0}:16'd0;
`endif
endmodule
'''
    (ROOT/'rtl/ui_font_zh_sync.v').write_text(sync, encoding='ascii')
    (ROOT/'verification/ui_font.json').write_text(json.dumps(dict(
        language='English', width=8, height=16, scale=2, font=FONT.name,
        font_sha256=hashlib.sha256(FONT.read_bytes()).hexdigest(), subtitle=SUBTITLE,
        codes={chr(c):c for c in range(32,127)}, rows=rows), indent=2), encoding='ascii')


if __name__ == '__main__':
    generate()

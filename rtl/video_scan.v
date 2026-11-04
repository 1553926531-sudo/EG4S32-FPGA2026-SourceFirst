`timescale 1ns/1ps
                                                                      
                                                                        
module video_scan(input wire pclk,input wire reset_n,input wire enable,input wire fatal,
 input wire [31:0] pixel_data,input wire pixel_valid,input wire [13:0] pixel_level,
 output wire pixel_ready,output reg underrun,
 output reg [23:0] rgb,output reg de,output reg hs,output reg vs);
 reg [10:0] h;
 reg [9:0] v;
 reg started;
 wire active=(h>=220 && h<1500 && v>=25 && v<825);
 wire invalid=fatal || underrun || !started;
 assign pixel_ready=active && started && !fatal && !underrun;
 wire [10:0] x=h-220;
 wire [9:0] y=v-25;
 reg [4:0] glyph_row;
 reg [6:0] letter;
 wire [3:0] char_no=(x-32)>>6;
 wire [2:0] glyph_y=(y-32)>>3;
 wire [2:0] glyph_x=(x-32)>>3;
 always @* begin
  case(char_no)0:letter="I";1:letter="N";2:letter="V";3:letter="A";4:letter="L";5:letter="I";6:letter="D";default:letter=" ";endcase
  glyph_row=0;
  case(letter)
   "I":case(glyph_y)0,6:glyph_row=31;default:glyph_row=4;endcase
   "N":case(glyph_y)0,6:glyph_row=17;1:glyph_row=25;2:glyph_row=25;3:glyph_row=21;4,5:glyph_row=19;default:glyph_row=0;endcase
   "V":case(glyph_y)0,1,2,3:glyph_row=17;4,5:glyph_row=10;6:glyph_row=4;default:glyph_row=0;endcase
   "A":case(glyph_y)0:glyph_row=14;3:glyph_row=31;default:glyph_row=17;endcase
   "L":case(glyph_y)6:glyph_row=31;default:glyph_row=16;endcase
   "D":case(glyph_y)0,6:glyph_row=30;default:glyph_row=17;endcase
   default:glyph_row=0;
  endcase
 end
 wire text_on=(x>=32 && x<480 && y>=32 && y<88 && glyph_x<5 && glyph_row[4-glyph_x]);
 always @(posedge pclk) begin
  if(!reset_n)begin h<=0;v<=0;started<=0;underrun<=0;rgb<=0;de<=0;hs<=0;vs<=0;end
  else begin
   if(h==1649)begin h<=0;if(v==829)v<=0;else v<=v+1'b1;end else h<=h+1'b1;
   if(h==0 && v==0 && enable && pixel_level>=4096 && !fatal && !underrun)started<=1;
   if(pixel_ready && !pixel_valid)underrun<=1;
   de<=active;hs<=(h>=1610);vs<=(v<5);
   if(!active)rgb<=0;
   else if(invalid || !pixel_valid)begin
    if(text_on)rgb<=24'hffff00;
    else rgb<=(x[5]^y[5])?24'hff0033:24'h570057;
   end else rgb<=pixel_data[23:0];
  end
 end
endmodule

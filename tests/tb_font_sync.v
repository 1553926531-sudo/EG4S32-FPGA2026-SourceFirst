`timescale 1ns/1ps
module tb_font_sync;
 reg clk=0;always #5 clk=~clk;
 reg [7:0] code=0;reg [3:0] row=0;
 wire [15:0] expected,actual;
 ui_font_zh reference(.code(code),.row(row),.bits(expected));
 ui_font_zh_sync dut(.clk(clk),.code(code),.row(row),.bits(actual));
 integer c,r;
 initial begin
  for(c=0;c<256;c=c+1)for(r=0;r<16;r=r+1)begin
   @(negedge clk);code=c;row=r;@(posedge clk);#1;
   if(actual!==expected)begin $display("FAIL font bank code=%0d row=%0d got=%h expected=%h",c,r,actual,expected);$finish;end
  end
  $display("PASS font_sync: all 4096 code/row addresses match the rendered English glyph reference");$finish;
 end
endmodule

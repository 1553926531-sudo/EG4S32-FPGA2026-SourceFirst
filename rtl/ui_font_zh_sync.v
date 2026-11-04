`timescale 1ns/1ps
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

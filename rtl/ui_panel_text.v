`timescale 1ns/1ps
module ui_panel_text(input wire clk,input wire [3:0] line_id,
 input wire [6:0] character,output wire [7:0] code);
`ifdef __ICARUS__
 reg [7:0] memory[0:2047];reg [7:0] q;
 initial $readmemh("rtl/ui_panel_text.hex",memory);
 always @(posedge clk)q<=memory[{line_id,character}];
 assign code=q;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
  .BYTE_ENABLE(0),.MODE("SP"),.REGMODE_A("NOREG"),.IMPLEMENT("9K"),
  .INIT_FILE("ui_panel_text.mif")) text_memory(
  .dia(8'd0),.addra({line_id,character}),.cea(1'b1),.ocea(1'b1),.clka(clk),
  .wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(code));
`endif
endmodule

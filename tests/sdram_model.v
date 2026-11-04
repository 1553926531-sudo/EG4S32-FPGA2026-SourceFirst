`timescale 1ns/1ps
                                                                                   
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,
 input [1:0] ba,inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 reg [31:0] mem[0:2097151];
 reg [10:0] row[0:3];
 reg [1:0] bank;
 reg [7:0] col;
 reg reading=0,writing=0,drive=0;
 reg [31:0] q;
 integer latency;
 wire [2:0] cmd={ras_n,cas_n,we_n};
 assign dq=drive?q:32'bz;
 always @(posedge clk)if(!cs_n && cke)begin
  if(reading && cmd!=3'b110 && cmd!=3'b010)begin
   if(latency!=0)latency=latency-1;
   else begin q<=mem[{bank,row[bank],col}];drive<=1;col=col+1'b1;end
  end
  if(writing && cmd!=3'b110 && cmd!=3'b010)begin
   mem[{bank,row[bank],col}]=dq;col=col+1'b1;
  end
  case(cmd)
   3'b011:row[ba]=addr;
   3'b101:begin bank=ba;col=addr[7:0];reading=1;writing=0;latency=2;end
   3'b100:begin bank=ba;col=addr[7:0];writing=1;reading=0;drive<=0;
    mem[{ba,row[ba],addr[7:0]}]=dq;col=col+1'b1;end
   3'b110,3'b010:begin reading=0;writing=0;drive<=0;end
   default:begin end
  endcase
 end
endmodule

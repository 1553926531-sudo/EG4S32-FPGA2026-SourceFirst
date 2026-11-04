`timescale 1ns/1ps
                                                      
                                                                         
                                                                          
                                                                                   
module sdram_burst #(parameter INIT_CYCLES=17000, parameter REFRESH_CYCLES=600)(
 input wire clk, input wire reset_n,
 input wire req, input wire write, input wire [20:0] address,
 output wire ready, output reg done, output reg initialized,
 input wire [31:0] wr_data,input wire wr_valid,output wire wr_ready,
 output reg [31:0] rd_data,output reg rd_valid,output reg fault);
 localparam WAIT_INIT=0,INIT_PRE=1,WAIT_PRE=2,INIT_REF=3,WAIT_REF=4,MODE=5,
  WAIT_MODE=6,IDLE=7,ACT=8,RCD=9,READ=10,LAT=11,RDATA=12,
  WDATA=13,TERM=14,RECOVER=15,PRE=16,RP=17,REF=18,RFC=19;
 reg [4:0] state;
 reg [14:0] timer;
 reg [2:0] init_refs;
 reg [9:0] refresh_timer;
 reg refresh_pending;
 reg [20:0] addr_q;
 reg write_q;
 reg [8:0] beat;
 reg [31:0] dq_out;
 wire [31:0] dq;
 reg dq_oe;
 reg ras_n,cas_n,we_n;
 reg [10:0] addr;
 reg [1:0] bank;
 assign dq=dq_oe ? dq_out : 32'bz;
 assign ready=(state==IDLE && !refresh_pending && initialized);
 assign wr_ready=(state==WDATA);
 wire mem_clk=~clk;
                                                                           
                                                                             
                                                                        
 always @(posedge clk) rd_data<=dq;
 sdram ram(.clk(mem_clk),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
  .addr(addr),.ba(bank),.dq(dq),.cs_n(1'b0),.dm0(1'b0),.dm1(1'b0),
  .dm2(1'b0),.dm3(1'b0),.cke(1'b1));
 always @* begin
  ras_n=1;cas_n=1;we_n=1;addr=0;bank=addr_q[20:19];dq_oe=0;
                                                                          
                                                                          
                                                                         
                                                                          
  dq_out=wr_valid ? wr_data : 32'b0;
  case(state)
   INIT_PRE:begin ras_n=0;we_n=0;addr=11'h400;bank=0;end
   INIT_REF,REF:begin ras_n=0;cas_n=0;end
   MODE:begin ras_n=0;cas_n=0;we_n=0;addr=11'h037;bank=0;end
   ACT:begin ras_n=0;addr=addr_q[18:8];end
   READ:begin cas_n=0;addr={3'b0,addr_q[7:0]};end
   WDATA:begin
    dq_oe=1;
    if(beat==0) begin cas_n=0;we_n=0;addr={3'b0,addr_q[7:0]};end
   end
   TERM:we_n=0;
   PRE:begin ras_n=0;we_n=0;addr=0;end
   default:begin end
  endcase
 end
 always @(posedge clk) begin
  if(!reset_n) begin
   state<=WAIT_INIT;timer<=0;init_refs<=0;refresh_timer<=0;
   refresh_pending<=0;addr_q<=0;write_q<=0;beat<=0;done<=0;
   initialized<=0;rd_valid<=0;fault<=0;
  end else begin
   done<=0;rd_valid<=0;
   if(initialized) begin
    if(refresh_timer==REFRESH_CYCLES-1) begin refresh_timer<=0;refresh_pending<=1;end
    else refresh_timer<=refresh_timer+1'b1;
   end
   case(state)
    WAIT_INIT:if(timer==INIT_CYCLES-1)begin state<=INIT_PRE;timer<=0;end else timer<=timer+1'b1;
    INIT_PRE:begin timer<=3;state<=WAIT_PRE;end
    WAIT_PRE:if(timer==0)state<=INIT_REF;else timer<=timer-1'b1;
    INIT_REF:begin timer<=8;state<=WAIT_REF;end
    WAIT_REF:if(timer!=0)timer<=timer-1'b1;else if(init_refs==7)state<=MODE;
     else begin init_refs<=init_refs+1'b1;state<=INIT_REF;end
    MODE:begin timer<=3;state<=WAIT_MODE;end
    WAIT_MODE:if(timer!=0)timer<=timer-1'b1;else begin initialized<=1;state<=IDLE;end
    IDLE:if(refresh_pending)state<=REF;else if(req)begin
     addr_q<=address;write_q<=write;beat<=0;state<=ACT;
     if((write && address[6:0]!=0)||(!write && address[7:0]!=0))fault<=1;
    end
    ACT:begin timer<=2;state<=RCD;end
    RCD:if(timer!=0)timer<=timer-1'b1;else state<=write_q?WDATA:READ;
    READ:begin timer<=2;state<=LAT;end
    LAT:if(timer!=0)timer<=timer-1'b1;else begin rd_valid<=1;beat<=1;state<=RDATA;end
    RDATA:begin
     rd_valid<=1;
     if(beat==255)state<=TERM;else beat<=beat+1'b1;
    end
    WDATA:begin
     if(!wr_valid)fault<=1;
     if(beat==127)state<=TERM;else beat<=beat+1'b1;
    end
    TERM:begin timer<=2;state<=RECOVER;end
    RECOVER:if(timer!=0)timer<=timer-1'b1;else state<=PRE;
    PRE:begin timer<=2;state<=RP;end
    RP:if(timer!=0)timer<=timer-1'b1;else begin state<=IDLE;done<=1;end
    REF:begin refresh_pending<=0;timer<=8;state<=RFC;end
    RFC:if(timer!=0)timer<=timer-1'b1;else state<=IDLE;
    default:begin state<=WAIT_INIT;fault<=1;end
   endcase
  end
 end
endmodule

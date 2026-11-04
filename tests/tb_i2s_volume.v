`timescale 1ns/1ps
module tb_i2s_volume;
 reg clk=0,reset_n=0,start=0;
 always #5 clk=~clk;
 localparam [31:0] N=32'd272;
 reg [4:0] volume=16;reg muted=0;
 wire ready,done,under,bclk,ws,sd;
 integer consumed=0,checked=0,bitpos=-1;
 integer a,b,g,ea,eb;
 reg [31:0] expected[0:N-1];reg [15:0] serial=0,left=0;
 reg last_ws=0,pending=0;
 function [31:0] pattern;
  input integer n;
  begin case(n/34)
   0:pattern=32'h7fff8000;1:pattern=32'h80007fff;
   2:pattern=32'h0001ffff;3:pattern=32'hffff0001;
   4:pattern=32'h1234abcd;5:pattern=32'hf1231fed;
   6:pattern=32'h00000000;default:pattern=(n*32'hc5d72a81)^32'ha15e9b37;
  endcase end
 endfunction
 wire [31:0] data=pattern(consumed);
 i2s_player #(.VOLUME_CONTROL(1)) dut(.mclk(clk),.reset_n(reset_n),.start_toggle(start),
  .total_samples(N),.done_toggle(done),.underrun(under),.sample_data(data),
  .sample_valid(consumed<N),.sample_ready(ready),.bclk(bclk),.lrclk(ws),.sdata(sd),
  .pause(1'b0),.flush_toggle(1'b0),.volume(volume),.muted(muted));
                                                                      
                                                                          
 always @(negedge clk)if(reset_n && dut.phase==80)begin
  volume=consumed%17;muted=(consumed/17)%2;
 end
 always @(posedge clk)if(reset_n && ready)begin
  a=$signed(data[15:0]);b=$signed(data[31:16]);g=muted?0:volume;
  ea=(a*g)>>>4;eb=(b*g)>>>4;
  expected[consumed]={eb[15:0],ea[15:0]};consumed=consumed+1;
 end
 always @(posedge bclk)if(reset_n)begin
  if(ws!=last_ws)begin bitpos=0;last_ws=ws;end else bitpos=bitpos+1;
  if(bitpos>=1 && bitpos<=16)serial={serial[14:0],sd};
  if(bitpos==16)begin
   if(!ws)begin left=serial;pending=checked<consumed;end
   else if(pending)begin
    if({serial,left}!==expected[checked])begin
     $display("FAIL i2s_volume sample=%0d got=%h expected=%h",checked,{serial,left},expected[checked]);$finish;
    end
    checked=checked+1;pending=0;
   end
  end
 end
 initial begin
  #43;reset_n=1;#300;start=1;
  wait(done==1);repeat(600)@(negedge clk);
  if(under || consumed!=N || checked!=N)begin
   $display("FAIL i2s_volume completion under=%b consumed=%0d checked=%0d",under,consumed,checked);$finish;
  end
  $display("PASS i2s_volume: 272 decoded stereo samples, every level 0..16, mute/unmute, full signed range, mid-word changes remain stereo atomic, unchanged consumption and completion");$finish;
 end
 initial begin #1000000;$display("FAIL i2s_volume timeout");$finish;end
endmodule

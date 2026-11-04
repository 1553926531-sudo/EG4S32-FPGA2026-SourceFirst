`timescale 1ns/1ps
module tb_i2s;
 reg clk=0,reset_n=0,start=0;
 always #5 clk=~clk;
 wire done,under,ready,bclk,ws,sd;
 reg [31:0] samples[0:2];
 integer consumed=0,checked=0,bitpos=-1;
 reg last_ws=0,locked=0;
 reg [15:0] bits=0,left=0;
 wire [31:0] data=consumed<3?samples[consumed]:32'h0;
 i2s_player dut(.mclk(clk),.reset_n(reset_n),.start_toggle(start),.total_samples(32'd3),
  .done_toggle(done),.underrun(under),.sample_data(data),.sample_valid(consumed<3),
  .sample_ready(ready),.bclk(bclk),.lrclk(ws),.sdata(sd),.pause(1'b0),.flush_toggle(1'b0));
 always @(posedge clk)if(reset_n && ready && consumed<3)consumed<=consumed+1;
 always @(posedge bclk)if(reset_n)begin
  if(ws!=last_ws)begin bitpos=0;last_ws=ws;end
  else bitpos=bitpos+1;
  if(bitpos>=1 && bitpos<=16)bits={bits[14:0],sd};
  if(bitpos==16)begin
   if(!ws)left=bits;
   else if(locked || {bits,left}!=0)begin
    locked=1;
    if(checked>=3 || {bits,left}!==samples[checked])begin
     $display("FAIL I2S sample %d got %h expected %h",checked,{bits,left},samples[checked]);$finish;
    end
    checked=checked+1;
    if(checked==3)locked=0;
   end
  end
 end
 initial begin
  samples[0]=32'h91bc1234;samples[1]=32'h0000ffff;samples[2]=32'h7fff8000;
  #43 reset_n=1;#300;start=1;
  wait(done==1);#2600;
  if(under || consumed!=3 || checked!=3)$display("FAIL I2S completion under=%d consumed=%d checked=%d",under,consumed,checked);
  else $display("PASS i2s: Philips delay, exact signed stereo order, completion");
  $finish;
 end
 initial begin #30000;$display("FAIL I2S timeout");$finish;end
endmodule

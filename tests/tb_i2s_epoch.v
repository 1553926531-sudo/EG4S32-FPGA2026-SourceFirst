`timescale 1ns/1ps
                                                                             
                                                                                
module tb_i2s_epoch;
 reg clk=0,reset_n=0,start=0,flush=0,pause=0;
 always #7 clk=~clk;
 reg [31:0] total=300;
 wire ready,done,under,bclk,ws,sd,epoch;
 wire [31:0] gray;
 integer accepted=0,n,paused_count;
 reg [31:0] previous_gray=0,difference;
 reg previous_epoch=0,previous_flush=0;
 i2s_player dut(.mclk(clk),.reset_n(reset_n),.start_toggle(start),.total_samples(total),
  .done_toggle(done),.underrun(under),.sample_data(32'h1234abcd),.sample_valid(1'b1),
  .sample_ready(ready),.bclk(bclk),.lrclk(ws),.sdata(sd),.pause(pause),
  .flush_toggle(flush),.playhead_gray(gray),.playhead_epoch(epoch));
 function [31:0] decode;
  input [31:0] g;integer bit_index;
  begin decode[31]=g[31];for(bit_index=30;bit_index>=0;bit_index=bit_index-1)
   decode[bit_index]=decode[bit_index+1]^g[bit_index];end
 endfunction
 task bad;input [511:0] message;begin
  $display("FAIL i2s_epoch %0s accepted=%0d decoded=%0d epoch=%b",message,accepted,decode(gray),epoch);$finish;
 end endtask
 always @(posedge clk)begin
  if(reset_n)begin
   if(ready)accepted=accepted+1;
   #1;
   if(dut.flush_seen!=previous_flush)begin
    accepted=0;previous_flush=dut.flush_seen;
    if(gray!=0 || dut.running || under)bad("flush position/running");
   end else if(epoch!=previous_epoch)begin
    accepted=0;if(gray!=0)bad("start did not reset position");
   end else if(decode(gray)!==accepted)bad("position differs from accepted PCM");
   difference=gray^previous_gray;
   if(epoch==previous_epoch && dut.flush_seen==previous_flush && difference!=0 &&
      gray!=0 && (difference & (difference-1))!=0)bad("multi-bit Gray transition");
   if(under)bad("unexpected underrun");
   previous_gray=gray;previous_epoch=epoch;
  end
 end
 task launch;input [31:0] count;begin
  @(negedge clk);total=count;repeat(8)@(negedge clk);
  start=~start;wait(epoch===start);@(negedge clk);
  if(accepted!=0 || gray!=0)bad("new epoch retained stale position");
 end endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;
  launch(300);wait(accepted==129);@(negedge clk);pause=1;paused_count=accepted;
  repeat(800)@(negedge clk);if(accepted!=paused_count || ready)bad("pause consumed PCM");
  pause=0;wait(done==start);@(negedge clk);
  if(accepted!=300 || decode(gray)!=300)bad("completion position");
  launch(400);wait(accepted==17);@(negedge clk);pause=1;flush=~flush;
  repeat(20)@(negedge clk);if(accepted!=0 || gray!=0 || done!=start)bad("cancel reset");
  pause=0;launch(257);wait(done==start);@(negedge clk);
  if(accepted!=257 || decode(gray)!=257)bad("restart completion");
  $display("PASS i2s_epoch: PCM-counted Gray position, 127/255 carries, epoch reset, pause, cancellation and both start polarities");$finish;
 end
 initial begin #4000000;bad("timeout");end
endmodule

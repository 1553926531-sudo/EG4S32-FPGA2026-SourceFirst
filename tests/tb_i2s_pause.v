`timescale 1ns/1ps
module tb_i2s_pause;
 reg clk=0, reset_n=0, start=0, pause=0;
 always #5 clk=~clk;
 wire done,under,ready,bclk,ws,sd;
 reg [31:0] sample_data=32'h12345678;
 integer consumed=0;
 i2s_player dut(.mclk(clk),.reset_n(reset_n),.start_toggle(start),
  .total_samples(32'd4),.done_toggle(done),.underrun(under),
  .sample_data(sample_data),.sample_valid(1'b1),.sample_ready(ready),
  .bclk(bclk),.lrclk(ws),.sdata(sd),.pause(pause));
 always @(posedge clk) if (reset_n && ready) consumed=consumed+1;
 initial begin
  #43 reset_n=1; #300; start=1;
                                                                        
  #3000 pause=1;
  #2600;
  if (ready || consumed == 0 || under) begin
   $display("FAIL I2S pause ready=%d consumed=%d under=%d",ready,consumed,under);
   $finish;
  end
  pause=0;
  wait(done==1);
  if (under || consumed!=4) begin
   $display("FAIL I2S resume consumed=%d under=%d",consumed,under);
   $finish;
  end
  $display("PASS i2s_pause: clocks stay framed, samples stop/mute, resume completes");
  $finish;
 end
 initial begin #50000; $display("FAIL I2S pause timeout"); $finish; end
endmodule

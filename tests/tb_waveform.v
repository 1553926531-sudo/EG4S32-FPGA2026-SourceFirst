`timescale 1ns/1ps
module tb_waveform;
 reg clk=0,reset_n=0,toggle=0,flush=0,tick=0;
 reg [15:0] pcm=0;
 reg [8:0] index=0;
 wire [9:0] y;
 wire valid;
 always #5 clk=~clk;
 audio_waveform dut(.pclk(clk),.reset_n(reset_n),.pcm(pcm),
  .sample_toggle(toggle),.flush_toggle(flush),.frame_tick(tick),
  .read_index(index),.sample_y(y),.sample_valid(valid));
 task sample;
  input [15:0] data;
  begin @(negedge clk);pcm=data;toggle=~toggle;repeat(6)@(negedge clk);end
 endtask
 task snapshot;
  begin @(negedge clk);tick=1;@(negedge clk);tick=0;end
 endtask
 task check;
  input [8:0] address; input [9:0] expected; input expected_valid;
  begin @(negedge clk);index=address;@(posedge clk);#1;
   if(valid!==expected_valid || (expected_valid && y!==expected))begin
    $display("FAIL waveform index=%d y=%d expected=%d valid=%b",address,y,expected,valid);$finish;
   end
  end
 endtask
 integer i;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  snapshot;check(0,0,0);
  sample(16'h0000);sample(16'h7fff);sample(16'h8000);sample(16'hff00);
  check(0,0,0);                                               
  snapshot;check(0,720,1);check(1,657,1);check(2,784,1);check(3,721,1);check(4,0,0);
  pcm=16'h5000;repeat(30)@(negedge clk);snapshot;
  if(dut.count!==10'd4)begin $display("FAIL waveform wrote without consumption toggle");$finish;end
  for(i=4;i<520;i=i+1)sample({i[7:0],8'd0});
  snapshot;
  check(0,716,1);                                         
  check(255,717,1);                          
  check(511,717,1);                          
  @(negedge clk);flush=~flush;repeat(6)@(negedge clk);
  check(0,0,0);snapshot;check(511,0,0);
  sample(16'h4000);snapshot;check(0,688,1);check(1,0,0);
  $display("PASS waveform: signed consumed PCM, snapshot, ring wrap, no invented samples, flush");$finish;
 end
 initial begin #100000;$display("FAIL waveform timeout");$finish;end
endmodule

`timescale 1ns/1ps
module tb_ui_times;
 reg clk=0,rst_n=0;always #1 clk=~clk;
 reg [15:0] play_seconds=0,total_seconds=0,target_seconds=0;
 wire [23:0] play_time,total_time,target_time;
 integer n,h,m,s;reg [23:0] expected;
 media_ui_times dut(.clk(clk),.rst_n(rst_n),.play_seconds(play_seconds),
  .total_seconds(total_seconds),.target_seconds(target_seconds),
  .play_time(play_time),.total_time(total_time),.target_time(target_time));
 task check;
  input integer value;input [23:0] actual;
  begin
   h=value/3600;m=(value%3600)/60;s=value%60;
   expected[23:20]=h/10;expected[19:16]=h%10;
   expected[15:12]=m/10;expected[11:8]=m%10;
   expected[7:4]=s/10;expected[3:0]=s%10;
   if(actual!==expected)begin
    $display("FAIL UI times seconds=%0d got=%h expected=%h",value,actual,expected);$finish;
   end
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
                                                                              
  for(n=0;n<65536;n=n+1)begin
   play_seconds=n;total_seconds=65535-n;target_seconds=(n*257)%65536;
   repeat(360)@(negedge clk);
   check(play_seconds,play_time);check(total_seconds,total_time);check(target_seconds,target_time);
   if(n%4096==4095)begin $display("TIMES %0d input values checked",n+1);$fflush();end
  end
  $display("PASS ui_times: all 65536 seconds values on three clocks, 196608 independent hh:mm:ss comparisons, forward/backward updates");$finish;
 end
 initial begin #50000000;$display("FAIL UI times timeout");$finish;end
endmodule

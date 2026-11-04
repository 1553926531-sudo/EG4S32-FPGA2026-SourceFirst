`timescale 1ns/1ps
module tb_video;
 reg clk=0,reset_n=0,valid=1;
 always #5 clk=~clk;
 wire ready,under,de,hs,vs;
 wire [23:0] rgb;
 reg [31:0] index=0;
 integer count=0,ticks=0,hcount=0,vcount=0,frames=0;
 video_scan dut(clk,reset_n,1'b1,1'b0,index,valid,14'd8192,ready,under,rgb,de,hs,vs);
 always @(posedge clk)if(reset_n && ready && valid)index<=index+1'b1;
 always @(negedge clk)if(reset_n)begin
  ticks=ticks+1;
  if(hs)hcount=hcount+1;
  if(vs)vcount=vcount+1;
  if(de)begin
   if(rgb!==count[23:0])begin $display("FAIL video pixel %d got %h",count,rgb);$finish;end
   count=count+1;
  end
  if(ticks==1369500)begin
   if(count!=(frames+1)*1024000 || hcount!=40*830 || vcount!=5*1650 || under)begin
    $display("FAIL raster active=%d HS=%d VS=%d under=%d",count,hcount,vcount,under);$finish;
   end
   ticks=0;hcount=0;vcount=0;frames=frames+1;
   if(frames==2)begin
    valid=0;wait(under);#20;
    if(rgb==0)$display("FAIL invalid marker");else $display("PASS video: two exact 1280x800 frames, no spatial loss, 1650x830 raster; underrun visible");
    $finish;
   end
  end
 end
 initial begin #31;reset_n=1;end
 initial begin #30000000;$display("FAIL video timeout");$finish;end
endmodule

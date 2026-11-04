`timescale 1ns/1ps
                                                                             
                                                                             
module tb_frame_store_full;
 localparam WORDS=1024000;
 reg clk50=0,pclk=0,reset50_n=0,resetp_n=0;
 always #10 clk50=~clk50;
 always #6.0845 pclk=~pclk;
 reg [20:0] wa=0;
 reg [31:0] wd=0;
 reg wv=0,pub=0,bank=0;
 wire wr,commit,valid,display_valid,initialized,fault;
 wire [31:0] data;
 wire [13:0] level;
 reg scanning=0;
 integer x=0,y=0,position=0,image_seen=0,frames=0,writes=0;
 integer idle_cycles=0;
                                                                       
                                                                     
 wire ready=scanning && x>=219 && x<1499 && y>=25 && y<825;
 frame_store dut(.clk50(clk50),.reset50_n(reset50_n),.wr_address(wa),.wr_data(wd),
  .wr_valid(wv),.wr_ready(wr),.publish_toggle(pub),.publish_bank(bank),.commit_toggle(commit),
  .pclk(pclk),.resetp_n(resetp_n),.pixel_data(data),.pixel_valid(valid),.pixel_ready(ready),
  .pixel_level(level),.display_valid(display_valid),.memory_initialized(initialized),.fault(fault));
 function [31:0] pattern;
  input integer image,index;
  begin pattern=(index ^ ((image+1)*32'h00324957)) & 32'h00ffffff;end
 endfunction
 task load_image;
  input integer image;
  integer i;
  begin
   $display("full frame_store load image=%d start time=%t",image,$time);$fflush();
   for(i=0;i<WORDS;i=i+1)begin
    @(negedge clk50);wv=1;wa=((image%2)?1048576:0)+i;wd=pattern(image,i);
    @(posedge clk50);while(!wr)@(posedge clk50);
    if((i%262144)==262143)begin
     $display("full frame_store load image=%d accepted=%d time=%t",image,i+1,$time);$fflush();
    end
   end
   @(negedge clk50);wv=0;
  end
 endtask
 always @(posedge clk50)if(reset50_n && wv && wr)writes=writes+1;
 always @(posedge pclk)if(resetp_n)begin
  if(fault)begin $display("FAIL full frame_store memory fault at %t",$time);$finish;end
                                                                            
                                                                           
                                                                            
  if(dut.dma_pop || (ready && valid) || dut.engine_done)idle_cycles=0;
  else if(initialized && (wv || scanning || pub!=commit))begin
   idle_cycles=idle_cycles+1;
   if(idle_cycles>100000)begin
    $display("FAIL full frame_store no progress writes=%d position=%d req=%b ready=%b inflight=%b",writes,position,dut.engine_req,dut.engine_ready,dut.inflight);$finish;
   end
  end else idle_cycles=0;
  if(!scanning && level>=4096)scanning<=1;
  if(scanning)begin
   if(x==1649)begin x<=0;if(y==829)y<=0;else y<=y+1;end else x<=x+1;
  end
  if(ready)begin
   if(!valid)begin $display("FAIL full frame_store underrun image=%d pos=%d",image_seen,position);$finish;end
   if(position==0 && image_seen<2 && data==pattern(image_seen+1,0))image_seen=image_seen+1;
   if(data!==pattern(image_seen,position))begin
    $display("FAIL full frame_store image=%d pixel=%d got=%h expected=%h",image_seen,position,data,pattern(image_seen,position));$finish;
   end
   if(position==WORDS-1)begin
    position=0;frames=frames+1;
    $display("full frame_store frame %d complete, image=%d writes=%d",frames,image_seen,writes);
    $fflush();
    if(image_seen==2)begin
     if(writes!=3*WORDS)begin $display("FAIL full frame_store write count %d",writes);$finish;end
     $display("PASS full frame_store: 1280x800, three exact images, both banks reused, saturated async DMA, complete-frame order; %d frames",frames);
     $finish;
    end
   end else position=position+1;
  end
 end
 initial begin
  #51;reset50_n=1;resetp_n=1;
  wait(initialized);
  load_image(0);
  @(negedge clk50);pub=1;
  wait(commit==1);
  @(negedge clk50);bank=1;
  load_image(1);
  @(negedge clk50);pub=0;
  wait(commit==0);
  @(negedge clk50);bank=0;
  load_image(2);
  @(negedge clk50);pub=1;
  wait(commit==1);
 end
 initial begin #1000000000;$display("FAIL full frame_store timeout");$finish;end
endmodule

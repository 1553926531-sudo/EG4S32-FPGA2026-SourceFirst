`timescale 1ns/1ps
                                                                       
                                                                           
module tb_frame_store;
 localparam TEST_WORDS=4096;
 reg clk50=0,pclk=0,reset50_n=0,resetp_n=0;
 always #10 clk50=~clk50;
 always #6.0845 pclk=~pclk;
 reg [20:0] wa=0;
 reg [31:0] wd=0;
 reg wv=0,pub=0,bank=0;
 wire wr,commit,valid,display_valid,initialized,fault;
 wire [31:0] data;
 wire [13:0] level;
 integer cycles=0,position=0,complete_frames=0,new_frames=0;
 integer refresh_collisions=0,request_wait_cycles=0;
 reg waiting_request=0;
 reg held_write;
 reg [20:0] held_address;
 reg reading=0,new_image=0;
 wire ready=reading && (cycles%4!=0);
 frame_store #(.FRAME_WORDS(TEST_WORDS)) dut(.clk50(clk50),.reset50_n(reset50_n),.wr_address(wa),.wr_data(wd),
  .wr_valid(wv),.wr_ready(wr),.publish_toggle(pub),.publish_bank(bank),.commit_toggle(commit),
  .pclk(pclk),.resetp_n(resetp_n),.pixel_data(data),.pixel_valid(valid),.pixel_ready(ready),
  .pixel_level(level),.display_valid(display_valid),.memory_initialized(initialized),.fault(fault));
 function [31:0] pattern;
  input integer image,index;
  begin pattern=(index^(image?32'h2468ac:32'h13579b));end
 endfunction
 task load_image;
  input integer image;
  integer i;
  begin
   for(i=0;i<TEST_WORDS;i=i+1)begin
    @(negedge clk50);wv=1;wa=(image?1048576:0)+i;wd=pattern(image,i);
    @(posedge clk50);while(!wr)@(posedge clk50);
   end
   @(negedge clk50);wv=0;
  end
 endtask
 always @(posedge pclk)if(resetp_n)begin
  cycles<=cycles+1;
                                                                         
                                                                       
  if(waiting_request && (!dut.engine_req || dut.op_write!==held_write ||
                         dut.engine_address!==held_address))begin
   $display("FAIL frame_store dropped or changed a stalled SDRAM request");$finish;
  end
  waiting_request=dut.engine_req && !dut.engine_ready;
  if(waiting_request)begin
   held_write=dut.op_write;held_address=dut.engine_address;
   request_wait_cycles=request_wait_cycles+1;
  end
  if(level>=TEST_WORDS)reading<=1;
  if(fault)begin $display("FAIL frame_store sticky memory fault");$finish;end
  if(ready)begin
   if(!valid)begin $display("FAIL frame_store underrun position=%d",position);$finish;end
   if(position==0 && data==pattern(1,0))new_image=1;
   if(data!==pattern(new_image,position))begin
    $display("FAIL frame_store pixel position=%d got=%h image=%d",position,data,new_image);$finish;
   end
   if(position==TEST_WORDS-1)begin
    position=0;complete_frames=complete_frames+1;
    if(new_image)new_frames=new_frames+1;
    if(new_frames==1)begin
     if(refresh_collisions!=2 || request_wait_cycles<2)begin
      $display("FAIL frame_store refresh collision coverage missing");$finish;
     end
     $display("PASS frame_store: two 4096-word test banks through async DMA, SDRAM and scan FIFO; ordered frame switch; write/read refresh collisions; %d complete frames",complete_frames);
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
 end
                                                                           
                                                                           
                                                                            
                                                                       
 initial begin
  wait(initialized);
  @(negedge pclk);
  while(!(dut.engine_ready && !dut.inflight && !dut.engine_req &&
          dut.dma_rlevel>=128 && dut.dma_valid))@(negedge pclk);
  force dut.memory.refresh_timer=10'd599;
  @(negedge pclk);release dut.memory.refresh_timer;
  refresh_collisions=refresh_collisions+1;
  while(!(display_valid && dut.engine_ready && !dut.inflight && !dut.engine_req &&
          level<=4096))@(negedge pclk);
  force dut.memory.refresh_timer=10'd599;
  @(negedge pclk);release dut.memory.refresh_timer;
  refresh_collisions=refresh_collisions+1;
 end
 initial begin #150000000;$display("FAIL frame_store timeout");$finish;end
endmodule

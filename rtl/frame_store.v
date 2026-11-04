`timescale 1ns/1ps
                                                                               
                                                                             
                                                                              
module frame_store #(parameter FRAME_WORDS=1024000)(input wire clk50,input wire reset50_n,
 input wire [20:0] wr_address,input wire [31:0] wr_data,
 input wire wr_valid,output wire wr_ready,
 input wire publish_toggle,input wire publish_bank,output reg commit_toggle,
 input wire pclk,input wire resetp_n,
 output wire [31:0] pixel_data,output wire pixel_valid,input wire pixel_ready,
 output wire [13:0] pixel_level,output reg display_valid,
 output wire memory_initialized,output reg fault);
 wire [52:0] dma_head;
 wire dma_valid,dma_pop;
 wire [11:0] dma_wlevel,dma_rlevel;
 async_stream_fifo #(.WIDTH(53),.AW(11)) write_queue(
  .wclk(clk50),.wrst_n(reset50_n),.flush_toggle(1'b0),.in_data({wr_address,wr_data}),.in_valid(wr_valid),
  .in_ready(wr_ready),.write_level(dma_wlevel),.rclk(pclk),.rrst_n(resetp_n),
  .out_data(dma_head),.out_valid(dma_valid),.out_ready(dma_pop),.read_level(dma_rlevel));
 reg engine_req,op_write,inflight;
 reg [20:0] engine_address,expected_write_address;
 wire engine_ready,engine_done,engine_wready,engine_fault;
 wire [31:0] engine_data;
 wire engine_valid,display_fifo_ready;
 assign dma_pop=engine_wready;
 sdram_burst memory(.clk(pclk),.reset_n(resetp_n),.req(engine_req),.write(op_write),
  .address(engine_address),.ready(engine_ready),.done(engine_done),.initialized(memory_initialized),
  .wr_data(dma_head[31:0]),.wr_valid(dma_valid),.wr_ready(engine_wready),
  .rd_data(engine_data),.rd_valid(engine_valid),.fault(engine_fault));
 sync_stream_fifo #(.WIDTH(32),.AW(13)) scan_queue(
  .clk(pclk),.reset_n(resetp_n),.in_data(engine_data),.in_valid(engine_valid),
  .in_ready(display_fifo_ready),.out_data(pixel_data),.out_valid(pixel_valid),
  .out_ready(pixel_ready),.level(pixel_level));
 (* async_reg="true" *) reg publish_sync1,publish_sync2;
 (* async_reg="true" *) reg bank_sync1,bank_sync2;
 reg pending,pending_bank,pending_toggle,front_bank;
 reg [19:0] fetch_offset;
 reg [3:0] fence_count;
 wire write_fenced=(dma_rlevel==0 && !dma_valid && !(inflight && op_write));
 wire frame_fetch_end=engine_done && inflight && !op_write && fetch_offset==(FRAME_WORDS-256);
 always @(posedge pclk) begin
  if(!resetp_n) begin
   engine_req<=0;op_write<=0;inflight<=0;engine_address<=0;expected_write_address<=0;
   publish_sync1<=0;publish_sync2<=0;commit_toggle<=0;pending<=0;
   bank_sync1<=0;bank_sync2<=0;
   pending_bank<=0;pending_toggle<=0;front_bank<=0;fetch_offset<=0;
   display_valid<=0;fault<=0;fence_count<=0;
  end else begin
                                                                            
                                                                           
                                                                              
   if(engine_req && engine_ready)engine_req<=0;
   publish_sync1<=publish_toggle;publish_sync2<=publish_sync1;
   bank_sync1<=publish_bank;bank_sync2<=bank_sync1;
   if(engine_fault || (engine_valid && !display_fifo_ready))fault<=1;
   if(write_fenced)begin if(fence_count!=15)fence_count<=fence_count+1'b1;end
   else fence_count<=0;
   if(publish_sync2!=commit_toggle && !pending && fence_count>=8)begin
    pending<=1;pending_bank<=bank_sync2;pending_toggle<=publish_sync2;
   end
   if(dma_pop)begin
    if(!dma_valid || dma_head[52:32]!=expected_write_address)fault<=1;
    expected_write_address<=expected_write_address+1'b1;
   end
   if(engine_done && inflight)begin
    inflight<=0;
    if(!op_write)begin
     if(fetch_offset==(FRAME_WORDS-256))fetch_offset<=0;
     else fetch_offset<=fetch_offset+20'd256;
    end
   end
   if(pending && memory_initialized && ((!display_valid && !inflight)||frame_fetch_end))begin
    front_bank<=pending_bank;commit_toggle<=pending_toggle;
    display_valid<=1;fetch_offset<=0;pending<=0;
   end
   if(engine_ready && !inflight && !engine_req && !fault)begin
    if(display_valid && pixel_level<=4096)begin
     engine_address<={front_bank,fetch_offset};op_write<=0;engine_req<=1;inflight<=1;
    end else if(dma_rlevel>=128 && dma_valid)begin
     engine_address<=dma_head[52:32];expected_write_address<=dma_head[52:32];
     op_write<=1;engine_req<=1;inflight<=1;
    end else if(display_valid && pixel_level<=7935)begin
     engine_address<={front_bank,fetch_offset};op_write<=0;engine_req<=1;inflight<=1;
    end
   end
  end
 end
endmodule

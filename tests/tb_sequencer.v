`timescale 1ns/1ps
`ifdef DISPATCH_LEGACY_TEST
module tb_dispatch_legacy;
`else
module tb_sequencer;
`endif
 reg clk=0,reset_n=0;always #5 clk=~clk;
 wire req,accept,rdready,wrvalid,pub,pbank,astart,avalid;
 wire [31:0] lba,wdata,samples,adata,logical_lba,frame;
 wire [20:0] waddr;
 wire [19:0] frame_word;
 wire [5:0] state;wire [7:0] error;
 reg busy=0,done=0,commit=0,adone=0;
 reg [31:0] active_lba;
 reg [6:0] index=0;
 integer cycles=0,writes=0,publishes=0,audio_count=0,delay=0;
 reg last_pub=0,last_astart=0;
 wire valid=busy;
 wire wready=(cycles%5!=0);
 wire aready=(cycles%3!=0);
 assign accept=req && !busy && !done;
 `include "seq_words.vh"
 wire [31:0] data=sector_word(active_lba,index);
`ifdef DISPATCH_LEGACY_TEST
 media_dispatch #(.CYCLES_PER_MS(1)) dut(
`else
 media_sequencer #(.CYCLES_PER_MS(1)) dut(
`endif
  .clk50(clk),.reset_n(reset_n),.system_ready(1'b1),.external_fault(1'b0),
  .rd_req(req),.rd_lba(lba),.rd_accept(accept),.rd_data(data),.rd_valid(valid),
  .rd_ready(rdready),.rd_done(done),.rd_error(1'b0),.card_fatal(1'b0),
  .wr_address(waddr),.wr_data(wdata),.wr_valid(wrvalid),.wr_ready(wready),
  .publish_toggle(pub),.publish_bank(pbank),.commit_toggle(commit),
  .audio_start_toggle(astart),.audio_total_samples(samples),.audio_done_toggle(adone),
  .audio_write_level(13'd0),.audio_data(adata),.audio_valid(avalid),.audio_ready(aready),
  .state(state),.error_code(error),.logical_lba(logical_lba),.frame_number(frame),.frame_word(frame_word),
`ifdef DISPATCH_LEGACY_TEST
  .scale_mode(2'd0),
`endif
  .pause(1'b0),.restart(1'b0),.media_select(2'd0),.media_index(10'd0));
 always @(posedge clk)if(reset_n)begin
  cycles<=cycles+1;done<=0;
  if(accept)begin busy<=1;active_lba<=lba;index<=0;end
  if(valid && rdready)begin
   if(index==127)begin busy<=0;done<=1;end else index<=index+1'b1;
  end
  if(wrvalid && wready)begin
   if(waddr!==((writes<1024000)?writes:1048576+writes-1024000) ||
     wdata!==((writes<1024000)?(writes^32'h13579b):((writes-1024000)^32'h2468ac)))begin
    $display("FAIL media DMA pixel %d addr %h data %h",writes,waddr,wdata);$finish;
   end
   writes=writes+1;
  end
  if(pub!=last_pub)begin
   if(writes!=(publishes+1)*1024000)begin $display("FAIL partial frame publication");$finish;end
   last_pub<=pub;delay<=20;publishes=publishes+1;
  end
  if(delay>0)begin delay<=delay-1;if(delay==1)commit<=last_pub;end
  if(avalid && aready)begin
   if(adata!==((audio_count<<16)|((~audio_count)&65535)))begin $display("FAIL PCM order %d",audio_count);$finish;end
   audio_count=audio_count+1;
  end
  if(astart!=last_astart)begin
   last_astart<=astart;
   if(audio_count!=300 || samples!=300)begin $display("FAIL audio prefill/start");$finish;end
   adone<=astart;
  end
  if(error!=0)begin $display("FAIL media error=%h state=%h lba=%d",error,state,logical_lba);$finish;end
  if(state==12)begin
   if(writes!=2048000 || publishes!=2 || audio_count!=300)$display("FAIL media completion");
   else $display("PASS sequencer: full 1024000-pixel video + separate picture + 300 exact stereo samples, independent CRCs, backpressure, commit fences");
   $finish;
  end
 end
 initial begin #31 reset_n=1;end
 initial begin #50000000;$display("FAIL sequencer timeout state=%h",state);$finish;end
endmodule

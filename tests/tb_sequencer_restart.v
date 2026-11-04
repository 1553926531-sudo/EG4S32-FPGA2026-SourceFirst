`timescale 1ns/1ps
                                                                            
                                                                           
                                                                            
module tb_sequencer_restart;
 reg clk=0,reset_n=0;always #5 clk=~clk;
 reg restart=0,allow_accept=0,commit=0,adone=0;
 reg [1:0] selection=0;
 wire req,accept,rdready,wrvalid,pub,pbank,astart,aflush,avalid;
 wire [31:0] lba,wdata,samples,adata,logical_lba,frame;
 wire [20:0] waddr;wire [19:0] frame_word;
 wire [5:0] state;wire [7:0] error;
 reg busy=0,done=0;reg [31:0] active_lba=0;
 reg [6:0] index=0;integer latency=0,done_delay=0,cycles=0;
 integer writes=0,burst_words=0,accepted=0,audio_count=0,flushes=0;
 reg front_valid=0,front_bank=0,last_pub=0,last_flush=0,last_start=0;
 integer completion_delay=0;
 wire valid=busy && latency==0;
 wire wready=(cycles%5!=0);
 assign accept=req && allow_accept && !busy && !done && done_delay==0;
 `include "seq_words.vh"
 `include "seq_checkpoint.vh"
 wire [31:0] data=sector_word(active_lba,index);
 media_sequencer #(.CYCLES_PER_MS(1)) dut(
  .clk50(clk),.reset_n(reset_n),.system_ready(1'b1),.external_fault(1'b0),
  .rd_req(req),.rd_lba(lba),.rd_accept(accept),.rd_data(data),.rd_valid(valid),
  .rd_ready(rdready),.rd_done(done),.rd_error(1'b0),.card_fatal(1'b0),
  .wr_address(waddr),.wr_data(wdata),.wr_valid(wrvalid),.wr_ready(wready),
  .publish_toggle(pub),.publish_bank(pbank),.commit_toggle(commit),
  .audio_start_toggle(astart),.audio_flush_toggle(aflush),.audio_total_samples(samples),
  .audio_done_toggle(adone),.audio_write_level(13'd0),.audio_data(adata),
  .audio_valid(avalid),.audio_ready(1'b1),.state(state),.error_code(error),
  .logical_lba(logical_lba),.frame_number(frame),.frame_word(frame_word),
  .pause(1'b0),.restart(restart),.media_select(selection),.media_index(10'd0));
 always @(posedge clk)if(reset_n)begin
  cycles<=cycles+1;done<=0;
  if(accept)begin busy<=1;active_lba<=lba;index<=0;latency<=8;accepted=accepted+1;end
  if(latency>0)latency<=latency-1;
  if(valid && rdready)begin
   if(index==127)begin busy<=0;done_delay<=4;end else index<=index+1'b1;
  end
  if(done_delay>0)begin done_delay<=done_delay-1;if(done_delay==1)done<=1;end
  if(wrvalid && wready)begin
   if(waddr[6:0]!==burst_words[6:0] || (front_valid && waddr[20]==front_bank))begin
    $display("FAIL restart discontinuous burst/front-bank overwrite addr=%h word=%d front=%b",waddr,burst_words,front_bank);$finish;
   end
   writes=writes+1;burst_words=(burst_words+1)%128;
  end
  if(pub!=last_pub)begin
   last_pub<=pub;
   if(burst_words!=0)begin $display("FAIL restart partial publication");$finish;end
  end
  if(aflush!=last_flush)begin
   last_flush<=aflush;audio_count=0;flushes=flushes+1;
   adone<=astart;completion_delay<=0;
  end
  if(avalid)begin
   if(adata!==((audio_count<<16)|((~audio_count)&65535)))begin
    $display("FAIL restart PCM order word=%d data=%h",audio_count,adata);$finish;
   end
   audio_count=audio_count+1;
  end
  if(astart!=last_start)begin
   last_start<=astart;completion_delay<=20;
   if(state==15 || restart)begin $display("FAIL restart issued audio start while cancelling");$finish;end
  end
  if(completion_delay>0)begin
   completion_delay<=completion_delay-1;if(completion_delay==1)adone<=astart;
  end
  if(error!=0)begin $display("FAIL restart error=%h state=%d lba=%d",error,state,logical_lba);$finish;end
  if(state==15 && req)begin $display("FAIL restart requested during drain");$finish;end
 end
 task pulse_restart;
  begin @(negedge clk);restart=1;@(negedge clk);restart=0;wait(state==15);end
 endtask
 task await_reboot;
  begin
   wait(state==0);@(negedge clk);
   if(busy || done_delay!=0 || burst_words!=0 || dut.publish_pending)begin
    $display("FAIL restart reboot with unfinished transaction");$finish;
   end
  end
 endtask
 initial begin
  #31 reset_n=1;
  wait(state==1);pulse_restart;await_reboot;
  if(accepted!=0)begin $display("FAIL restart REQUEST accepted new work");$finish;end
  allow_accept=1;
  wait(state==2 && active_lba==0 && index==10);pulse_restart;await_reboot;
  wait(state==3 && active_lba==0);pulse_restart;await_reboot;
  wait(state==2 && active_lba==1 && index==37);pulse_restart;await_reboot;
  if(writes!=128)begin $display("FAIL restart frame drain writes=%d",writes);$finish;end
                                                                      
                                                                        
  wait(state==1 && dut.mode==1);
  @(negedge clk);
  dut.logical_lba=8000;dut.frame_sector=7999;dut.frame_word=1023872;
  dut.frame_crc=VIDEO_PREFIX_CRC;
  wait(state==6);pulse_restart;
  repeat(20)@(negedge clk);
  if(state!=15 || pbank!=0 || req)begin
   $display("FAIL restart did not wait for delayed commit state=%d bank=%b",state,pbank);$finish;
  end
  front_bank=pbank;front_valid=1;commit=pub;
  await_reboot;
  if(pbank!=1)begin $display("FAIL restart did not release former front bank");$finish;end
  wait(state==2 && active_lba==1 && index==7);pulse_restart;await_reboot;
  selection=2;
  pulse_restart;await_reboot;
  wait(avalid && audio_count==31);pulse_restart;await_reboot;
  wait(state==12);
  if(audio_count!=300 || samples!=300 || flushes!=8)begin
   $display("FAIL restart completion count=%d samples=%d flushes=%d",audio_count,samples,flushes);$finish;
  end
  $display("PASS sequencer_restart: REQUEST/RECEIVE/WAIT_SD/frame/audio cancellation, complete bursts, delayed commit, front-bank protection, clean replay");$finish;
 end
 initial begin #1000000;$display("FAIL restart timeout state=%d busy=%b lba=%d",state,busy,logical_lba);$finish;end
endmodule

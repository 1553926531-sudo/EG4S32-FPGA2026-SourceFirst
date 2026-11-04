`timescale 1ns/1ps
`ifdef DISPATCH_V2_TEST
`define V2_CORE dut.indexed
module tb_dispatch_v2;
`else
`define V2_CORE dut
module tb_sequencer_v2;
`endif
 `include "seq_v2_constants.vh"
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,pause=0,restart=0,external_fault=0;
 reg [1:0] media_select=0,scale_mode=0;
 reg [9:0] media_index=0;
 wire rd_req,rd_ready,wr_valid,publish_toggle,publish_bank,audio_start_toggle,audio_flush_toggle,audio_valid;
 wire [31:0] rd_lba,wr_data,audio_total_samples,audio_data,logical_lba,frame_number;
 wire [20:0] wr_address;wire [19:0] frame_word;wire [5:0] state;wire [7:0] error_code;
 wire [9:0] video_count,image_count,actual_index;wire [1:0] actual_media;
 reg rd_accept=0,rd_valid=0,rd_done=0,rd_error=0,wr_ready=0,commit_toggle=0,audio_done_toggle=0;
 reg [31:0] rd_data=0;
 wire audio_ready=q_count<4096;
 wire [12:0] audio_write_level=q_count;
`ifdef DISPATCH_V2_TEST
 media_dispatch #(.CYCLES_PER_MS(30),.DEST_WIDTH(128),.DEST_HEIGHT(8)) dut(
`else
 media_sequencer_v2 #(.CYCLES_PER_MS(30),.DEST_WIDTH(128),.DEST_HEIGHT(8)) dut(
`endif
 .clk50(clk),.reset_n(reset_n),.system_ready(1'b1),.external_fault(external_fault),
 .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),.rd_valid(rd_valid),
 .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.card_fatal(1'b0),
 .wr_address(wr_address),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
 .publish_toggle(publish_toggle),.publish_bank(publish_bank),.commit_toggle(commit_toggle),
 .audio_start_toggle(audio_start_toggle),.audio_flush_toggle(audio_flush_toggle),.audio_total_samples(audio_total_samples),
 .audio_done_toggle(audio_done_toggle),.audio_write_level(audio_write_level),
 .audio_data(audio_data),.audio_valid(audio_valid),.audio_ready(audio_ready),.state(state),.error_code(error_code),
 .logical_lba(logical_lba),.frame_number(frame_number),.frame_word(frame_word),
 .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),.scale_mode(scale_mode),
 .video_count(video_count),.image_count(image_count),.actual_media(actual_media),.actual_index(actual_index));
 reg [31:0] rom[0:TOTAL_WORDS-1];reg [31:0] golden[0:20479];
 reg [31:0] frame[0:2047],queue[0:4095];
 integer cycle=0,sd_state=0,sd_word=0,sd_delay=0,sd_lba=0,sd_reads=0;
 integer q_count=0,q_read=0,q_write=0,audio_position=0,audio_loops=0,audio_ticks=0;
 integer commit_delay=0,publishes=0,commits=0,words0=0,words1=0;
 integer mode_test=0,expected_image=0,i,corrupt=0,old_commits,old_reads,old_loops;
 reg seen_publish=0,seen_start=0,seen_flush=0,playing=0,have_front=0,front_bank=1,pending_bank=0;
 reg inhibit_commit=0;reg [31:0] stalled_data;reg [20:0] stalled_address;reg stalled=0;
 task bad;input [255:0] message;begin $display("FAIL TFM2 %0s state=%0d err=%h cycle=%0d",message,state,error_code,cycle);$finish;end endtask
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!reset_n)begin
   sd_state=0;sd_word=0;rd_accept<=0;rd_valid<=0;rd_done<=0;rd_error<=0;
   q_count=0;q_read=0;q_write=0;seen_flush=0;seen_start=0;playing=0;audio_position=0;audio_done_toggle<=0;
   commit_toggle<=0;seen_publish=0;have_front=0;commit_delay=0;
   publishes=0;commits=0;words0=0;words1=0;audio_loops=0;stalled=0;
  end else begin
   if(stalled && !restart && state!=15 && state!=31 && (wr_data!==stalled_data || wr_address!==stalled_address || !wr_valid))bad("output changed under backpressure");
   stalled=wr_valid && !wr_ready;stalled_data=wr_data;stalled_address=wr_address;
   if(wr_valid && wr_ready)begin
    if(have_front && wr_address[20]==front_bank)bad("write to visible front bank");
    if(wr_address[19:0]==0)begin if(wr_address[20])words1=0;else words0=0;end
    if(wr_address[19:0]!==((wr_address[20])?words1:words0))bad("nonsequential framebuffer burst");
    if(wr_address[19:0]>=1024)bad("frame address overflow");
    frame[wr_address[20]*1024+wr_address[19:0]]=wr_data;
    if(wr_address[20])words1=words1+1;else words0=words0+1;
   end
   if(publish_toggle!=seen_publish)begin
    if(commit_delay!=0)bad("overlapping publish");
    seen_publish=publish_toggle;pending_bank=publish_bank;publishes=publishes+1;commit_delay=97;
    if((publish_bank?words1:words0)!=1024)bad("published incomplete image");
    expected_image=(media_select==0)?`V2_CORE.work_index:2+`V2_CORE.work_index;
    for(i=0;i<1024;i=i+1)if(frame[publish_bank*1024+i]!==golden[scale_mode*5120+expected_image*1024+i])begin
     $display("pixel=%0d media=%0d image=%0d scale=%0d got=%h want=%h",i,media_select,expected_image,scale_mode,
        frame[publish_bank*1024+i],golden[scale_mode*5120+expected_image*1024+i]);bad("scaled pixel mismatch");end
   end
   if(commit_delay!=0 && !inhibit_commit)begin
    commit_delay=commit_delay-1;
    if(commit_delay==0)begin commit_toggle<=seen_publish;front_bank=pending_bank;have_front=1;commits=commits+1;end
   end
   if(audio_flush_toggle!=seen_flush)begin
    seen_flush=audio_flush_toggle;q_count=0;q_read=0;q_write=0;playing=0;audio_position=0;seen_start=audio_start_toggle;audio_done_toggle<=audio_start_toggle;
   end else begin
    if(audio_valid && audio_ready)begin queue[q_write]=audio_data;q_write=(q_write+1)%4096;q_count=q_count+1;end
    if(audio_start_toggle!=seen_start)begin
     if(!have_front)bad("audio started before first frame commit");
     seen_start=audio_start_toggle;playing=1;audio_position=0;
     if(audio_total_samples!=5000)bad("audio length mismatch");
    end
    audio_ticks=audio_ticks+1;
    if(playing && !pause && audio_ticks%64==0)begin
     if(q_count==0)bad("concurrent audio underrun");
     if(queue[q_read]!==((audio_position<<16)|((~audio_position)&65535)))begin
      $display("audio got=%h position=%0d q=%0d loop=%0d start=%b done=%b pushed=%0d remaining=%0d corrupt=%0d",
       queue[q_read],audio_position,q_count,audio_loops,audio_start_toggle,audio_done_toggle,`V2_CORE.audio_pushed,`V2_CORE.audio_remaining,corrupt);
      bad("audio sample ordering");end
     q_read=(q_read+1)%4096;q_count=q_count-1;audio_position=audio_position+1;
     if(audio_position==5000)begin playing=0;audio_done_toggle<=seen_start;audio_loops=audio_loops+1;end
    end
   end
   rd_accept<=0;rd_done<=0;
   case(sd_state)
    0:if(rd_req)begin sd_lba=rd_lba;sd_word=0;sd_state=1;rd_accept<=1;sd_reads=sd_reads+1;end
    1:begin rd_valid<=0;sd_state=2;end
    2:begin
     if(rd_valid && rd_ready)begin
      rd_valid<=0;sd_word=sd_word+1;
      if(sd_word==128)begin sd_state=3;sd_delay=5;end
     end else if(!rd_valid && cycle%5!=0)begin
      if(sd_lba*128+sd_word>=TOTAL_WORDS)bad("SD LBA outside package");
      rd_data<=rom[sd_lba*128+sd_word];
      if((corrupt==1 && sd_lba==0 && sd_word==0) ||
         (corrupt==2 && sd_lba==1 && sd_word==0) ||
         (corrupt==3 && sd_lba==6 && sd_word==0) ||
         (corrupt==4 && sd_lba==AUDIO_LBA && sd_word==0))rd_data<=rom[sd_lba*128+sd_word]^1;
      rd_valid<=1;
     end
    end
    3:if(sd_delay==0)begin rd_done<=1;sd_state=4;end else sd_delay=sd_delay-1;
    4:sd_state=0;
   endcase
  end
 end
 always @(negedge clk)wr_ready=(cycle%11!=0 && cycle%7!=0);
 task cold_start;input [1:0] category;input [1:0] zoom;begin
  @(negedge clk);reset_n=0;pause=0;restart=0;media_select=category;media_index=0;scale_mode=zoom;inhibit_commit=0;
  repeat(5)@(negedge clk);reset_n=1;
 end endtask
 task restart_now;begin @(negedge clk);restart=1;@(negedge clk);restart=0;end endtask
 initial begin
  $readmemh("verification/seq_v2_words.hex",rom);$readmemh("verification/seq_v2_expected.hex",golden);
  for(mode_test=0;mode_test<4;mode_test=mode_test+1)begin
   $display("TFM2 test scale=%0d",mode_test);
   cold_start(0,mode_test);wait(commits>=3);@(negedge clk);pause=1;old_commits=commits;
   repeat(35000)@(negedge clk);if(commits!=old_commits)bad("pause advanced carousel");pause=0;
   wait(commits>=4);if(video_count!=2 || image_count!=3 || actual_media!=0)bad("media counts/category");
   media_select=1;media_index=1;restart_now;wait(actual_media==1 && actual_index==1);
   old_commits=commits;wait(commits>=old_commits+3);
  end
                                                                         
                                                 
  $display("TFM2 sustained audio");cold_start(1,2);wait(audio_loops>=2);
                                                                       
  $display("TFM2 partial restart");wait(wr_valid && wr_address[6:0]==57);media_select=2;restart_now;
  wait(actual_media==2);old_commits=commits;repeat(70000)@(negedge clk);
  if(commits!=old_commits)bad("audio background unexpectedly rotated");
                                                                        
  $display("TFM2 pending restart");media_select=1;restart_now;inhibit_commit=1;wait(commit_delay!=0);old_reads=sd_reads;
  media_select=0;restart_now;repeat(300)@(negedge clk);
  if(state!=15 || sd_reads!=old_reads)bad("restart ignored pending publish");
  inhibit_commit=0;wait(actual_media==0 && commits>=2);
  for(corrupt=1;corrupt<=4;corrupt=corrupt+1)begin
   cold_start(0,0);wait(state==31);
   if(error_code!==((corrupt==4)?8'h06:(corrupt==3)?8'h05:8'h03))bad("wrong CRC rejection");
   if(publishes!=0)bad("corrupt media became visible");
  end
  $display("PASS TFM2: four scaling modes, carousel, concurrent PCM loops, pause, safe partial-burst/publish restart and CRC rejection");$finish;
 end
 initial begin #100000000;bad("timeout");end
endmodule
`undef V2_CORE

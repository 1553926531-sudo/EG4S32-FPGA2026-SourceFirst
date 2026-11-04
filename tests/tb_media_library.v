`timescale 1ns/1ps
module tb_media_library;
 parameter DEST_WIDTH=32,DEST_HEIGHT=32;
 localparam FRAME_PIXELS=DEST_WIDTH*DEST_HEIGHT,QUEUE_DEPTH=2048;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,pause=0,restart=0,seek_request=0;
 reg [1:0] media_select=0;
 reg [9:0] media_index=0;
 reg [15:0] seek_seconds=0;
 wire rd_req,rd_ready,wr_valid,publish_toggle,publish_bank,audio_start,audio_flush;
 wire audio_valid,library_ready,legacy_library,lyric_valid,lyric_toggle;
 wire [31:0] rd_lba,wr_data,audio_data,audio_total,position,duration;
 wire [20:0] wr_address;
 wire [5:0] state;
 wire [7:0] error;
 wire [9:0] videos,images,songs,actual_index;
 wire [1:0] actual_media;
 wire [639:0] lyric_text;
 reg rd_accept=0,rd_valid=0,rd_done=0,rd_error=0,wr_ready=0,commit=0,audio_done=0;
 reg [31:0] rd_data=0,audio_position=0;
 reg epoch=0;
 integer qcount=0;
 wire [12:0] audio_level=qcount;
 wire audio_ready=qcount<QUEUE_DEPTH;
 media_library #(.CYCLES_PER_MS(500),.DEST_WIDTH(DEST_WIDTH),.DEST_HEIGHT(DEST_HEIGHT)) dut(
  .clk50(clk),.reset_n(reset_n),.system_ready(1'b1),.external_fault(1'b0),
  .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.card_fatal(1'b0),
  .wr_address(wr_address),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
  .publish_toggle(publish_toggle),.publish_bank(publish_bank),.commit_toggle(commit),
  .audio_start_toggle(audio_start),.audio_flush_toggle(audio_flush),.audio_total_samples(audio_total),
  .audio_done_toggle(audio_done),.audio_write_level(audio_level),.audio_data(audio_data),.audio_valid(audio_valid),.audio_ready(audio_ready),
  .state(state),.error_code(error),.logical_lba(),.frame_number(),.frame_word(),
  .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),.scale_mode(2'd2),
  .audio_position(audio_position),.audio_position_epoch(epoch),.seek_request(seek_request),.seek_seconds(seek_seconds),
  .playback_position(position),.playback_duration(duration),.video_count(videos),.image_count(images),.music_count(songs),
  .lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
  .actual_media(actual_media),.actual_index(actual_index),.library_ready(library_ready),.legacy_library(legacy_library),
  .name_clk(clk),.name_reset_n(reset_n),.name_id(12'd0),.name_char(5'd0),.name_code());
 reg [31:0] lbas[0:4095],disk[0:524287],frame[0:2*FRAME_PIXELS-1],queue[0:QUEUE_DEPTH-1];
 integer pcm_period=256,sd_gap=0,min_queue=QUEUE_DEPTH,max_queue=0,decoded_samples=0;
 integer nsectors,mode,cycle=0,phase=0,word=0,slot=0,delay=0,i,reads=0;
 integer writes=0,commits=0,commit_delay=0,base=0,readptr=0,writeptr=0,loops=0;
 integer starts=0,flushes=0,old_writes,old_reads,old_position,old_commits,old_loops;
 reg seen_publish=0,seen_start=0,seen_flush=0,playing=0,inject=0,fail_sector=0;
 reg [31:0] sample_base=0,expected_pixel=0;
 integer model_media=0,lyric_updates=0;
 reg seen_lyric=0;
 function [31:0] pcm;input [31:0] n;reg [15:0] left,right;begin
  left=(n*29)%32768;right=-((n*41)%32768);pcm={right,left};
 end endfunction
 task bad;input [511:0] why;begin
  $fatal(1,"FAIL media library %0s cycle=%0d config=%0d engine=%0d CPU=%0d PC=%h error=%h reads=%0d commits=%0d q=%0d",why,cycle,dut.config_state,state,dut.storage.cpu.state,dut.storage.cpu.pc,error,reads,commits,qcount);
 end endtask
 always @(negedge clk)wr_ready=(cycle%7!=0 && cycle%11!=0);
 always @(posedge clk)begin
  cycle=cycle+1;
  if(cycle%1000000==0)begin $display("progress cycle=%0d config=%0d engine=%0d CPU=%0d PC=%h err=%h starts=%0d pos=%0d remain=%0d",cycle,dut.config_state,state,dut.storage.cpu.state,dut.storage.cpu.pc,error,starts,audio_position,dut.engine.audio_remaining);$fflush();end
  if(cycle>240000000)bad("timeout");
  rd_accept<=0;rd_done<=0;
  if(reset_n)begin
   if(wr_valid && wr_ready)begin
    if(wr_address[19:0]>=FRAME_PIXELS)bad("frame address overflow");
    frame[wr_address[20]*FRAME_PIXELS+wr_address[19:0]]=wr_data;writes=writes+1;
   end
   if(publish_toggle!=seen_publish)begin
    seen_publish=publish_toggle;commit_delay=11;base=publish_bank*FRAME_PIXELS;
    expected_pixel=frame[base];
    for(i=0;i<FRAME_PIXELS;i=i+1)if(frame[base+i]!==expected_pixel)bad("incomplete uniform frame");
    if(commits==0 && expected_pixel!==32'h00101820)bad("startup frame");
    if(dut.selected_kind==2 && expected_pixel!==32'h00101820)bad("music showed picture");
   end
   if(commit_delay!=0)begin
    commit_delay=commit_delay-1;
    if(commit_delay==0)begin commit<=seen_publish;commits=commits+1;end
   end
   if(audio_flush!=seen_flush)begin
    seen_flush=audio_flush;qcount=0;readptr=0;writeptr=0;playing=0;audio_position=0;
    seen_start=audio_start;audio_done<=audio_start;flushes=flushes+1;
   end else begin
    if(audio_valid && audio_ready)begin
     if(dut.selected_kind==1)bad("picture emitted audio");
     queue[writeptr]=audio_data;writeptr=(writeptr+1)%QUEUE_DEPTH;qcount=qcount+1;
     if(qcount>max_queue)max_queue=qcount;
     if(qcount>QUEUE_DEPTH)bad("audio queue overflow");
    end
    if(audio_start!=seen_start)begin
     if(commits<2)bad("sound before selected frame");
     seen_start=audio_start;playing=1;audio_position=0;epoch=audio_start;
     sample_base=dut.engine.play_base;model_media=dut.selected_kind;starts=starts+1;
    end
    if(playing && !pause && cycle%pcm_period==0)begin
     if(qcount==0)bad("PCM underrun");
     if(qcount<min_queue)min_queue=qcount;
     if(queue[readptr]!==pcm(sample_base+audio_position))begin
      $display("PCM got=%h want=%h at=%0d",queue[readptr],pcm(sample_base+audio_position),sample_base+audio_position);bad("PCM sequence");
     end
     readptr=(readptr+1)%QUEUE_DEPTH;qcount=qcount-1;audio_position=audio_position+1;
     decoded_samples=decoded_samples+1;
     if(audio_position==audio_total)begin playing=0;audio_done<=seen_start;loops=loops+1;end
    end
   end
   if(lyric_toggle!=seen_lyric)begin
    seen_lyric=lyric_toggle;
    if(lyric_valid)begin
     lyric_updates=lyric_updates+1;
     if(dut.selected_kind!=2)bad("lyric on other media");
     if(lyric_text[7:0]!=8'd70 && lyric_text[7:0]!=8'd83 && lyric_text[7:0]!=8'd84)bad("lyric contents");
    end
   end
   case(phase)
    0:if(rd_req)begin
     slot=-1;for(i=0;i<nsectors;i=i+1)if(lbas[i]==rd_lba)slot=i;
     if(slot<0)begin $display("unmapped LBA=%0d",rd_lba);bad("unmapped disk sector");end
     word=0;rd_accept<=1;delay=2;phase=1;reads=reads+1;
     fail_sector=inject;inject=0;
    end
    1:if(delay!=0)delay=delay-1;else begin rd_data<=disk[slot*128+word];rd_valid<=1;phase=2;end
    2:if(rd_valid && rd_ready)begin
     rd_valid<=0;
     if(word==127)begin phase=3;delay=3;end
     else begin word=word+1;phase=1;delay=sd_gap+((cycle%7==0)?1:0);end
    end
    3:if(delay!=0)delay=delay-1;else begin rd_done<=1;rd_error<=fail_sector;phase=4;end
    4:begin rd_error<=0;phase=0;end
   endcase
  end
 end
 task open;input [1:0] kind;input [9:0] index;begin
  @(negedge clk);media_select=kind;media_index=index;restart=1;
  @(negedge clk);restart=0;
 end endtask
 task wait_display;input [31:0] color;begin
  while(!(dut.config_state==7 && dut.display_ready && frame[base]===color))begin
   @(negedge clk);if(dut.config_state==8)bad("display failed");
  end
 end endtask
 task seek;input [15:0] seconds;begin
  @(negedge clk);seek_seconds=seconds;seek_request=1;
  @(negedge clk);seek_request=0;
 end endtask
 initial begin
  if(!$value$plusargs("sectors=%d",nsectors))bad("missing sectors");
  if(!$value$plusargs("mode=%d",mode))mode=0;
  if(!$value$plusargs("pcm_period=%d",pcm_period))pcm_period=256;
  if(!$value$plusargs("sd_gap=%d",sd_gap))sd_gap=0;
  if(pcm_period<1 || sd_gap<0)bad("invalid timing arguments");
  $readmemh("lbas.hex",lbas,0,nsectors-1);$readmemh("disk.hex",disk,0,nsectors*128-1);
  repeat(5)@(negedge clk);reset_n=1;
  wait(library_ready && commits==1);repeat(1000)@(negedge clk);
  if(audio_valid || starts!=0 || dut.config_state!=3)bad("automatic playback at boot");
  if(mode==2)begin
   if(videos!=0 || images!=0 || songs!=0)bad("empty library count");
   open(0,0);repeat(1000)@(negedge clk);
   if(dut.config_state!=3 || commits!=1 || starts!=0)bad("empty library opened media");
   $display("PASS media library empty card, startup blank and no automatic playback");
  end else begin
  if(videos!=(mode==1?1:2) || images!=(mode==1?2:3) || songs!=1 || legacy_library!=(mode==1))bad("directory counts");
  $display("library images and silence");
  open(1,0);wait_display(32'h00112233);
  @(negedge clk);pause=1;old_commits=commits;old_writes=writes;old_reads=reads;
  repeat(12000)@(negedge clk);
  if(commits!=old_commits || starts!=0 || duration!=0)bad("image pause/silence");
  pause=0;open(1,1);wait_display(32'h0044aa55);
  if(mode==0)begin
   open(1,2);wait(error!=0);repeat(30)@(negedge clk);
   open(1,0);wait_display(32'h00112233);
  end
  $display("library WAV, lyrics, pause and seek");
  open(2,0);wait(starts==1);wait(audio_position>1000);
  @(negedge clk);pause=1;old_position=audio_position;
  repeat(10000)@(negedge clk);
  if(audio_position!=old_position)bad("audio pause");
  seek(1);wait(starts==2);repeat(2000)@(negedge clk);
  if(position!=48000 || audio_position!=0 || sample_base!=48000)bad("paused seek position");
  pause=0;wait(loops>=1);wait(starts>=3 && audio_position>100);
  if(mode==0 && lyric_updates<3)bad("lyrics missing across seek/loop");
  $display("library switch during read and video");
  wait(rd_valid && rd_ready);open(1,0);wait_display(32'h00112233);
  if(qcount!=0 || playing)bad("audio not flushed for picture");
  old_commits=commits;open(0,0);wait(commits>=old_commits+5);
  if(error!=0 || loops<2)bad("video full loop");
  if(mode==0)begin
   $display("library SD error and recovery");
   open(1,0);wait_display(32'h00112233);
   @(negedge clk);inject=1;open(1,1);wait(error!=0);
   repeat(50)@(negedge clk);open(1,0);wait_display(32'h00112233);
   $display("library active WAV read error and recovery");
   old_loops=starts;open(2,0);wait(starts>old_loops && audio_position>1000);
   @(negedge clk);inject=1;wait(error!=0);repeat(80)@(negedge clk);
   open(1,0);wait_display(32'h00112233);
   $display("library invalid TFV CRC and recovery");
   open(0,1);wait(error!=0);repeat(80)@(negedge clk);
   open(1,0);wait_display(32'h00112233);
   $display("library rapid selection during prepare");
   open(2,0);wait(dut.config_state==6);
   open(1,1);open(2,0);open(1,0);wait_display(32'h00112233);
   repeat(2000)@(negedge clk);
   if(actual_media!=1 || actual_index!=0 || error!=0 || playing || qcount!=0)bad("latest selection did not win");
  end
  $display("PASS media library mode=%0d reads=%0d commits=%0d PCM starts=%0d loops=%0d lyric=%0d queue=%0d min=%0d max=%0d samples=%0d period=%0d sd_gap=%0d frame=%0dx%0d",mode,reads,commits,starts,loops,lyric_updates,QUEUE_DEPTH,min_queue,max_queue,decoded_samples,pcm_period,sd_gap,DEST_WIDTH,DEST_HEIGHT);
  end
  $finish;
 end
endmodule

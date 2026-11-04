`timescale 1ns/1ps
`ifdef LONG_INDEX_TEST
module tb_v3_long;
 `include "v3_long.vh"
 localparam AUDIO_TICK=8;
`else
module tb_v3_media;
 `include "v3_fixture.vh"
 localparam AUDIO_TICK=32;
`endif
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,pause=0,restart=0;
 reg [1:0] media_select=0;
 reg [9:0] media_index=0;
 wire rd_req,rd_ready,wr_valid,publish_toggle,publish_bank,audio_start_toggle,audio_flush_toggle,audio_valid;
 wire [31:0] rd_lba,wr_data,audio_total_samples,audio_data;
 wire [20:0] wr_address;wire [5:0] state;wire [7:0] error_code;
 wire [9:0] video_count,image_count,music_count,actual_index;wire [1:0] actual_media;
 wire [639:0] lyric_text;wire lyric_valid,lyric_toggle;
 reg rd_accept=0,rd_valid=0,rd_done=0,wr_ready=0,commit_toggle=0,audio_done_toggle=0;
 reg [31:0] rd_data=0,audio_position=0;
 reg audio_position_epoch=0;
 wire audio_ready=q_count<4096;
 wire [12:0] audio_write_level=q_count;
 media_dispatch #(.CYCLES_PER_MS(30),.DEST_WIDTH(128),.DEST_HEIGHT(8),.ENABLE_LEGACY(0)) dut(
 .clk50(clk),.reset_n(reset_n),.system_ready(1'b1),.external_fault(1'b0),
 .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),.rd_valid(rd_valid),
 .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(1'b0),.card_fatal(1'b0),
 .wr_address(wr_address),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
 .publish_toggle(publish_toggle),.publish_bank(publish_bank),.commit_toggle(commit_toggle),
 .audio_start_toggle(audio_start_toggle),.audio_flush_toggle(audio_flush_toggle),.audio_total_samples(audio_total_samples),
 .audio_done_toggle(audio_done_toggle),.audio_write_level(audio_write_level),
 .audio_data(audio_data),.audio_valid(audio_valid),.audio_ready(audio_ready),.state(state),.error_code(error_code),
 .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),.scale_mode(2'd2),
 .audio_position(audio_position),.audio_position_epoch(audio_position_epoch),
 .video_count(video_count),.image_count(image_count),.music_count(music_count),
 .lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
 .actual_media(actual_media),.actual_index(actual_index));
 reg [31:0] rom[0:PREFIX_WORDS-1],sector_data[0:127],frame[0:2047],queue[0:4095];
 integer cycle=0,sd_state=0,sd_word=0,sd_delay=0,sd_lba=0,sd_reads=0;
 integer q_count=0,q_read=0,q_write=0,audio_loops=0,model_track=0,start_delay=0;
 integer commit_delay=0,publishes=0,commits=0,words0=0,words1=0,video_next=0;
 integer i,j,corrupt=0,old_commits,old_position,old_lyrics,cue_updates=0;
 integer sample_base,sector_track,track_length,expected_cue,expected_time,lyric_char;
 reg seen_publish=0,seen_start=0,seen_flush=0,seen_lyric=0,playing=0,have_front=0,front_bank=1,pending_bank=0;
 reg [31:0] crc,value,expected_pixel,stalled_data;reg [20:0] stalled_address;reg stalled=0;
 reg [639:0] expected_text;
 function [7:0] cue_character;input integer offset,track_number,cue_number;begin
  case(offset)
   0:cue_character="T";1:cue_character="R";2:cue_character="A";3:cue_character="C";4:cue_character="K";
   6:cue_character=48+track_number;8:cue_character="C";9:cue_character="U";10:cue_character="E";
   12:cue_character=48+cue_number;default:cue_character=32;
  endcase
 end endfunction
 function [31:0] pcm;input integer track,position;begin
  pcm=((position<<16)|((~position)&65535))^(track*32'h10203040);
 end endfunction
 function [31:0] crc_word;input [31:0] old,data;reg [31:0] c;integer b,n;begin
  c=old;for(b=0;b<4;b=b+1)begin c=c^((data>>(b*8))&255);
   for(n=0;n<8;n=n+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;end
  crc_word=c;
 end endfunction
 task bad;input [511:0] message;begin
  $display("FAIL V3 %0s state=%0d err=%h cycle=%0d position=%0d track=%0d",message,state,error_code,cycle,audio_position,model_track);$finish;
 end endtask
 task prepare_sector;begin
  if(sd_lba<0 || sd_lba>=FILE_SECTORS)bad("request outside package");
  if(sd_lba<MOVIE_LBA)for(j=0;j<128;j=j+1)sector_data[j]=rom[sd_lba*128+j];
  else begin
   sector_track=(sd_lba<SONG1_LBA)?0:(sd_lba<SONG2_LBA)?1:2;
   sample_base=(sd_lba-((sector_track==0)?MOVIE_LBA:(sector_track==1)?SONG1_LBA:SONG2_LBA))*127;
   track_length=(sector_track==0)?MOVIE_SAMPLES:(sector_track==1)?6000:8000;
   crc=32'hffffffff;
   for(j=0;j<127;j=j+1)begin
    sector_data[j]=(sample_base+j<track_length)?pcm(sector_track,sample_base+j):0;
    crc=crc_word(crc,sector_data[j]);
   end
   sector_data[127]=~crc;
  end
  if(corrupt==1 && sd_lba==0)sector_data[0]=sector_data[0]^1;
  if(corrupt==2 && sd_lba==SONG1_LBA)sector_data[0]=sector_data[0]^1;
  if(corrupt==3 && sd_lba==AUDIO_INDEX+1)sector_data[2]=FILE_SECTORS;
  if(corrupt==4 && sd_lba==CUE_LBA)sector_data[1]=6000;
  if(corrupt==5 && sd_lba==CUE_LBA)sector_data[4]=32'h414141ff;
  if(corrupt>=3)begin crc=32'hffffffff;for(j=0;j<127;j=j+1)crc=crc_word(crc,sector_data[j]);sector_data[127]=~crc;end
 end endtask
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!reset_n)begin
   sd_state=0;rd_accept<=0;rd_valid<=0;rd_done<=0;
   q_count=0;q_read=0;q_write=0;seen_flush=0;seen_start=0;seen_lyric=0;playing=0;audio_position=0;
   audio_done_toggle<=0;audio_position_epoch=0;start_delay=0;
   commit_toggle<=0;seen_publish=0;have_front=0;commit_delay=0;video_next=0;
   publishes=0;commits=0;words0=0;words1=0;audio_loops=0;cue_updates=0;stalled=0;
  end else begin
   if(state==31 && corrupt==0)bad("unexpected media failure");
   if(stalled && !restart && state!=15 && state!=31 && (wr_data!==stalled_data || wr_address!==stalled_address || !wr_valid))bad("unstable stalled output");
   stalled=wr_valid && !wr_ready;stalled_data=wr_data;stalled_address=wr_address;
   if(wr_valid && wr_ready)begin
    if(have_front && wr_address[20]==front_bank)bad("write to visible bank");
    if(wr_address[19:0]==0)begin if(wr_address[20])words1=0;else words0=0;end
    if(wr_address[19:0]!==((wr_address[20])?words1:words0))bad("nonsequential framebuffer");
    if(wr_address[19:0]>=1024)bad("frame overflow");
    frame[wr_address[20]*1024+wr_address[19:0]]=wr_data;
    if(wr_address[20])words1=words1+1;else words0=words0+1;
   end
   if(publish_toggle!=seen_publish)begin
    if(commit_delay!=0 || (publish_bank?words1:words0)!=1024)bad("incomplete or overlapping publish");
    seen_publish=publish_toggle;pending_bank=publish_bank;publishes=publishes+1;commit_delay=97;
    if(media_select==0)begin
     if(dut.indexed.work_index!=video_next)bad("32-bit video index ordering");
     if(video_next!=0 && (audio_position<video_next*3840 || audio_position_epoch!=audio_start_toggle))bad("video before its audio timestamp");
     expected_pixel=((video_next+1)*769)&24'hffffff;video_next=(video_next+1)%VIDEO_FRAMES;
    end else if(media_select==2)expected_pixel=(media_index==1)?32'h0033bb44:32'h00aa1122;
    else expected_pixel=(dut.indexed.work_index==1)?32'h0033bb44:32'h00aa1122;
    for(i=0;i<1024;i=i+1)if(frame[publish_bank*1024+i]!==expected_pixel)bad("scaled pixels/background differ");
   end
   if(commit_delay!=0)begin
    commit_delay=commit_delay-1;
    if(commit_delay==0)begin
     commit_toggle<=seen_publish;front_bank=pending_bank;have_front=1;commits=commits+1;
     if(VIDEO_FRAMES>100 && commits%128==0)begin
      $display("V3 long video committed %0d/1100",commits);$fflush;
     end
    end
   end
   if(audio_flush_toggle!=seen_flush)begin
    seen_flush=audio_flush_toggle;q_count=0;q_read=0;q_write=0;playing=0;audio_position=0;
    seen_start=audio_start_toggle;audio_done_toggle<=audio_start_toggle;start_delay=0;
   end else begin
    if(audio_valid && audio_ready)begin queue[q_write]=audio_data;q_write=(q_write+1)%4096;q_count=q_count+1;end
    if(audio_start_toggle!=seen_start)begin
     if(!have_front)bad("audio before first visible frame");
     seen_start=audio_start_toggle;start_delay=40;playing=0;
     model_track=(media_select==0)?0:(media_select==2 && media_index==1)?2:1;
     if(audio_total_samples!==((model_track==0)?MOVIE_SAMPLES:(model_track==1)?6000:8000))bad("selected PCM length");
    end
    if(start_delay!=0)begin
     start_delay=start_delay-1;
     if(start_delay==0)begin playing=1;audio_position=0;audio_position_epoch=seen_start;end
    end
    if(playing && !pause && cycle%AUDIO_TICK==0)begin
     if(q_count==0)bad("audio underrun");
     if(queue[q_read]!==pcm(model_track,audio_position))bad("PCM samples crossed tracks/loop or reordered");
     q_read=(q_read+1)%4096;q_count=q_count-1;audio_position=audio_position+1;
     if(audio_position==audio_total_samples)begin playing=0;audio_done_toggle<=seen_start;audio_loops=audio_loops+1;end
    end
   end
   if(lyric_toggle!=seen_lyric)begin
    seen_lyric=lyric_toggle;
    if(lyric_valid)begin
     if(start_delay!=0 || audio_position_epoch!=audio_start_toggle)bad("stale playhead published next-loop lyric");
     expected_cue=lyric_text[12*8+:8]-8'd48;
     if(expected_cue<0 || expected_cue>2 || lyric_text[6*8+:8]!=8'd48+model_track)bad("wrong song lyric");
     for(lyric_char=0;lyric_char<80;lyric_char=lyric_char+1)
      if(lyric_text[lyric_char*8+:8]!==cue_character(lyric_char,model_track,expected_cue))bad("partial or reordered lyric publication");
     expected_time=(expected_cue==0)?0:(model_track==1)?((expected_cue==1)?1000:4500):((expected_cue==1)?2000:7000);
     if(audio_position<expected_time || audio_position>expected_time+32)bad("lyric timing outside 32 samples");
     cue_updates=cue_updates+1;
    end
   end
   rd_accept<=0;rd_done<=0;
   case(sd_state)
    0:if(rd_req)begin sd_lba=rd_lba;prepare_sector;sd_word=0;sd_state=1;rd_accept<=1;sd_reads=sd_reads+1;end
    1:begin rd_valid<=0;sd_state=2;end
    2:begin
     if(rd_valid && rd_ready)begin rd_valid<=0;sd_word=sd_word+1;if(sd_word==128)begin sd_state=3;sd_delay=5;end end
     else if(!rd_valid && cycle%5!=0)begin rd_data<=sector_data[sd_word];rd_valid<=1;end
    end
    3:if(sd_delay==0)begin rd_done<=1;sd_state=4;end else sd_delay=sd_delay-1;
    4:sd_state=0;
   endcase
  end
 end
 always @(negedge clk)wr_ready=(cycle%11!=0 && cycle%7!=0);
 task cold_start;input [1:0] category;input [9:0] index;begin
  @(negedge clk);reset_n=0;pause=0;restart=0;media_select=category;media_index=index;
  repeat(5)@(negedge clk);reset_n=1;
 end endtask
 task restart_now;begin @(negedge clk);restart=1;@(negedge clk);restart=0;end endtask
 initial begin
`ifdef LONG_INDEX_TEST
  $readmemh("verification/v3_long.hex",rom);
  cold_start(0,0);wait(commits==VIDEO_FRAMES);@(negedge clk);
  if(video_count!=1 || (dut.indexed.work_index!=VIDEO_FRAMES-1 && dut.indexed.work_index!=0))bad("long video count/final frame");
  $display("PASS V3 long: 1100 consecutive decoded/scaled frames, index crosses 600 and 1023, sample-clock scheduling, ordered PCM and no underrun");$finish;
`else
  $readmemh("verification/v3_fixture.hex",rom);
  $display("V3 songs, lyrics, pause and loop");
  cold_start(2,0);wait(audio_position>=1500);@(negedge clk);pause=1;
  old_position=audio_position;old_lyrics=cue_updates;old_commits=commits;
  repeat(10000)@(negedge clk);
  if(audio_position!=old_position || cue_updates!=old_lyrics || commits!=old_commits)bad("pause advanced playback");
  pause=0;wait(audio_loops>=2);
  if(cue_updates!=6 || music_count!=2 || video_count!=1 || image_count!=2)bad("song loops/cues/counts");
  wait(rd_valid && rd_ready);media_index=1;restart_now;
  wait(actual_media==2 && actual_index==1);wait(audio_position>7200 && model_track==2);
  if(cue_updates<9)bad("second song cues missing");
  media_index=99;restart_now;wait(actual_index==0 && model_track==1 && audio_position>100);
  if(music_count!=2)bad("invalid selection fallback");
  $display("V3 movie sample synchronization and complete loop");
  cold_start(0,0);wait(commits>=5);
  if(audio_loops<1)bad("movie loop did not finish complete PCM");
  @(negedge clk);pause=1;old_position=audio_position;old_commits=commits;
  repeat(30000)@(negedge clk);if(commits!=old_commits || audio_position!=old_position)bad("movie pause");
  pause=0;wait(commits>=7);
  $display("V3 malformed metadata/PCM rejection");
  for(corrupt=1;corrupt<=5;corrupt=corrupt+1)begin
   cold_start(2,0);wait(state==31);@(negedge clk);
   if(error_code!==((corrupt==2)?8'h06:(corrupt==3)?8'h0a:(corrupt==4)?8'h0b:8'h03))bad("wrong corruption result");
  end
  $display("PASS V3: dispatch, independent songs/backgrounds, timed lyrics, delayed-start epochs, pause, full loops, safe track change, CRC and forged metadata rejection");$finish;
`endif
 end
 initial begin #2000000000;bad("timeout");end
endmodule

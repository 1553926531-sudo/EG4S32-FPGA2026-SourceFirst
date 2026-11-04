`timescale 1ns/1ps
module tb_v3_seek;
 `include "v3_seek.vh"
 localparam AUDIO_TICK=16;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,pause=0,restart=0;
 reg seek_request=0;reg [15:0] seek_seconds=0;
 integer expected_base=0,model_base=0;wire [31:0] playback_position,playback_duration;
 reg [1:0] media_select=0;
 reg [9:0] media_index=0;
 wire rd_req,rd_ready,wr_valid,publish_toggle,publish_bank,audio_start_toggle,audio_flush_toggle,audio_valid;
 wire [31:0] rd_lba,wr_data,audio_total_samples,audio_data;
 wire [20:0] wr_address;wire [5:0] state;wire [7:0] error_code;
 wire [9:0] video_count,image_count,music_count,actual_index;wire [1:0] actual_media;
 wire [639:0] lyric_text;wire lyric_valid,lyric_toggle;
 reg rd_accept=0,rd_valid=0,rd_done=0,wr_ready=0,commit_toggle=0,audio_done_toggle=0;
 reg [31:0] rd_data=0,audio_position=0;wire [31:0] frame_number;
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
 .audio_data(audio_data),.audio_valid(audio_valid),.audio_ready(audio_ready),.state(state),.error_code(error_code),.frame_number(frame_number),
 .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),.scale_mode(2'd2),
 .audio_position(audio_position),.audio_position_epoch(audio_position_epoch),
 .seek_request(seek_request),.seek_seconds(seek_seconds),.playback_position(playback_position),.playback_duration(playback_duration),
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
   track_length=(sector_track==0)?MOVIE_SAMPLES:(sector_track==1)?173211:130007;
   crc=32'hffffffff;
   for(j=0;j<127;j=j+1)begin
    sector_data[j]=(sample_base+j<track_length)?pcm(sector_track,sample_base+j):0;
    crc=crc_word(crc,sector_data[j]);
   end
   sector_data[127]=~crc;
  end
  if(corrupt==1 && sd_lba==0)sector_data[0]=sector_data[0]^1;
  if(corrupt==2 && sector_track==model_track && sd_lba>=MOVIE_LBA && sample_base<=expected_base && sample_base+127>expected_base)sector_data[0]=sector_data[0]^1;
  if(corrupt==3 && sd_lba==AUDIO_INDEX+1)sector_data[2]=FILE_SECTORS;
  if(corrupt==4 && sd_lba==CUE_LBA)sector_data[1]=173211;
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
     if(video_next!=expected_base/3840 && (audio_position+model_base<video_next*3840 || audio_position_epoch!=audio_start_toggle))bad("video before its audio timestamp");
     expected_pixel=((video_next+1)*769)&24'hffffff;video_next=(video_next+1)%VIDEO_FRAMES;
    end else if(media_select==2)expected_pixel=(media_index==1)?32'h0033bb44:32'h00aa1122;
    else expected_pixel=(dut.indexed.work_index==1)?32'h0033bb44:32'h00aa1122;
    for(i=0;i<1024;i=i+1)if(frame[publish_bank*1024+i]!==expected_pixel)bad("scaled pixels/background differ");
   end
   if(commit_delay!=0)begin
    commit_delay=commit_delay-1;
    if(commit_delay==0)begin
     commit_toggle<=seen_publish;front_bank=pending_bank;have_front=1;commits=commits+1;
     if(VIDEO_FRAMES>100 && commits%128==0)$display("V3 long video committed %0d/1100",commits);
    end
   end
   if(audio_flush_toggle!=seen_flush)begin
    seen_flush=audio_flush_toggle;q_count=0;q_read=0;q_write=0;playing=0;audio_position=0;
    seen_start=audio_start_toggle;audio_done_toggle<=audio_start_toggle;start_delay=0;
    model_base=expected_base;video_next=expected_base/3840;
    model_track=(media_select==0)?0:(media_select==2 && media_index==1)?2:1;
   end else begin
    if(audio_valid && audio_ready)begin queue[q_write]=audio_data;q_write=(q_write+1)%4096;q_count=q_count+1;end
    if(audio_start_toggle!=seen_start)begin
     if(!have_front)bad("audio before first visible frame");
     seen_start=audio_start_toggle;start_delay=40;playing=0;model_base=expected_base;
     model_track=(media_select==0)?0:(media_select==2 && media_index==1)?2:1;
     if(audio_total_samples!==(((model_track==0)?MOVIE_SAMPLES:(model_track==1)?173211:130007)-expected_base))bad("selected PCM length");
    end
    if(start_delay!=0)begin
     start_delay=start_delay-1;
     if(start_delay==0)begin playing=1;audio_position=0;audio_position_epoch=seen_start;end
    end
    if(playing && !pause && cycle%AUDIO_TICK==0)begin
     if(q_count==0)bad("audio underrun");
     if(queue[q_read]!==pcm(model_track,audio_position+model_base))bad("PCM samples crossed tracks/loop or reordered");
     q_read=(q_read+1)%4096;q_count=q_count-1;audio_position=audio_position+1;
     if(audio_position==audio_total_samples)begin playing=0;audio_done_toggle<=seen_start;audio_loops=audio_loops+1;expected_base=0;video_next=0;end
    end
   end
   if(lyric_toggle!=seen_lyric)begin
    seen_lyric=lyric_toggle;
    if(lyric_valid)begin
     expected_cue=lyric_text[12*8+:8]-8'd48;
     if(expected_cue<0 || expected_cue>2 || lyric_text[6*8+:8]!=8'd48+model_track)bad("wrong song lyric after seek");
     for(lyric_char=0;lyric_char<80;lyric_char=lyric_char+1)
      if(lyric_text[lyric_char*8+:8]!==cue_character(lyric_char,model_track,expected_cue))bad("partial or reordered lyric after seek");
     expected_time=(expected_cue==0)?0:(model_track==1)?((expected_cue==1)?48000:96000):((expected_cue==1)?24000:100000);
     if(expected_time>model_base+audio_position)bad("future lyric after seek");
     if(expected_cue<2 && model_base+audio_position>=((model_track==1)?((expected_cue==0)?48000:96000):((expected_cue==0)?24000:100000)))bad("stale lyric after seek");
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
 task seek_to;input [15:0] seconds;input integer base;begin
  $display("SEEK request seconds=%0d base=%0d state=%0d level=%0d",seconds,base,state,q_count);$fflush();
  @(negedge clk);expected_base=base;seek_seconds=seconds;seek_request=1;
  @(negedge clk);seek_request=0;
  wait(!playing);wait(playing);@(negedge clk);
  if(model_base!=base || dut.indexed.play_base!=base || playback_duration!=((media_select==0)?MOVIE_SAMPLES:(media_index==1)?130007:173211))bad("seek position/duration");
  $display("SEEK started seconds=%0d base=%0d cycle=%0d",seconds,model_base,cycle);$fflush();
 end endtask
 task check_lyric;input integer number;begin
  if(!lyric_valid || lyric_text[12*8+:8]!=8'd48+number)bad("seek did not restore current lyric");
 end endtask
 initial begin
  $readmemh("verification/v3_seek.hex",rom);
  cold_start(2,0);wait(audio_position>900);@(negedge clk);pause=1;
  seek_to(1,48000);check_lyric(1);repeat(500)@(negedge clk);
  if(audio_position!=0 || playback_position!=48000)bad("paused seek consumed samples");
  pause=0;wait(audio_position>300);pause=1;
  seek_to(2,96000);check_lyric(2);pause=0;wait(audio_position>300);pause=1;
  seek_to(0,0);check_lyric(0);pause=0;wait(audio_position>300);pause=1;
  seek_to(3,144000);check_lyric(2);
                                                                         
                                                                          
                                                                           
  @(negedge clk);expected_base=96000;seek_seconds=2;seek_request=1;
  @(negedge clk);seek_request=0;wait(rd_valid && rd_ready);
  @(negedge clk);seek_request=0;@(negedge clk);expected_base=48000;seek_seconds=1;seek_request=1;
  @(negedge clk);seek_request=0;wait(!playing);wait(playing);check_lyric(1);
  if(model_base!=48000 || dut.indexed.play_base!=48000)bad("last drain request lost");
  seek_to(65535,173210);check_lyric(2);
  if(audio_total_samples!=1 || q_count!=1)bad("end clamp did not retain exactly one validated sample");
  pause=0;wait(audio_loops>0);wait(playing && model_base==0 && audio_position>200);
  if(playback_position>500 || playback_duration!=173211)bad("loop retained seek base");
  $display("SEEK movie frame and PCM synchronization");
  @(negedge clk);expected_base=0;cold_start(0,0);wait(audio_position>500);pause=1;
  seek_to(1,48000);if(frame_number!=12 || playback_position!=48000)bad("movie frame floor");
  pause=0;wait(audio_position>4100);pause=1;
  seek_to(3,144000);if(frame_number!=37)bad("late movie frame");
  seek_to(0,0);if(frame_number!=0)bad("movie seek beginning");
                                                        
  @(negedge clk);media_select=2;media_index=1;expected_base=0;restart=1;seek_request=1;seek_seconds=2;
  @(negedge clk);restart=0;seek_request=0;wait(!playing);wait(playing);
  if(model_base!=0 || dut.indexed.play_base!=0 || actual_index!=1)bad("restart/seek priority");
                                                                      
  @(negedge clk);corrupt=2;expected_base=48000;seek_seconds=1;seek_request=1;
  @(negedge clk);seek_request=0;wait(state==31);
  if(error_code!=6 || q_count!=0 || playing)bad("seek CRC corruption emitted PCM");
  $display("PASS V3 seek: CRC-validated PCM prefix, offsets 0/1/2/3 seconds, backward/forward, pause preservation, cue restoration, superseding drain request, one-sample end/loop, movie frame+PCM alignment, file-restart priority, corrupt target-sector rejection");$finish;
 end
 initial begin #100000000;$display("SEEK watchdog playing=%b q=%0d sd=%0d mode=%0d cues=%0d/%0d pending=%b seek=%b display=%b descriptor=%b image=%b",playing,q_count,sd_state,dut.indexed.mode,dut.indexed.cue_index,dut.indexed.cue_count,dut.indexed.cue_pending,dut.indexed.cue_seeking,dut.indexed.have_display,dut.indexed.need_descriptor,dut.indexed.image_active);bad("timeout");end
endmodule

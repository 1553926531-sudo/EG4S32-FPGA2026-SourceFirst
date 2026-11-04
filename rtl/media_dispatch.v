`timescale 1ns/1ps
                                                                          
                                                                           
                                                                      
module media_dispatch #(parameter CYCLES_PER_MS=50000,DEST_WIDTH=1280,DEST_HEIGHT=800,ENABLE_LEGACY=1)(
 input wire clk50,input wire reset_n,input wire system_ready,input wire external_fault,
 output wire rd_req,output wire [31:0] rd_lba,input wire rd_accept,
 input wire [31:0] rd_data,input wire rd_valid,output wire rd_ready,
 input wire rd_done,input wire rd_error,input wire card_fatal,
 output wire [20:0] wr_address,output wire [31:0] wr_data,output wire wr_valid,input wire wr_ready,
 output wire publish_toggle,output wire publish_bank,input wire commit_toggle,
 output wire audio_start_toggle,output wire audio_flush_toggle,output wire [31:0] audio_total_samples,
 input wire audio_done_toggle,input wire [12:0] audio_write_level,
 output wire [31:0] audio_data,output wire audio_valid,input wire audio_ready,
 output wire [5:0] state,output wire [7:0] error_code,
 output wire [31:0] logical_lba,output wire [31:0] frame_number,output wire [19:0] frame_word,
 input wire pause,input wire restart,input wire [1:0] media_select,input wire [9:0] media_index,
 input wire [1:0] scale_mode,input wire [31:0] audio_position,input wire audio_position_epoch,
 input wire seek_request,input wire [15:0] seek_seconds,
 output wire [31:0] playback_position,output wire [31:0] playback_duration,
 output wire [9:0] video_count,output wire [9:0] image_count,
 output wire [9:0] music_count,output wire [639:0] lyric_text,
 output wire lyric_valid,output wire lyric_toggle,
 output wire [1:0] actual_media,output wire [9:0] actual_index);
 localparam BOOT=0,PROBE_REQUEST=1,PROBE_DATA=2,PROBE_DONE=3,RUN=4,FAILED=31;
 reg [5:0] probe_state;reg [7:0] probe_error;
 reg [6:0] word_index;reg [31:0] version;reg engine_v2,probe_inflight,probe_restart_pending;
 wire running=probe_state==RUN;
                                                                    
                                                                      
                                                                         
                                                              
 wire selected_engine=ENABLE_LEGACY?engine_v2:1'b1;
 wire map_valid;wire [31:0] probe_lba,unused_crc,unused_sectors;
 media_extent_map probe_map(.logical_lba(32'd0),.physical_lba(probe_lba),.valid(map_valid),
 .expected_header_crc(unused_crc),.file_sectors(unused_sectors));
 wire [1:0] engine_req,engine_ready,engine_wr_valid,engine_publish,engine_bank,engine_start,engine_flush,engine_audio_valid;
 wire [31:0] engine_lba[0:1],engine_wr_data[0:1],engine_samples[0:1],engine_audio_data[0:1];
 wire [5:0] engine_state[0:1];wire [7:0] engine_error[0:1];
 wire [31:0] engine_logical[0:1],engine_frame[0:1];wire [19:0] engine_word[0:1];
 wire [20:0] engine_wr_address[0:1];
 wire [9:0] engine_video_count[0:1],engine_image_count[0:1],engine_actual_index[0:1];
 wire [1:0] engine_actual_media[0:1];
 wire [9:0] indexed_music_count;
 wire [639:0] indexed_lyric_text;
 wire indexed_lyric_valid,indexed_lyric_toggle;
 wire [31:0] indexed_position,indexed_duration;
 assign playback_position=engine_v2?indexed_position:audio_position;
 assign playback_duration=engine_v2?indexed_duration:engine_samples[0];
 assign rd_req=running?engine_req[engine_v2]:(probe_state==PROBE_REQUEST && map_valid && !external_fault && !card_fatal);
 assign rd_lba=running?engine_lba[engine_v2]:probe_lba;
 assign rd_ready=running?engine_ready[engine_v2]:((probe_state==PROBE_DATA)||(probe_state==FAILED && probe_inflight));
 assign wr_valid=running && engine_wr_valid[engine_v2];
 assign wr_address=engine_wr_address[engine_v2];assign wr_data=engine_wr_data[engine_v2];
 assign publish_toggle=running && engine_publish[engine_v2];assign publish_bank=engine_bank[engine_v2];
 assign audio_start_toggle=ENABLE_LEGACY?(running && engine_start[selected_engine]):engine_start[1];
 assign audio_flush_toggle=ENABLE_LEGACY?(running && engine_flush[selected_engine]):engine_flush[1];
 assign audio_total_samples=engine_samples[selected_engine];assign audio_data=engine_audio_data[selected_engine];
 assign audio_valid=running && engine_audio_valid[engine_v2];
 assign state=running?engine_state[engine_v2]:probe_state;
 assign error_code=running?engine_error[engine_v2]:probe_error;
 assign logical_lba=running?engine_logical[engine_v2]:0;
 assign frame_number=engine_frame[engine_v2];assign frame_word=engine_word[engine_v2];
 assign video_count=running?engine_video_count[engine_v2]:10'd1;
 assign image_count=running?engine_image_count[engine_v2]:10'd1;
 assign music_count=(running && engine_v2)?indexed_music_count:10'd1;
 assign lyric_text=indexed_lyric_text;
 assign lyric_valid=running && engine_v2 && indexed_lyric_valid;
 assign lyric_toggle=indexed_lyric_toggle;
 assign actual_media=engine_actual_media[engine_v2];assign actual_index=engine_actual_index[engine_v2];
 always @(posedge clk50)begin
  if(!reset_n)begin probe_state<=BOOT;probe_error<=0;word_index<=0;version<=0;engine_v2<=0;probe_inflight<=0;probe_restart_pending<=0;end
  else if(!running)begin
   if(restart)probe_restart_pending<=1;
   if(rd_accept)probe_inflight<=1;
   if(rd_done)probe_inflight<=0;
   if((external_fault || card_fatal) && probe_state!=FAILED)begin
    probe_state<=FAILED;probe_error<=card_fatal?8'h02:8'h07;
   end else if(rd_done && rd_error)begin probe_state<=FAILED;probe_error<=8'h02;end
   else case(probe_state)
    BOOT:if(system_ready)begin probe_state<=PROBE_REQUEST;word_index<=0;end
    PROBE_REQUEST:if(!map_valid)begin probe_state<=FAILED;probe_error<=8'h01;end
     else if(rd_accept)probe_state<=PROBE_DATA;
    PROBE_DATA:if(rd_valid)begin
     if(word_index==1)version<=rd_data;
     if(word_index==127)probe_state<=PROBE_DONE;else word_index<=word_index+1'b1;
    end
    PROBE_DONE:if(rd_done)begin
     if(probe_restart_pending || restart)begin probe_state<=BOOT;probe_restart_pending<=0;end
     else if((ENABLE_LEGACY && version==1) || version==2 || version==3)begin engine_v2<=version!=1;probe_state<=RUN;end
     else begin probe_state<=FAILED;probe_error<=8'h04;end
    end
    FAILED:if((restart || probe_restart_pending) && !probe_inflight && !external_fault && !card_fatal)begin
     probe_state<=BOOT;probe_error<=0;probe_restart_pending<=0;end
    default:begin probe_state<=FAILED;probe_error<=8'hff;end
   endcase
  end
 end
 generate if(ENABLE_LEGACY)begin: with_legacy
 media_sequencer #(.CYCLES_PER_MS(CYCLES_PER_MS)) legacy(
 .clk50(clk50),.reset_n(reset_n && running && !engine_v2),.system_ready(system_ready),.external_fault(external_fault),
 .rd_req(engine_req[0]),.rd_lba(engine_lba[0]),.rd_accept(rd_accept && running && !engine_v2),
 .rd_data(rd_data),.rd_valid(rd_valid && running && !engine_v2),.rd_ready(engine_ready[0]),
 .rd_done(rd_done && running && !engine_v2),.rd_error(rd_error),.card_fatal(card_fatal),
 .wr_address(engine_wr_address[0]),.wr_data(engine_wr_data[0]),.wr_valid(engine_wr_valid[0]),.wr_ready(wr_ready),
 .publish_toggle(engine_publish[0]),.publish_bank(engine_bank[0]),.commit_toggle(commit_toggle),
 .audio_start_toggle(engine_start[0]),.audio_flush_toggle(engine_flush[0]),.audio_total_samples(engine_samples[0]),
 .audio_done_toggle(audio_done_toggle),.audio_write_level(audio_write_level),
 .audio_data(engine_audio_data[0]),.audio_valid(engine_audio_valid[0]),.audio_ready(audio_ready),
 .state(engine_state[0]),.error_code(engine_error[0]),.logical_lba(engine_logical[0]),
 .frame_number(engine_frame[0]),.frame_word(engine_word[0]),
 .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),
 .video_count(engine_video_count[0]),.image_count(engine_image_count[0]),
 .actual_media(engine_actual_media[0]),.actual_index(engine_actual_index[0]));
 end else begin: without_legacy
  assign engine_req[0]=0;assign engine_ready[0]=0;assign engine_lba[0]=0;
  assign engine_wr_valid[0]=0;assign engine_wr_address[0]=0;assign engine_wr_data[0]=0;
  assign engine_publish[0]=0;assign engine_bank[0]=0;assign engine_start[0]=0;assign engine_flush[0]=0;
  assign engine_samples[0]=0;assign engine_audio_data[0]=0;assign engine_audio_valid[0]=0;
  assign engine_state[0]=0;assign engine_error[0]=0;assign engine_logical[0]=0;
  assign engine_frame[0]=0;assign engine_word[0]=0;assign engine_video_count[0]=1;
  assign engine_image_count[0]=1;assign engine_actual_media[0]=0;assign engine_actual_index[0]=0;
 end endgenerate
 media_sequencer_v2 #(.CYCLES_PER_MS(CYCLES_PER_MS),.DEST_WIDTH(DEST_WIDTH),.DEST_HEIGHT(DEST_HEIGHT)) indexed(
 .clk50(clk50),.reset_n(reset_n && running && selected_engine),.system_ready(system_ready),.external_fault(external_fault),
 .rd_req(engine_req[1]),.rd_lba(engine_lba[1]),.rd_accept(rd_accept && running && engine_v2),
 .rd_data(rd_data),.rd_valid(rd_valid && running && engine_v2),.rd_ready(engine_ready[1]),
 .rd_done(rd_done && running && engine_v2),.rd_error(rd_error),.card_fatal(card_fatal),
 .wr_address(engine_wr_address[1]),.wr_data(engine_wr_data[1]),.wr_valid(engine_wr_valid[1]),.wr_ready(wr_ready),
 .publish_toggle(engine_publish[1]),.publish_bank(engine_bank[1]),.commit_toggle(commit_toggle),
 .audio_start_toggle(engine_start[1]),.audio_flush_toggle(engine_flush[1]),.audio_total_samples(engine_samples[1]),
 .audio_done_toggle(audio_done_toggle),.audio_write_level(audio_write_level),
 .audio_data(engine_audio_data[1]),.audio_valid(engine_audio_valid[1]),.audio_ready(audio_ready),
 .state(engine_state[1]),.error_code(engine_error[1]),.logical_lba(engine_logical[1]),
 .frame_number(engine_frame[1]),.frame_word(engine_word[1]),
 .pause(pause),.restart(restart),.media_select(media_select),.media_index(media_index),.scale_mode(scale_mode),
 .video_count(engine_video_count[1]),.image_count(engine_image_count[1]),
 .music_count(indexed_music_count),.audio_position(audio_position),.audio_position_epoch(audio_position_epoch),
 .seek_request(seek_request),.seek_seconds(seek_seconds),.playback_position(indexed_position),.playback_duration(indexed_duration),
 .lyric_text(indexed_lyric_text),.lyric_valid(indexed_lyric_valid),.lyric_toggle(indexed_lyric_toggle),
 .actual_media(engine_actual_media[1]),.actual_index(engine_actual_index[1]));
endmodule

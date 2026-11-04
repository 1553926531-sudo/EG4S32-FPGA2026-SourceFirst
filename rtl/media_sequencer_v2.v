`timescale 1ns/1ps
                                                                                 
                                                                           
                                                                         
                                                           
module media_sequencer_v2 #(parameter CYCLES_PER_MS=50000,DEST_WIDTH=1280,DEST_HEIGHT=800,FILE_IO=0,BLANK_BOOT=0,
 AUDIO_PREFILL=2048,AUDIO_LOW_WATER=3072)(
 input wire clk50,input wire reset_n,input wire system_ready,input wire external_fault,
 input wire play_enabled,input wire native_raw,input wire [31:0] file_sectors,
 output wire idle_ready,output wire display_ready,
 output wire rd_req,output wire [31:0] rd_lba,input wire rd_accept,
 input wire [31:0] rd_data,input wire rd_valid,output wire rd_ready,
 input wire rd_done,input wire rd_error,input wire card_fatal,
 output wire [20:0] wr_address,output wire [31:0] wr_data,output wire wr_valid,input wire wr_ready,
 output reg publish_toggle,output reg publish_bank,input wire commit_toggle,
 output reg audio_start_toggle,output reg audio_flush_toggle,output wire [31:0] audio_total_samples,
 input wire audio_done_toggle,input wire [12:0] audio_write_level,
 output wire [31:0] audio_data,output wire audio_valid,input wire audio_ready,
 output reg [5:0] state,output reg [7:0] error_code,
 output reg [31:0] logical_lba,output reg [31:0] frame_number,output reg [19:0] frame_word,
 input wire pause,input wire restart,input wire [1:0] media_select,input wire [9:0] media_index,
 input wire [1:0] scale_mode,input wire [31:0] audio_position,input wire audio_position_epoch,
 input wire seek_request,input wire [15:0] seek_seconds,
 output wire [31:0] playback_position,output wire [31:0] playback_duration,
 output reg [9:0] video_count,output reg [9:0] image_count,
 output reg [9:0] music_count,output reg [639:0] lyric_text,
 output reg lyric_valid,output reg lyric_toggle,
 output reg [1:0] actual_media,output reg [9:0] actual_index);
 localparam BOOT=0,REQUEST=1,RECEIVE=2,WAIT_SD=3,DISPATCH=4,PUBLISH=5,
  SCHEDULE=6,AUDIO_WAIT=8,AUDIO_LOAD=9,AUDIO_PUSH=10,HEADER_CHECK=13,HEADER_SPAN=14,DRAIN=15,
  HEADER_CAPACITY=16,HEADER_AUDIO_CHECK=17,HEADER_APPLY=18,
  TRACK_CHECK=19,TRACK_SPAN=20,TRACK_CAPACITY=21,TRACK_APPLY=22,DESC_CHECK=23,
  SEEK_PREP=24,SEEK_DIVIDE=25,SEEK_AUDIO=26,SEEK_VIDEO=27,CUE_COPY=28,FAILED=31,
  BLANK_FILL=32,BLANK_PUBLISH=33,BLANK_WAIT=34,HEADER_FIELDS=35,HEADER_DECIDE=36;
 localparam HEADER=0,DESC=1,PIXEL=2,AUDIO=3,TRACK=4,CUE=5;
 reg [2:0] mode;
 reg [1:0] active_media;
 reg [31:0] header[0:23];
 reg [31:0] descriptor[0:7];
 reg [31:0] track[0:7],cue[0:3];
 reg cue_copy_busy,cue_copy_publish,cue_copy_wait;
 reg [4:0] cue_copy_index;
 wire [31:0] cue_stage_data;
 reg [30:0] track_samples,track_capacity,track_floor;
 reg [27:0] track_start,cue_lba;
 reg [30:0] cue_previous;
 reg [31:0] video_target;
 reg [21:0] frame_samples;
 reg [12:0] cue_count,cue_index;
 reg [9:0] track_id,selected_index;
 reg track_ready,need_track,cue_pending;
                                                                      
                                                                         
                                                                         
                                                                        
 reg seek_pending,cue_seeking,seek_cue_valid;
 reg [31:0] seek_sample,divide_q;
 reg [30:0] play_base;
 reg [21:0] divide_r,divide_d;
 reg [5:0] divide_bits;
 reg divide_video;
 reg [6:0] audio_skip;
 reg audio_started,scale_start;
 wire playhead_ready=audio_position_epoch==audio_start_toggle;
                                                                         
 wire seeking=(seek_request===1'b1) && !(restart===1'b1);
 wire [31:0] seek_seconds_wide={16'd0,seek_seconds};
 wire [31:0] requested_sample=seek_seconds_wide*32'd48000;
 wire [31:0] absolute_position=play_base+audio_position;
 assign playback_duration=track_samples;
 assign playback_position=(!audio_started || !playhead_ready)?play_base:
                          ((absolute_position>track_samples)?track_samples:absolute_position);
 wire [22:0] divide_trial={divide_r,divide_q[31]};
 wire [22:0] divide_difference=divide_trial-{1'b0,divide_d};
 wire divide_subtract=!divide_difference[22];
 wire [21:0] divide_next_r=divide_subtract?divide_difference[21:0]:divide_trial[21:0];
 wire [31:0] divide_next_q={divide_q[30:0],divide_subtract};
 wire extended=FILE_IO?1'b1:(header[1]==3);
 reg [31:0] sector_crc,image_crc;
 reg [23:0] crc_tail;
 reg [1:0] crc_bytes;
 reg [6:0] word_index;
 reg block_bad,sd_inflight,publish_pending,restart_previous;
 reg blank_done,publish_blank,blank_music;
 reg [19:0] blank_address;
 wire [31:0] scale_data;
 wire scale_valid;
 reg [5:0] restart_settle;
 reg [19:0] work_index;
 reg need_descriptor,image_active,image_prepared,image_scaled,have_display;
 reg [27:0] image_lba,audio_lba;
 reg [15:0] image_remaining;
 reg [30:0] audio_remaining,audio_pushed;
 reg [31:0] hold_count,hold_cycles;
 reg [31:0] header_audio_sectors,header_audio_capacity,header_audio_floor;
 reg [20:0] header_metadata,header_image_base;
 reg [21:0] header_track_end;
 reg [10:0] header_track_count;
 reg header_file_bad,header_fields_bad;
 reg [27:0] descriptor_floor,descriptor_available;
 reg descriptor_fields_bad;
 reg header_input_bad,descriptor_input_bad,track_input_bad;
 reg fault_active,fault_card;
 reg [5:0] descriptor_row_sectors;
 reg [16:0] descriptor_sector_product;
 wire [20:0] metadata_sectors=21'd1+{1'b0,header[6][19:0]}+{11'd0,header[18][9:0]};
 wire [15:0] selected_hold_ms=(media_select==0)?header[7][15:0]:header[16][15:0];
 reg [11:0] raw_x,source_stride;
 wire [31:0] audio_stage_data;
 wire audio_stage_write=state==RECEIVE && mode==AUDIO && rd_valid && rd_ready && word_index<127;
 reg [6:0] emit_index;
 reg [7:0] emit_count;
 reg [31:0] emit_data;
                                                                            
                                                                                
 eg_dual_clock_mem #(.WIDTH(32),.AW(7),.IMPLEMENT("9K")) audio_stage(
  .wclk(clk50),.wrst(!reset_n),.we(audio_stage_write),.waddr(word_index),.wdata(rd_data),
  .rclk(clk50),.rrst(!reset_n),.re(1'b1),.raddr(emit_index),.rdata(audio_stage_data));
                                                                      
                                                                     
                                                                       
 wire cue_stage_write=state==RECEIVE && mode==CUE && rd_valid && rd_ready &&
                      word_index>=4 && word_index<24;
 eg_dual_clock_mem #(.WIDTH(32),.AW(5),.IMPLEMENT("9K")) cue_stage(
  .wclk(clk50),.wrst(!reset_n),.we(cue_stage_write),.waddr(word_index[4:0]-5'd4),.wdata(rd_data),
  .rclk(clk50),.rrst(!reset_n),.re(1'b1),.raddr(cue_copy_index),.rdata(cue_stage_data));
 wire [6:0] cue_byte_offset={(word_index[4:0]-5'd4),2'b00};
 wire map_valid;
 wire [31:0] map_sectors,expected_header_crc;
 generate if(FILE_IO)begin: file_addresses
  assign rd_lba=logical_lba;
  assign map_valid=file_sectors!=0;
  assign map_sectors=file_sectors;
  assign expected_header_crc=0;
 end else begin: fixed_addresses
  media_extent_map address_map(.logical_lba(logical_lba),.physical_lba(rd_lba),.valid(map_valid),
   .expected_header_crc(expected_header_crc),.file_sectors(map_sectors));
 end endgenerate
 assign idle_ready=state==BOOT && !publish_pending && !sd_inflight && !scale_busy;
 assign display_ready=have_display && track_ready;
 (* async_reg="true" *) reg commit_sync1,commit_sync2,audio_done_sync1,audio_done_sync2;
 wire paused=(pause===1'b1);
                                                                          
                                                                        
 wire restarting=(restart===1'b1) || seeking;
 wire restart_event=restarting && !restart_previous;
 wire draining=state==DRAIN || state==FAILED;
 wire scale_abort=draining || restarting || external_fault || card_fatal;
 wire scale_ready,scale_busy,scale_done,scale_error;
 wire [19:0] scale_address;
 image_scaler #(.DEST_WIDTH(DEST_WIDTH),.DEST_HEIGHT(DEST_HEIGHT)) scaler(
  .clk(clk50),.reset_n(reset_n),.start(scale_start),.abort(scale_abort),
  .width(descriptor[2][11:0]),.height(descriptor[3][11:0]),.mode(scale_mode),
  .in_data(rd_data),.in_valid(state==RECEIVE && mode==PIXEL && rd_valid && crc_bytes==0 && !scale_abort),
  .in_ready(scale_ready),.out_address(scale_address),.out_data(scale_data),
  .out_valid(scale_valid),.out_ready(wr_ready && state!=BLANK_FILL),.busy(scale_busy),.done(scale_done),.error(scale_error));
 assign wr_address={publish_bank,(state==BLANK_FILL)?blank_address:scale_address};
 assign wr_data=(state==BLANK_FILL)?32'h00101820:scale_data;
 assign wr_valid=(state==BLANK_FILL)?(!restarting && !external_fault && !card_fatal):scale_valid;
 assign rd_req=state==REQUEST && map_valid && !restarting && !external_fault && !card_fatal;
 assign rd_ready=(draining && sd_inflight) ||
  (state==RECEIVE && !restarting && crc_bytes==0 && ((mode!=PIXEL)||scale_ready));
 assign audio_data=emit_data;
 assign audio_valid=state==AUDIO_PUSH && !restarting && !external_fault && !card_fatal;
 assign audio_total_samples=track_samples-play_base;
 function [31:0] crc_byte;
  input [31:0] old;input [7:0] data;reg [31:0] c;integer i;
  begin c=old^{24'd0,data};for(i=0;i<8;i=i+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
                                                                          
                                                                             
                                                                           
 wire [7:0] crc_input=crc_bytes!=0?crc_tail[7:0]:rd_data[7:0];
 wire [31:0] next_crc=crc_byte((mode==PIXEL)?image_crc:sector_crc,crc_input);
 task fail;
  input [7:0] code;
  begin state<=FAILED;error_code<=code;audio_flush_toggle<=~audio_flush_toggle;audio_started<=0;end
 endtask
 integer k;
 always @(posedge clk50)begin
  if(!reset_n)begin
   state<=BOOT;error_code<=0;logical_lba<=0;frame_number<=0;frame_word<=0;
   publish_toggle<=0;publish_bank<=0;audio_start_toggle<=0;audio_flush_toggle<=0;
   mode<=HEADER;active_media<=0;sector_crc<=32'hffffffff;image_crc<=32'hffffffff;crc_tail<=0;crc_bytes<=0;
   word_index<=0;block_bad<=0;sd_inflight<=0;publish_pending<=0;restart_previous<=0;restart_settle<=0;
   blank_done<=0;publish_blank<=0;blank_music<=0;blank_address<=0;
   work_index<=0;need_descriptor<=0;image_active<=0;image_prepared<=0;image_scaled<=0;have_display<=0;
   image_lba<=0;image_remaining<=0;audio_lba<=0;audio_remaining<=0;audio_pushed<=0;
   hold_count<=0;hold_cycles<=0;raw_x<=0;source_stride<=0;
   header_audio_sectors<=0;header_audio_capacity<=0;header_audio_floor<=0;
   header_metadata<=0;header_image_base<=0;header_track_end<=0;header_track_count<=0;
   header_file_bad<=0;header_fields_bad<=0;
   descriptor_floor<=0;descriptor_available<=0;descriptor_row_sectors<=0;descriptor_sector_product<=0;
   descriptor_fields_bad<=0;header_input_bad<=0;descriptor_input_bad<=0;track_input_bad<=0;fault_active<=0;fault_card<=0;
   emit_index<=0;emit_count<=0;emit_data<=0;audio_started<=0;scale_start<=0;
   commit_sync1<=0;commit_sync2<=0;audio_done_sync1<=0;audio_done_sync2<=0;
   video_count<=1;image_count<=1;actual_media<=0;actual_index<=0;
   music_count<=1;lyric_text<=0;lyric_valid<=0;lyric_toggle<=0;
   cue_copy_busy<=0;cue_copy_publish<=0;cue_copy_wait<=0;cue_copy_index<=0;
   track_samples<=0;track_start<=0;track_capacity<=0;track_floor<=0;
   cue_lba<=0;cue_previous<=0;cue_count<=0;cue_index<=0;cue_pending<=0;
   track_id<=0;selected_index<=0;track_ready<=0;need_track<=0;video_target<=0;frame_samples<=0;
   seek_pending<=0;seek_sample<=0;play_base<=0;audio_skip<=0;
   divide_q<=0;divide_r<=0;divide_d<=1;divide_bits<=0;divide_video<=0;
   cue_seeking<=0;seek_cue_valid<=0;
   for(k=0;k<24;k=k+1)header[k]<=0;
   for(k=0;k<8;k=k+1)descriptor[k]<=0;
   for(k=0;k<8;k=k+1)track[k]<=0;
   for(k=0;k<4;k=k+1)cue[k]<=0;
  end else begin
   scale_start<=0;restart_previous<=restarting;
   if(crc_bytes!=0)begin
    if(mode==PIXEL)image_crc<=next_crc;else sector_crc<=next_crc;
    crc_tail<={8'd0,crc_tail[23:8]};crc_bytes<=crc_bytes-1'b1;
   end
                                                                          
                                                                           
                                                                     
   fault_active<=external_fault || card_fatal;fault_card<=card_fatal;
   commit_sync1<=commit_toggle;commit_sync2<=commit_sync1;
   audio_done_sync1<=audio_done_toggle;audio_done_sync2<=audio_done_sync1;
   if(rd_accept)sd_inflight<=1;
   if(rd_done)sd_inflight<=0;
   if(scale_done && !scale_error && !draining)image_scaled<=1;
   if(wr_valid && wr_ready)frame_word<=wr_address[19:0]+1'b1;
   if(have_display && !paused && hold_count<hold_cycles)hold_count<=hold_count+1'b1;
   if(publish_pending && commit_sync2==publish_toggle)begin
    publish_pending<=0;publish_bank<=~publish_bank;have_display<=1;hold_count<=0;
    if(publish_blank)begin
     publish_blank<=0;blank_done<=1;
     if(blank_music)begin actual_media<=active_media;actual_index<=selected_index;end
    end else begin
     actual_media<=active_media;
     actual_index<=(extended && active_media!=1)?selected_index:work_index[9:0];frame_number<=work_index;
    end
    if(!publish_blank && !draining && active_media!=2)begin
                                                                        
                                                                            
                                                                  
     need_descriptor<=!(FILE_IO && native_raw && active_media==1) && !(extended && active_media==0 && work_index+1>=header[6]);
     if(extended && active_media==0)video_target<=video_target+frame_samples;
     if(work_index+1>=((active_media==0)?header[6]:header[18]))work_index<=0;
     else work_index<=work_index+1'b1;
    end
   end
                                                                        
                                                                     
   if(!audio_started && have_display && !draining && !restarting &&
      !external_fault && !card_fatal && audio_pushed!=0 &&
      !cue_seeking && (!extended || cue_count==0 || cue_pending || cue_index!=0) &&
      (audio_pushed>=AUDIO_PREFILL || audio_pushed>=audio_total_samples))begin
    audio_start_toggle<=~audio_start_toggle;audio_started<=1;
   end
   if(cue_copy_busy && !draining && !restarting && !external_fault && !card_fatal)begin
    if(!cue_copy_wait)cue_copy_wait<=1;
    else begin
     for(k=0;k<20;k=k+1)if(cue_copy_index==k)lyric_text[k*32+:32]<=cue_stage_data;
     cue_copy_wait<=0;
     if(cue_copy_index==19)begin
      cue_copy_busy<=0;cue_pending<=0;cue_index<=cue_index+1'b1;cue_previous<=cue[1];
      if(cue_copy_publish)begin lyric_valid<=1;lyric_toggle<=~lyric_toggle;end
      else seek_cue_valid<=1;
     end else cue_copy_index<=cue_copy_index+1'b1;
    end
   end
   if(extended && cue_pending && !cue_copy_busy && audio_started && playhead_ready && !draining && !restarting &&
      !external_fault && !card_fatal && absolute_position>=cue[1])begin
    cue_copy_busy<=1;cue_copy_publish<=1;cue_copy_index<=0;cue_copy_wait<=0;
   end
   if(restart_event && state!=DRAIN)begin
    state<=DRAIN;restart_settle<=31;audio_flush_toggle<=~audio_flush_toggle;audio_started<=0;
    lyric_valid<=0;lyric_toggle<=~lyric_toggle;cue_pending<=0;cue_copy_busy<=0;
    seek_pending<=seeking;seek_sample<=seeking?requested_sample:32'd0;
   end else if(state==DRAIN)begin
                                                                          
                                                                             
    if(restart_event)begin seek_pending<=seeking;seek_sample<=seeking?requested_sample:32'd0;restart_settle<=31;end
    else if(restart_settle!=0)restart_settle<=restart_settle-1'b1;
    if(!restart_event && !sd_inflight && !publish_pending && !scale_busy && restart_settle==0)begin
     state<=BOOT;error_code<=0;logical_lba<=0;mode<=HEADER;
     need_descriptor<=0;image_active<=0;image_prepared<=0;image_scaled<=0;have_display<=0;
     image_remaining<=0;audio_remaining<=0;audio_pushed<=0;audio_started<=0;hold_count<=0;frame_word<=0;
     track_ready<=0;need_track<=0;cue_pending<=0;cue_index<=0;cue_count<=0;video_target<=0;
     play_base<=0;audio_skip<=0;cue_seeking<=0;seek_cue_valid<=0;
    end
   end else if(fault_active)begin
    cue_copy_busy<=0;
    if(state!=FAILED)fail(fault_card?8'h02:8'h07);
   end else if(external_fault || card_fatal)begin
                                                                       
                                                                      
   end else if(rd_done && rd_error && !draining)fail(8'h02);
   else if(scale_error && image_active && !draining)fail(8'h09);
   else case(state)
    BOOT:if(system_ready)begin
     if(BLANK_BOOT && !blank_done)begin blank_address<=0;blank_music<=0;state<=BLANK_FILL;end
     else if(!FILE_IO || play_enabled)begin mode<=HEADER;logical_lba<=0;state<=REQUEST;end
    end
    BLANK_FILL:if(wr_valid && wr_ready)begin
     if(blank_address==DEST_WIDTH*DEST_HEIGHT-1)state<=BLANK_PUBLISH;
     else blank_address<=blank_address+1'b1;
    end
    BLANK_PUBLISH:begin
     publish_toggle<=~publish_toggle;publish_pending<=1;publish_blank<=1;state<=BLANK_WAIT;
    end
    BLANK_WAIT:if(!publish_pending)state<=blank_music?(seek_pending?SEEK_PREP:SCHEDULE):BOOT;
    REQUEST:begin
     word_index<=0;sector_crc<=32'hffffffff;block_bad<=0;
     if(mode==HEADER)header_input_bad<=0;
     if(mode==DESC)descriptor_input_bad<=0;
     if(mode==TRACK)track_input_bad<=0;
     if(!map_valid || logical_lba>=map_sectors)fail(8'h01);
     else if(rd_accept)state<=RECEIVE;
    end
    RECEIVE:if(rd_valid && rd_ready)begin
     if(mode==PIXEL || word_index<127)begin crc_tail<=rd_data[31:8];crc_bytes<=3;end
     if(mode==PIXEL)begin
      image_crc<=next_crc;
      if(rd_data[31:24]!=0 || (raw_x>=descriptor[2] && rd_data!=0))block_bad<=1;
      if(raw_x==source_stride-1)raw_x<=0;else raw_x<=raw_x+1'b1;
     end else begin
      if(word_index<127)sector_crc<=next_crc;
      else if(!(FILE_IO && native_raw) &&
       (rd_data!=~sector_crc || (!FILE_IO && mode==HEADER && rd_data!=expected_header_crc)))block_bad<=1;
      if(mode==HEADER)case(word_index)
       0:if(rd_data!=32'h314d4654)header_input_bad<=1;
       1:begin header[1]<={30'd0,rd_data[1:0]};if(FILE_IO?(rd_data!=3):(rd_data!=2 && rd_data!=3))header_input_bad<=1;end
       2:if(rd_data!=1280)header_input_bad<=1;
       3:if(rd_data!=800)header_input_bad<=1;
       4:if(rd_data!=1)header_input_bad<=1;
       5:if(rd_data!=1024000)header_input_bad<=1;
       6:begin header[6]<={12'd0,rd_data[19:0]};if(rd_data==0 || rd_data>(extended?1000000:600))header_input_bad<=1;end
       7:begin header[7]<={16'd0,rd_data[15:0]};if(rd_data<(extended?80:1000) || rd_data>60000)header_input_bad<=1;end
       8:if(rd_data!=1)header_input_bad<=1;
       9:if(rd_data!=1)header_input_bad<=1;
       10:begin header[10]<={11'd0,rd_data[20:0]};if(|rd_data[31:21])header_input_bad<=1;end
       11:begin header[11]<={4'd0,rd_data[27:0]};if(|rd_data[31:28])header_input_bad<=1;end
       12:begin header[12]<={1'b0,rd_data[30:0]};if(rd_data==0 || rd_data>(extended?2073600000:172800000))header_input_bad<=1;end
       13:if(rd_data!=48000)header_input_bad<=1;
       14:if(rd_data!=16)header_input_bad<=1;
       15:if(rd_data!=2)header_input_bad<=1;
       16:begin header[16]<={16'd0,rd_data[15:0]};if(rd_data<1000 || rd_data>60000)header_input_bad<=1;end
       17:begin header[17]<={4'd0,rd_data[27:0]};if(rd_data>(extended?200000000:40000000))header_input_bad<=1;end
       18:begin header[18]<={22'd0,rd_data[9:0]};if(rd_data>600 || (rd_data==0 && !(FILE_IO && extended && media_select==0)))header_input_bad<=1;end
       19:if(rd_data!=1)header_input_bad<=1;
       20:begin header[20]<={22'd0,rd_data[9:0]};if(extended && (rd_data>600 || (rd_data==0 && !(FILE_IO && media_select==0))))header_input_bad<=1;end
       21:begin header[21]<={11'd0,rd_data[20:0]};if(extended && |rd_data[31:21])header_input_bad<=1;end
       22:begin header[22]<={22'd0,rd_data[9:0]};if(extended && |rd_data[31:10])header_input_bad<=1;end
       23:begin header[23]<={4'd0,rd_data[27:0]};if(extended && |rd_data[31:28])header_input_bad<=1;end
       default:begin end
      endcase
      if(mode==DESC)case(word_index)
       0:if(rd_data!=32'h32474d49)descriptor_input_bad<=1;
       1:begin descriptor[1]<={rd_data[31],11'd0,rd_data[19:0]};if(|rd_data[30:20])descriptor_input_bad<=1;end
       2:begin descriptor[2]<={20'd0,rd_data[11:0]};if(rd_data==0 || rd_data>2048)descriptor_input_bad<=1;end
       3:begin descriptor[3]<={20'd0,rd_data[11:0]};if(rd_data==0 || rd_data>2048)descriptor_input_bad<=1;end
       4:begin descriptor[4]<={4'd0,rd_data[27:0]};if(|rd_data[31:28])descriptor_input_bad<=1;end
       5:begin descriptor[5]<={27'd0,rd_data[4:0]};if(|rd_data[31:5])descriptor_input_bad<=1;end
       6:begin descriptor[6]<={16'd0,rd_data[15:0]};if(|rd_data[31:16])descriptor_input_bad<=1;end
       7:descriptor[7]<=rd_data;
       default:begin end
      endcase
      if(mode==TRACK)case(word_index)
       0:if(rd_data!=32'h33445541)track_input_bad<=1;
       1:begin track[1]<={22'd0,rd_data[9:0]};if(|rd_data[31:10])track_input_bad<=1;end
       2:begin track[2]<={4'd0,rd_data[27:0]};if(|rd_data[31:28])track_input_bad<=1;end
       3:begin track[3]<={1'b0,rd_data[30:0]};if(rd_data==0 || rd_data>2073600000)track_input_bad<=1;end
       4:begin track[4]<={8'd0,rd_data[23:0]};if(rd_data==0 || rd_data>16327560)track_input_bad<=1;end
       5:begin track[5]<={22'd0,rd_data[9:0]};if(|rd_data[31:10])track_input_bad<=1;end
       6:begin track[6]<={4'd0,rd_data[27:0]};if(|rd_data[31:28])track_input_bad<=1;end
       7:begin track[7]<={19'd0,rd_data[12:0]};if(rd_data>4096)track_input_bad<=1;end
       default:begin end
      endcase
      if(mode==CUE)begin
       if(word_index<4)cue[word_index]<=rd_data;
       if(word_index>=4 && word_index<24)begin
        if(rd_data[7:0]<32 || rd_data[7:0]>126 || rd_data[15:8]<32 || rd_data[15:8]>126 ||
           rd_data[23:16]<32 || rd_data[23:16]>126 || rd_data[31:24]<32 || rd_data[31:24]>126)block_bad<=1;
                                                                            
                                                               
        if((cue_byte_offset>=cue[3][6:0] && rd_data[7:0]!=32) ||
           (cue_byte_offset+7'd1>=cue[3][6:0] && rd_data[15:8]!=32) ||
           (cue_byte_offset+7'd2>=cue[3][6:0] && rd_data[23:16]!=32) ||
           (cue_byte_offset+7'd3>=cue[3][6:0] && rd_data[31:24]!=32))block_bad<=1;
       end
      end
      if(mode==AUDIO && word_index<127)begin
       if(word_index>=audio_remaining && rd_data!=0)block_bad<=1;
      end
     end
     if(word_index==127)state<=WAIT_SD;else word_index<=word_index+1'b1;
    end
    WAIT_SD:if(!sd_inflight && crc_bytes==0)begin
     if(block_bad)fail((mode==AUDIO)?8'h06:8'h03);else state<=DISPATCH;
    end
    DISPATCH:case(mode)
     HEADER:state<=HEADER_CHECK;
     DESC:begin
                                                                     
                                                                     
                                                                     
      descriptor_available<=header[11]-descriptor[4];
      descriptor_row_sectors<=({1'b0,descriptor[2][11:0]}+13'd127)>>7;
      descriptor_sector_product<=descriptor[5][4:0]*descriptor[3][11:0];
                                                                    
                                                                    
      descriptor_fields_bad<=descriptor_input_bad ||
       descriptor[1]!=((active_media==0)?work_index:(32'h80000000|work_index)) ||
       descriptor[4]<descriptor_floor || descriptor[4]>=header[11];
      state<=DESC_CHECK;
     end
     PIXEL:begin image_remaining<=image_remaining-1'b1;image_lba<=image_lba+1'b1;state<=SCHEDULE;end
     AUDIO:begin
      emit_index<=audio_skip;emit_count<=(audio_remaining>=127)?127:audio_remaining[7:0];state<=AUDIO_WAIT;
     end
     TRACK:state<=TRACK_CHECK;
     CUE:begin
      if(cue[0]!=32'h33455543 || cue[2]!={19'd0,cue_index} || cue[3]>78 || cue[1]>=track_samples ||
         (cue_index!=0 && cue[1]<=cue_previous))fail(8'h0b);
      else if(cue_seeking && cue[1]<=play_base)begin
       cue_copy_busy<=1;cue_copy_publish<=0;cue_copy_index<=0;cue_copy_wait<=0;state<=CUE_COPY;
      end else begin
       cue_pending<=1;state<=SCHEDULE;
       if(cue_seeking)begin
        cue_seeking<=0;lyric_valid<=seek_cue_valid;lyric_toggle<=~lyric_toggle;
       end
      end
     end
     default:fail(8'h04);
    endcase
    CUE_COPY:if(!cue_copy_busy)state<=SCHEDULE;
    DESC_CHECK:begin
     if(descriptor_fields_bad || descriptor[5]!={26'd0,descriptor_row_sectors} ||
      descriptor[6]!={15'd0,descriptor_sector_product} ||
      descriptor[6]>descriptor_available)fail(8'h08);
     else begin
      scale_start<=1;image_active<=1;image_scaled<=0;image_prepared<=0;
      image_lba<=descriptor[4];image_remaining<=descriptor[6];image_crc<=32'hffffffff;
      source_stride<=descriptor[5]<<7;raw_x<=0;frame_word<=0;state<=SCHEDULE;
     end
    end
    HEADER_CHECK:begin
     header_audio_sectors<=header[17]-header[11];
     header_metadata<=metadata_sectors;
     header_image_base<=21'd1+{1'b0,header[6][19:0]};
     header_track_end<={1'b0,header[21][20:0]}+{12'd0,header[22][9:0]};
     header_track_count<={1'b0,header[20][9:0]}+11'd1;
     header_file_bad<=header_input_bad || header[17]!=map_sectors || header[17]<=header[11];
     state<=HEADER_FIELDS;
    end
    HEADER_FIELDS:begin
     header_fields_bad<=header_file_bad || header[10]!={11'd0,header_image_base} ||
      header[11]<={11'd0,header_metadata} || (extended &&
       (header[21]!={11'd0,header_metadata} || header[22]!={21'd0,header_track_count} ||
        header[23]<{10'd0,header_track_end} || header[23]>=header[11]));
     state<=HEADER_DECIDE;
    end
    HEADER_DECIDE:begin
     if(header_fields_bad)fail(8'h04);
     else state<=extended?HEADER_APPLY:HEADER_SPAN;
    end
    HEADER_SPAN:begin
     if(header_audio_sectors==0 || header_audio_sectors>1360630)fail(8'h04);
     else begin
                                                                        
      header_audio_capacity<=(header_audio_sectors<<7)-header_audio_sectors;
      state<=HEADER_CAPACITY;
     end
    end
    HEADER_CAPACITY:begin
     header_audio_floor<=header_audio_capacity-127;
     state<=HEADER_AUDIO_CHECK;
    end
    HEADER_AUDIO_CHECK:begin
     if(header[12]>header_audio_capacity || header[12]<=header_audio_floor)fail(8'h04);
     else state<=HEADER_APPLY;
    end
    HEADER_APPLY:begin
                                                                      
                                                                           
      descriptor_floor<=extended?header[23]:{11'd0,metadata_sectors};
      video_count<=extended?10'd1:header[6][9:0];image_count<=header[18][9:0];
      music_count<=extended?header[20][9:0]:10'd1;
      active_media<=(media_select==1 || media_select==2)?media_select:2'd0;
      selected_index<=(media_select==2 && media_index<header[20] && extended)?media_index:10'd0;
      if(media_select==2 || (extended && media_select==0))work_index<=0;
      else if((^media_index!==1'bx) && media_index<((media_select==1)?header[18]:header[6]))work_index<=media_index;
      else work_index<=0;
      hold_cycles<=selected_hold_ms*CYCLES_PER_MS;
      audio_remaining<=(FILE_IO && media_select==1)?32'd0:header[12];audio_lba<=header[11];audio_pushed<=0;audio_started<=0;
      track_samples<=(FILE_IO && media_select==1)?32'd0:header[12];track_start<=header[11];
      need_track<=extended && !(FILE_IO && media_select==1);track_ready<=!extended || (FILE_IO && media_select==1);
      cue_pending<=0;cue_index<=0;cue_count<=0;cue_previous<=0;cue_copy_busy<=0;
      track_id<=(media_select==0)?10'd0:(media_select==2 && media_index<header[20])?(media_index+1'b1):10'd1;
      video_target<=0;frame_samples<=({16'd0,header[7][15:0]}<<5)+({16'd0,header[7][15:0]}<<4);
      have_display<=0;need_descriptor<=!(FILE_IO && media_select==2);image_prepared<=0;image_active<=0;
      state<=(!extended && seek_pending)?SEEK_PREP:SCHEDULE;
    end
    TRACK_CHECK:begin
     track_capacity<=(track[4]<<7)-track[4];
     if(track_input_bad || track[1]!={22'd0,track_id} || track[2]<header[11] || track[2]>=header[17] ||
        track[4]>header[17]-track[2] || (!(FILE_IO && active_media==0) && track[5]>=header[18]) ||
        (track[7]==0 && track[6]!=0) || (track[7]!=0 &&
         (track[6]<header[21]+header[22] || track[6]>=header[23] || track[7]>header[23]-track[6])) ||
        (track_id==0 && (track[2]!=header[11] || track[3]!=header[12])))fail(8'h0a);
     else state<=TRACK_SPAN;
    end
    TRACK_SPAN:begin track_floor<=track_capacity-127;state<=TRACK_CAPACITY;end
    TRACK_CAPACITY:begin
     if(track[3]>track_capacity || track[3]<=track_floor)fail(8'h0a);else state<=TRACK_APPLY;
    end
    TRACK_APPLY:begin
     track_samples<=track[3];track_start<=track[2];audio_remaining<=track[3];audio_lba<=track[2];
     cue_lba<=track[6];cue_count<=track[7][12:0];cue_index<=0;cue_previous<=0;cue_pending<=0;
     if(active_media==2)work_index<=track[5];
     need_track<=0;track_ready<=1;
     if(FILE_IO && active_media==2)begin blank_address<=0;blank_music<=1;state<=BLANK_FILL;end
     else state<=seek_pending?SEEK_PREP:SCHEDULE;
    end
    SEEK_PREP:begin
                                                                         
                                                                         
     play_base<=(seek_sample<track_samples)?seek_sample:(track_samples-1'b1);
     divide_q<=(seek_sample<track_samples)?seek_sample:(track_samples-1'b1);
     divide_r<=0;divide_d<=127;divide_bits<=32;divide_video<=0;
     cue_seeking<=extended && cue_count!=0;seek_cue_valid<=0;state<=SEEK_DIVIDE;
    end
    SEEK_DIVIDE:begin
     divide_q<=divide_next_q;divide_r<=divide_next_r;divide_bits<=divide_bits-1'b1;
     if(divide_bits==1)state<=divide_video?SEEK_VIDEO:SEEK_AUDIO;
    end
    SEEK_AUDIO:begin
     audio_lba<=track_start+divide_q;audio_remaining<=track_samples-play_base+divide_r;
     audio_skip<=divide_r[6:0];
     if(active_media==0)begin
      divide_q<=play_base;divide_r<=0;divide_d<=frame_samples;divide_bits<=32;divide_video<=1;state<=SEEK_DIVIDE;
     end else begin seek_pending<=0;state<=SCHEDULE;end
    end
    SEEK_VIDEO:begin
     work_index<=(divide_q<header[6])?divide_q:(header[6]-1'b1);
     video_target<=play_base-divide_r;seek_pending<=0;state<=SCHEDULE;
    end
    SCHEDULE:begin
     if(cue_seeking && cue_index>=cue_count)begin
      cue_seeking<=0;lyric_valid<=seek_cue_valid;lyric_toggle<=~lyric_toggle;
     end
     if(need_track)begin logical_lba<=header[21]+{22'd0,track_id};mode<=TRACK;state<=REQUEST;end
     else if(audio_started && audio_done_sync2==audio_start_toggle && audio_remaining==0)begin
      if(extended && active_media==0)begin
       state<=DRAIN;restart_settle<=31;audio_flush_toggle<=~audio_flush_toggle;audio_started<=0;
       lyric_valid<=0;lyric_toggle<=~lyric_toggle;cue_pending<=0;cue_copy_busy<=0;
       seek_pending<=0;
      end else begin
       audio_remaining<=track_samples;audio_lba<=track_start;audio_pushed<=0;audio_started<=0;
       cue_index<=0;cue_previous<=0;cue_pending<=0;cue_copy_busy<=0;lyric_valid<=0;lyric_toggle<=~lyric_toggle;
       play_base<=0;audio_skip<=0;cue_seeking<=0;seek_cue_valid<=0;
      end
     end else if(track_ready && audio_remaining!=0 && audio_write_level<AUDIO_LOW_WATER)begin
      logical_lba<=audio_lba;mode<=AUDIO;state<=REQUEST;
     end else if(track_ready && extended && !cue_pending && cue_index<cue_count)begin
      logical_lba<=cue_lba+{19'd0,cue_index};mode<=CUE;state<=REQUEST;
     end else if(track_ready && need_descriptor && !publish_pending)begin
      logical_lba<=((active_media==0)?32'd1:header[10])+{12'd0,work_index};
      mode<=DESC;need_descriptor<=0;state<=REQUEST;
     end else if(image_active && image_remaining!=0 && scale_ready)begin
      logical_lba<=image_lba;mode<=PIXEL;state<=REQUEST;
     end else if(image_active && image_remaining==0 && image_scaled)begin
      if(!(FILE_IO && native_raw) && ~image_crc!=descriptor[7])fail(8'h05);
      else begin image_prepared<=1;image_active<=0;end
     end else if(image_prepared && !publish_pending &&
       (!have_display || (!paused && ((extended && active_media==0)?
          (audio_started && playhead_ready && absolute_position>=video_target):(hold_count>=hold_cycles)))))state<=PUBLISH;
    end
    PUBLISH:begin publish_toggle<=~publish_toggle;publish_pending<=1;image_prepared<=0;state<=SCHEDULE;end
    AUDIO_WAIT:state<=AUDIO_LOAD;                                            
    AUDIO_LOAD:begin emit_data<=audio_stage_data;state<=AUDIO_PUSH;end
    AUDIO_PUSH:if(audio_ready)begin
     audio_pushed<=audio_pushed+1'b1;
     if(emit_index+1>=emit_count)begin
      audio_remaining<=audio_remaining-emit_count;audio_lba<=audio_lba+1'b1;audio_skip<=0;state<=SCHEDULE;
     end else begin emit_index<=emit_index+1'b1;state<=AUDIO_WAIT;end
    end
    FAILED:begin end
    default:fail(8'hff);
   endcase
  end
 end
endmodule

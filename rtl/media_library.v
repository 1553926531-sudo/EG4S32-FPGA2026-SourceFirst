`timescale 1ns/1ps
module media_library #(parameter CYCLES_PER_MS=50000,DEST_WIDTH=1280,DEST_HEIGHT=800,
 AUDIO_PREFILL=1024,AUDIO_LOW_WATER=1536)(
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
 output wire [9:0] video_count,output wire [9:0] image_count,output wire [9:0] music_count,
 output wire [639:0] lyric_text,output wire lyric_valid,output wire lyric_toggle,
 output wire [1:0] actual_media,output wire [9:0] actual_index,
 output reg library_ready,output reg legacy_library,
 input wire name_clk,input wire name_reset_n,input wire [11:0] name_id,input wire [4:0] name_char,output wire [7:0] name_code
);
 localparam MOUNT=0,PROBE=1,PROBE_WAIT=2,IDLE=3,DRAIN=4,PREPARE=5,PREPARE_WAIT=6,PLAY=7,ERROR=8;
 reg [3:0] config_state;
 reg [1:0] selected_kind;
 reg [9:0] selected_index;
 reg pending_open,prepare,engine_restart;
 wire storage_legacy;
 reg [31:0] carousel_count;
 wire mounted;
 wire [9:0] videos,images,songs;
 wire [7:0] adapter_error;
 wire prepared,raw_media;
 wire [31:0] file_sectors;
 wire engine_req,engine_accept,engine_valid,engine_ready,engine_done,engine_read_error;
 wire [31:0] engine_lba,engine_data;
 wire [5:0] engine_state;
 wire [7:0] engine_error;
 wire engine_idle,display_ready;
 wire [1:0] engine_media;
 wire [9:0] engine_index;
 wire [31:0] engine_position,engine_duration;
 wire [8:0] selected_file=legacy_library?9'd511:{selected_kind,selected_index[6:0]};
 wire [9:0] desired_count=(media_select==0)?video_count:(media_select==1)?image_count:music_count;
 wire selection_valid=media_select<3 && media_index<desired_count;
 wire [7:0] real_name;
 reg [7:0] legacy_name;
 (* async_reg="true" *) reg name_legacy_sync1,name_legacy_sync2;
 reg [4:0] name_position;
 reg [11:0] name_seen;
 reg [22:0] name_decimal,name_adjusted;
 reg [11:0] name_digits;
 reg [3:0] name_bits;
 integer digit;
 reg [1:0] name_kind;
 assign video_count=library_ready?videos:10'd0;
 assign image_count=library_ready?images:10'd0;
 assign music_count=library_ready?songs:10'd0;
 assign actual_media=legacy_library?engine_media:selected_kind;
 assign actual_index=legacy_library?engine_index:selected_index;
 assign playback_position=config_state==PLAY?engine_position:32'd0;
 assign playback_duration=config_state==PLAY?engine_duration:32'd0;
 assign state=engine_state;
 assign error_code=adapter_error!=0?adapter_error:engine_error;
 assign name_code=name_legacy_sync2?legacy_name:real_name;
                                                                          
                                                                           
                                                                          
 always @*begin
  name_adjusted=name_decimal;
  for(digit=0;digit<3;digit=digit+1)
   if(name_decimal[11+4*digit+:4]>=5)
    name_adjusted[11+4*digit+:4]=name_decimal[11+4*digit+:4]+4'd3;
 end
 always @(posedge name_clk)begin
  if(!name_reset_n)begin
   name_legacy_sync1<=0;name_legacy_sync2<=0;
   name_position<=0;name_kind<=0;name_seen<=12'hfff;
   name_decimal<=0;name_digits<=0;name_bits<=0;
  end else begin
   name_legacy_sync1<=legacy_library;name_legacy_sync2<=name_legacy_sync1;
   name_position<=name_char;name_kind<=name_id[11:10];
   if(name_id!=name_seen)begin
    name_seen<=name_id;name_decimal<={12'd0,({1'b0,name_id[9:0]}+11'd1)};name_bits<=11;
   end else if(name_bits!=0)begin name_decimal<=name_adjusted<<1;name_bits<=name_bits-1'b1;end
   else name_digits<=name_decimal[22:11];
  end
 end
 always @*begin
  legacy_name=32;
  case(name_position)
   0:legacy_name=(name_kind==0)?86:(name_kind==1)?73:65;
   1:legacy_name=(name_kind==0)?73:(name_kind==1)?77:85;
   2:legacy_name=(name_kind==0)?68:(name_kind==1)?65:68;
   3:legacy_name=(name_kind==0)?69:(name_kind==1)?71:73;
   4:legacy_name=(name_kind==0)?79:(name_kind==1)?69:79;
   5:legacy_name=95;
   6:legacy_name=48+name_digits[11:8];
   7:legacy_name=48+name_digits[7:4];
   8:legacy_name=48+name_digits[3:0];
   default:begin end
  endcase
 end
 media_storage storage(.clk(clk50),.reset_n(reset_n),.enable(system_ready),
  .sd_req(rd_req),.sd_lba(rd_lba),.sd_accept(rd_accept),.sd_data(rd_data),.sd_valid(rd_valid),
  .sd_ready(rd_ready),.sd_done(rd_done),.sd_error(rd_error || card_fatal),
  .mounted(mounted),.error(adapter_error),.videos(videos),.images(images),.songs(songs),
  .legacy_library(storage_legacy),.prepare(prepare),.select_file(selected_file),
  .select_kind(selected_kind),.legacy(legacy_library),.prepared(prepared),.raw_media(raw_media),.sectors(file_sectors),
  .rd_req(engine_req),.rd_lba(engine_lba),.rd_accept(engine_accept),.rd_data(engine_data),
  .rd_valid(engine_valid),.rd_ready(engine_ready),.rd_done(engine_done),.rd_error(engine_read_error),
  .name_clk(name_clk),.name_reset_n(name_reset_n),.name_id({name_id[11:10],name_id[6:0]}),.name_char(name_char),.name_code(real_name));
 media_sequencer_v2 #(.CYCLES_PER_MS(CYCLES_PER_MS),.DEST_WIDTH(DEST_WIDTH),.DEST_HEIGHT(DEST_HEIGHT),
  .FILE_IO(1),.BLANK_BOOT(1),.AUDIO_PREFILL(AUDIO_PREFILL),.AUDIO_LOW_WATER(AUDIO_LOW_WATER)) engine(
  .clk50(clk50),.reset_n(reset_n),.system_ready(system_ready),.external_fault(external_fault),
  .play_enabled(config_state==PLAY),.native_raw(raw_media),.file_sectors(file_sectors),
  .idle_ready(engine_idle),.display_ready(display_ready),
  .rd_req(engine_req),.rd_lba(engine_lba),.rd_accept(engine_accept),.rd_data(engine_data),
  .rd_valid(engine_valid),.rd_ready(engine_ready),.rd_done(engine_done),
  .rd_error(engine_read_error),.card_fatal(card_fatal),
  .wr_address(wr_address),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
  .publish_toggle(publish_toggle),.publish_bank(publish_bank),.commit_toggle(commit_toggle),
  .audio_start_toggle(audio_start_toggle),.audio_flush_toggle(audio_flush_toggle),
  .audio_total_samples(audio_total_samples),.audio_done_toggle(audio_done_toggle),
  .audio_write_level(audio_write_level),.audio_data(audio_data),.audio_valid(audio_valid),.audio_ready(audio_ready),
  .state(engine_state),.error_code(engine_error),.logical_lba(logical_lba),.frame_number(frame_number),.frame_word(frame_word),
  .pause(pause),.restart(engine_restart),.media_select(selected_kind),.media_index(legacy_library?selected_index:10'd0),
  .scale_mode(scale_mode),.audio_position(audio_position),.audio_position_epoch(audio_position_epoch),
  .seek_request(seek_request && config_state==PLAY),.seek_seconds(seek_seconds),
  .playback_position(engine_position),.playback_duration(engine_duration),
  .video_count(),.image_count(),.music_count(),.lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
  .actual_media(engine_media),.actual_index(engine_index));
 always @(posedge clk50)begin
  if(!reset_n)begin
   config_state<=MOUNT;selected_kind<=0;selected_index<=0;pending_open<=0;prepare<=0;engine_restart<=0;
   library_ready<=0;legacy_library<=0;carousel_count<=0;
  end else begin
   prepare<=0;engine_restart<=0;
   if(restart && library_ready && selection_valid)begin
    selected_kind<=media_select;selected_index<=media_index;pending_open<=1;carousel_count<=0;
    engine_restart<=1;
    if(config_state==IDLE || config_state==PLAY || config_state==ERROR)config_state<=DRAIN;
   end else case(config_state)
    MOUNT:if(mounted)begin
     library_ready<=1;legacy_library<=storage_legacy;config_state<=IDLE;
    end
    IDLE:begin end
    DRAIN:if(engine_idle && !engine_restart)config_state<=PREPARE;
    PREPARE:begin prepare<=1;pending_open<=0;config_state<=PREPARE_WAIT;end
    PREPARE_WAIT:if(!prepare)begin
     if(adapter_error!=0)begin
      if(pending_open)begin engine_restart<=1;config_state<=DRAIN;end
      else config_state<=ERROR;
     end
     else if(prepared)begin
      if(pending_open)begin engine_restart<=1;config_state<=DRAIN;end
      else config_state<=PLAY;
     end
    end
    PLAY:begin
     if(!legacy_library && selected_kind==1 && images>1 && display_ready && !pause)begin
      if(carousel_count>=5000*CYCLES_PER_MS-1)begin
       selected_index<=(selected_index+10'd1>=images)?10'd0:selected_index+1'b1;
       carousel_count<=0;engine_restart<=1;config_state<=DRAIN;
      end else carousel_count<=carousel_count+1'b1;
     end
    end
    ERROR:begin end
    default:config_state<=ERROR;
   endcase
  end
 end
endmodule

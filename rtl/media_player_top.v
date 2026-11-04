`timescale 1ns/1ps
                                                                         
                                                                               
module media_player_top(input wire clk50, output wire uart_tx,
 output wire sd_clk,inout wire sd_cmd,inout wire [3:0] sd_dat,
 inout wire hdmi_scl,inout wire hdmi_sda,output wire [23:0] hdmi_d,
 output wire hdmi_clk,output wire hdmi_de,output wire hdmi_hs,output wire hdmi_vs,
 output wire hdmi_nreset,input wire hdmi_int,
 output wire i2s_mclk,output wire i2s_sdata,output wire i2s_lrclk,output wire i2s_bclk,
 input wire [3:0] key_col_n,output wire [3:0] key_row_n,
 input wire [7:0] switches,output wire [7:0] led,
 output wire [7:0] Digitron_Out,output wire [3:0] DigitronCS_Out);
                                                                        
                                                                          
 assign Digitron_Out=8'h00;
 assign DigitronCS_Out=4'hf;
 reg [23:0] power_count=0;
 always @(posedge clk50)if(power_count<16000000)power_count<=power_count+1'b1;
 wire pll_reset=(power_count<1024);
 wire pixel_clock_hz,audio_clock_hz,pixel_locked,audio_locked,unused_phase_clock;
 pixel_pll pixel_clock(.refclk(clk50),.reset(pll_reset),.pixel_clk(pixel_clock_hz),
  .hdmi_clk(unused_phase_clock),.locked(pixel_locked));
 audio_pll audio_clock(.refclk(clk50),.reset(pll_reset),.mclk(audio_clock_hz),.locked(audio_locked));
                                                                             
                                                                                 
 assign hdmi_clk=pixel_clock_hz;
 assign i2s_mclk=audio_clock_hz;
 assign hdmi_nreset=(power_count>=10000000);
                                                                            
                                                                            
                                                                             
                                                              
 (* async_reg="true" *) reg pixel_lock_sync1,pixel_lock_sync2;
 (* async_reg="true" *) reg audio_lock_sync1,audio_lock_sync2;
 always @(posedge clk50) begin
  if (!hdmi_nreset) begin
   pixel_lock_sync1 <= 1'b0;
   pixel_lock_sync2 <= 1'b0;
   audio_lock_sync1 <= 1'b0;
   audio_lock_sync2 <= 1'b0;
  end else begin
   pixel_lock_sync1 <= pixel_locked;
   pixel_lock_sync2 <= pixel_lock_sync1;
   audio_lock_sync1 <= audio_locked;
   audio_lock_sync2 <= audio_lock_sync1;
  end
 end
 wire control_ready = hdmi_nreset && pixel_lock_sync2 && audio_lock_sync2;
 wire reset50_n,resetp_n,reseta_n;
 reset_release r50(.clk(clk50),.async_reset_n(control_ready),.reset_n(reset50_n));
 reset_release rp(.clk(pixel_clock_hz),.async_reset_n(pixel_locked),.reset_n(resetp_n));
 reset_release ra(.clk(audio_clock_hz),.async_reset_n(audio_locked),.reset_n(reseta_n));
 wire [1:0] ui_media_select;
  wire [9:0] ui_media_index;
 wire ui_paused,ui_has_opened;
 wire [7:0] ui_brightness,ui_contrast;
 wire [1:0] ui_zoom_mode;
 wire ui_waveform_enable,ui_subtitle_enable,ui_overlay_enable;
 wire [1:0] ui_transition_mode;
 wire ui_restart_pulse;
 wire [7:0] ui_switch_state,ui_led_state;
 wire [9:0] media_video_count,media_image_count,media_actual_index;
 wire [9:0] media_music_count;
 wire [1:0] media_actual_select;
 wire ui_seek_request;
 wire [15:0] ui_seek_seconds;
 wire [31:0] media_position,media_duration;
 wire [1:0] ui_page,ui_seek_step;
 wire [10:0] ui_cursor,ui_progress,ui_library_count;
 wire [23:0] ui_play_time,ui_total_time,ui_target_time;
 wire [4:0] ui_volume;wire ui_muted;
 media_ui_ctrl #(.START_BROWSER(1)) ui(.clk(clk50),.rst_n(reset50_n),.key_col_n(key_col_n),.switches(switches),
  .key_row_n(key_row_n),
  .media_select(ui_media_select),.media_index(ui_media_index),.paused(ui_paused),.has_opened(ui_has_opened),
  .brightness(ui_brightness),.contrast(ui_contrast),.zoom_mode(ui_zoom_mode),
  .waveform_enable(ui_waveform_enable),.subtitle_enable(ui_subtitle_enable),
  .overlay_enable(ui_overlay_enable),.transition_mode(ui_transition_mode),
  .restart_pulse(ui_restart_pulse),.switch_state(ui_switch_state),.led_state(ui_led_state),
  .video_count(media_video_count),.image_count(media_image_count),.music_count(media_music_count),
  .actual_media(media_actual_select),.actual_index(media_actual_index),
  .playback_position(media_position),.playback_duration(media_duration),
  .seek_request(ui_seek_request),.seek_seconds(ui_seek_seconds),
  .ui_page(ui_page),.browser_cursor(ui_cursor),.seek_step(ui_seek_step),.volume(ui_volume),.muted(ui_muted),
  .play_seconds(),.total_seconds(),.progress_mark(ui_progress),.library_count(ui_library_count),
  .play_time(ui_play_time),.total_time(ui_total_time),.target_time(ui_target_time));
 wire [9:0] lut_index;
 wire [31:0] lut_data;
 wire i2c_error,i2c_done;
 wire [7:0] i2c_error_count;
 media_hdmi_lut lut(.index(lut_index),.data(lut_data));
 sii9134_i2c_writer hdmi_init(.rst(!reset50_n || power_count<15000000),.clk(clk50),
  .clk_div_cnt(16'd125),.i2c_addr_2byte(1'b0),.lut_index(lut_index),
  .lut_dev_addr(lut_data[31:24]),.lut_reg_addr(lut_data[23:8]),.lut_reg_data(lut_data[7:0]),
  .error(i2c_error),.error_count(i2c_error_count),.done(i2c_done),
  .i2c_scl(hdmi_scl),.i2c_sda(hdmi_sda));
 wire rd_req,rd_accept,rd_valid,rd_ready,rd_done,rd_error,card_ready,card_fatal;
 wire [31:0] rd_lba,rd_data;
 wire sd_uart_unused;
 tf_native_media_reader card(.clk50(clk50),.reset_n(reset50_n),.uart_tx(sd_uart_unused),
  .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.initialized(card_ready),.fatal(card_fatal),
  .sd_clk(sd_clk),.sd_cmd(sd_cmd),.sd_dat(sd_dat));
 wire [20:0] wr_address;
 wire [31:0] wr_data,pixel_data;
 wire wr_valid,wr_ready,publish_toggle,publish_bank,commit_toggle,display_valid;
 wire [13:0] pixel_level;
 wire pixel_valid,pixel_ready,memory_initialized,memory_fault,video_underrun;
 frame_store frames(.clk50(clk50),.reset50_n(reset50_n),.wr_address(wr_address),.wr_data(wr_data),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.publish_toggle(publish_toggle),.publish_bank(publish_bank),
  .commit_toggle(commit_toggle),.pclk(pixel_clock_hz),.resetp_n(resetp_n),
  .pixel_data(pixel_data),.pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_level(pixel_level),
  .display_valid(display_valid),.memory_initialized(memory_initialized),.fault(memory_fault));
 wire [31:0] audio_input,audio_output,audio_samples;
 wire [31:0] audio_playhead_gray;
 wire audio_playhead_epoch;
 (* keep = "true" *) (* async_reg="true" *) reg playhead_epoch_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg playhead_epoch_s2;                 
 reg playhead_epoch_s3;
 (* keep = "true" *) (* async_reg="true" *) reg [31:0] playhead_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg [31:0] playhead_s2;                 
 reg [31:0] audio_playhead;
 function [31:0] gray_decode;
  input [31:0] value;integer n;
  begin gray_decode[31]=value[31];for(n=30;n>=0;n=n-1)gray_decode[n]=gray_decode[n+1]^value[n];end
 endfunction
 always @(posedge clk50)begin
  if(!reset50_n)begin
   playhead_sync1<=0;playhead_s2<=0;audio_playhead<=0;
   playhead_epoch_sync1<=0;playhead_epoch_s2<=0;playhead_epoch_s3<=0;
  end else begin
   playhead_sync1<=audio_playhead_gray;playhead_s2<=playhead_sync1;audio_playhead<=gray_decode(playhead_s2);
   playhead_epoch_sync1<=audio_playhead_epoch;playhead_epoch_s2<=playhead_epoch_sync1;playhead_epoch_s3<=playhead_epoch_s2;
  end
 end
 wire audio_in_valid,audio_in_ready,audio_out_valid,audio_out_ready;
 wire [11:0] audio_wlevel,audio_rlevel;
  wire audio_start_toggle,audio_flush_toggle,audio_done_toggle,audio_underrun;
 (* async_reg="true" *) reg pause_audio_sync1,pause_audio_sync2;
 async_stream_fifo #(.WIDTH(32),.AW(11)) sound_queue(
  .wclk(clk50),.wrst_n(reset50_n),.in_data(audio_input),.in_valid(audio_in_valid),
  .in_ready(audio_in_ready),.write_level(audio_wlevel),.rclk(audio_clock_hz),.rrst_n(reseta_n),
   .out_data(audio_output),.out_valid(audio_out_valid),.out_ready(audio_out_ready),.read_level(audio_rlevel),
   .flush_toggle(audio_flush_toggle));
 wire [4:0] audio_volume;wire audio_muted;
 media_ui_snapshot #(.WIDTH(6)) audio_volume_snapshot(.src_clk(clk50),.src_reset_n(reset50_n),
  .source({ui_muted,ui_volume}),.dst_clk(audio_clock_hz),.dst_reset_n(reseta_n),.value({audio_muted,audio_volume}));
 i2s_player #(.VOLUME_CONTROL(1)) sound(.mclk(audio_clock_hz),.reset_n(reseta_n),.start_toggle(audio_start_toggle),
  .volume(audio_volume),.muted(audio_muted),
  .total_samples(audio_samples),.done_toggle(audio_done_toggle),.underrun(audio_underrun),
   .sample_data(audio_output),.sample_valid(audio_out_valid),.sample_ready(audio_out_ready),
    .bclk(i2s_bclk),.lrclk(i2s_lrclk),.sdata(i2s_sdata),.pause(pause_audio_sync2),
    .flush_toggle(audio_flush_toggle),.playhead_gray(audio_playhead_gray),.playhead_epoch(audio_playhead_epoch));
 function [15:0] abs_pcm16;
  input [15:0] value;
  begin abs_pcm16=value[15] ? (~value + 1'b1) : value; end
 endfunction
 reg [15:0] audio_level_audio;
 reg [15:0] visual_pcm;
 reg visual_sample_toggle;
 reg [1:0] visual_divide;
 reg signed [17:0] visual_sum;
 wire signed [17:0] visual_sum_next=visual_sum+$signed({{2{audio_output[15]}},audio_output[15:0]});
 (* async_reg="true" *) reg visual_flush_s1,visual_flush_s2;
 reg visual_flush_seen;
 always @(posedge audio_clock_hz) begin
  if(!reseta_n) begin
   pause_audio_sync1<=0; pause_audio_sync2<=0; audio_level_audio<=0;
   visual_pcm<=0;visual_sample_toggle<=0;visual_divide<=0;visual_sum<=0;
   visual_flush_s1<=0;visual_flush_s2<=0;visual_flush_seen<=0;
  end else begin
   pause_audio_sync1<=ui_paused;
   pause_audio_sync2<=pause_audio_sync1;
   visual_flush_s1<=audio_flush_toggle;visual_flush_s2<=visual_flush_s1;
   if(pause_audio_sync2) audio_level_audio<=0;
   else if(audio_out_valid && audio_out_ready)
   audio_level_audio <= (abs_pcm16(audio_output[15:0]) > abs_pcm16(audio_output[31:16])) ?
                        abs_pcm16(audio_output[15:0]) : abs_pcm16(audio_output[31:16]);
   if(visual_flush_s2!=visual_flush_seen)begin
    visual_flush_seen<=visual_flush_s2;visual_divide<=0;visual_sum<=0;audio_level_audio<=0;
   end else if(audio_out_valid && audio_out_ready)begin
                                                                         
    if(visual_divide==3)begin
     visual_pcm<=visual_sum_next[17:2];visual_sample_toggle<=~visual_sample_toggle;
     visual_sum<=0;visual_divide<=0;
    end else begin visual_sum<=visual_sum_next;visual_divide<=visual_divide+1'b1;end
   end
  end
 end
 (* async_reg="true" *) reg [15:0] audio_level_p1,audio_level_p2;
 always @(posedge pixel_clock_hz) begin
  if(!resetp_n) begin audio_level_p1<=0;audio_level_p2<=0;end
  else begin audio_level_p1<=audio_level_audio;audio_level_p2<=audio_level_p1;end
 end
 (* async_reg="true" *) reg memory_init_sync1,memory_init_sync2;
 (* async_reg="true" *) reg memory_fault_sync1,memory_fault_sync2;
 (* async_reg="true" *) reg video_fault_sync1,video_fault_sync2;
 (* async_reg="true" *) reg audio_fault_sync1,audio_fault_sync2;
 wire [5:0] state;
 wire [7:0] error_code;
 wire [31:0] logical_lba,frame_number;
 wire [19:0] frame_word;
 wire [639:0] lyric_text;
 wire lyric_valid,lyric_toggle;
 wire global_fault=(i2c_error_count!=0)||memory_fault_sync2||video_fault_sync2||audio_fault_sync2;
 always @(posedge clk50)begin
  if(!reset50_n)begin
   memory_init_sync1<=0;memory_init_sync2<=0;memory_fault_sync1<=0;memory_fault_sync2<=0;
   video_fault_sync1<=0;video_fault_sync2<=0;audio_fault_sync1<=0;audio_fault_sync2<=0;
  end else begin
   memory_init_sync1<=memory_initialized;memory_init_sync2<=memory_init_sync1;
   memory_fault_sync1<=memory_fault;memory_fault_sync2<=memory_fault_sync1;
   video_fault_sync1<=video_underrun;video_fault_sync2<=video_fault_sync1;
   audio_fault_sync1<=audio_underrun;audio_fault_sync2<=audio_fault_sync1;
  end
 end
                                                                           
                                                                                  
 wire library_ready,legacy_library;
 wire [11:0] name_id;wire [4:0] name_char;wire [7:0] name_code;
 media_library media(.clk50(clk50),.reset_n(reset50_n),
  .system_ready(i2c_done && card_ready && memory_init_sync2),.external_fault(global_fault),
  .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.card_fatal(card_fatal),
  .wr_address(wr_address),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
  .publish_toggle(publish_toggle),.publish_bank(publish_bank),.commit_toggle(commit_toggle),
  .audio_start_toggle(audio_start_toggle),.audio_flush_toggle(audio_flush_toggle),
  .audio_total_samples(audio_samples),.audio_done_toggle(audio_done_toggle),
  .audio_write_level({1'b0,audio_wlevel}),.audio_data(audio_input),.audio_valid(audio_in_valid),.audio_ready(audio_in_ready),
  .state(state),.error_code(error_code),.logical_lba(logical_lba),.frame_number(frame_number),.frame_word(frame_word),
  .pause(ui_paused),.restart(ui_restart_pulse),.media_select(ui_media_select),.media_index(ui_media_index),
  .scale_mode(ui_zoom_mode),.audio_position(audio_playhead),.audio_position_epoch(playhead_epoch_s3),
  .seek_request(ui_seek_request),.seek_seconds(ui_seek_seconds),
  .playback_position(media_position),.playback_duration(media_duration),
  .video_count(media_video_count),.image_count(media_image_count),.music_count(media_music_count),
  .lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
  .actual_media(media_actual_select),.actual_index(media_actual_index),
  .library_ready(library_ready),.legacy_library(legacy_library),
  .name_clk(pixel_clock_hz),.name_reset_n(resetp_n),.name_id(name_id),.name_char(name_char),.name_code(name_code));
 (* async_reg="true" *) reg fatal_sync1,fatal_sync2,enable_sync1,enable_sync2;
 (* async_reg="true" *) reg memory_fault_p1,memory_fault_p2;
 (* async_reg="true" *) reg [7:0] brightness_p1,brightness_p2,contrast_p1,contrast_p2;
 (* async_reg="true" *) reg [1:0] zoom_p1,zoom_p2,transition_p1,transition_p2,media_select_p1,media_select_p2;
 (* async_reg="true" *) reg waveform_p1,waveform_p2,subtitle_p1,subtitle_p2,overlay_p1,overlay_p2,paused_p1,paused_p2;
  (* async_reg="true" *) reg [9:0] media_index_p1,media_index_p2;
 wire [1:0] page_sync2,step_sync2;
 wire library_ready_p,has_opened_p;
 wire [7:0] media_error_p;
 wire [10:0] cursor_sync2,progress_sync2,count_sync2;
 wire [9:0] videos_sync2,images_sync2;
 wire [23:0] time_sync2,length_sync2,target_sync2;
 wire [4:0] volume_p;wire muted_p;
 media_ui_snapshot #(.WIDTH(145)) ui_snapshot(.src_clk(clk50),.src_reset_n(reset50_n),
  .source({ui_muted,ui_volume,error_code,library_ready,ui_has_opened,ui_page,ui_seek_step,ui_cursor,ui_progress,ui_library_count,
           media_video_count,media_image_count,ui_play_time,ui_total_time,ui_target_time}),
  .dst_clk(pixel_clock_hz),.dst_reset_n(resetp_n),
  .value({muted_p,volume_p,media_error_p,library_ready_p,has_opened_p,page_sync2,step_sync2,cursor_sync2,progress_sync2,count_sync2,
          videos_sync2,images_sync2,time_sync2,length_sync2,target_sync2}));
 always @(posedge pixel_clock_hz)begin
  if(!resetp_n)begin
   fatal_sync1<=0;fatal_sync2<=0;enable_sync1<=0;enable_sync2<=0;memory_fault_p1<=0;memory_fault_p2<=0;
   brightness_p1<=8'd128;brightness_p2<=8'd128;contrast_p1<=8'd128;contrast_p2<=8'd128;
   zoom_p1<=0;zoom_p2<=0;transition_p1<=0;transition_p2<=0;media_select_p1<=0;media_select_p2<=0;
   waveform_p1<=0;waveform_p2<=0;subtitle_p1<=0;subtitle_p2<=0;overlay_p1<=0;overlay_p2<=0;
   paused_p1<=0;paused_p2<=0;media_index_p1<=0;media_index_p2<=0;
  end else begin
   fatal_sync1<=global_fault || card_fatal;fatal_sync2<=fatal_sync1;
   enable_sync1<=i2c_done;enable_sync2<=enable_sync1;
   memory_fault_p1<=memory_fault;memory_fault_p2<=memory_fault_p1;
   brightness_p1<=ui_brightness;brightness_p2<=brightness_p1;
   contrast_p1<=ui_contrast;contrast_p2<=contrast_p1;
   zoom_p1<=ui_zoom_mode;zoom_p2<=zoom_p1;
   transition_p1<=ui_transition_mode;transition_p2<=transition_p1;
   media_select_p1<=media_actual_select;media_select_p2<=media_select_p1;
   waveform_p1<=ui_waveform_enable;waveform_p2<=waveform_p1;
   subtitle_p1<=ui_subtitle_enable;subtitle_p2<=subtitle_p1;
   overlay_p1<=ui_overlay_enable;overlay_p2<=overlay_p1;
   paused_p1<=ui_paused;paused_p2<=paused_p1;
   media_index_p1<=media_actual_index;media_index_p2<=media_index_p1;
  end
 end
 video_scan_enhanced #(.PLAYER_UI(1)) scan(.pclk(pixel_clock_hz),.reset_n(resetp_n),.enable(enable_sync2),
  .fatal(fatal_sync2 || memory_fault_p2),.pixel_data(pixel_data),.pixel_valid(pixel_valid),.pixel_level(pixel_level),
  .pixel_ready(pixel_ready),.underrun(video_underrun),.brightness(brightness_p2),.contrast(contrast_p2),
  .zoom_mode(zoom_p2),.waveform_enable(waveform_p2),.subtitle_enable(subtitle_p2),
  .overlay_enable(overlay_p2),.transition_mode(media_select_p2==0?2'd0:transition_p2),.paused(paused_p2),
  .lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
  .media_select(media_select_p2),.media_index(media_index_p2),.audio_level(audio_level_p2),
  .audio_pcm(visual_pcm),.audio_sample_toggle(visual_sample_toggle),
  .audio_flush_toggle(audio_flush_toggle),.frame_commit_toggle(commit_toggle),
  .ui_page(page_sync2),.browser_cursor(cursor_sync2),.library_count(count_sync2),
  .library_ready(library_ready_p),.has_opened(has_opened_p),
  .name_id(name_id),.name_char(name_char),.name_code(name_code),.media_error(media_error_p),
  .video_count(videos_sync2),.image_count(images_sync2),.play_time(time_sync2),.total_time(length_sync2),
  .target_time(target_sync2),.progress_mark(progress_sync2),.seek_step(step_sync2),.volume(volume_p),.muted(muted_p),
  .rgb(hdmi_d),.de(hdmi_de),.hs(hdmi_hs),.vs(hdmi_vs));
 assign led = ui_led_state | {7'b0,global_fault};
 status_uart status(.clk50(clk50),.reset_n(reset50_n),.state(state),.error_code(error_code),
  .flags({audio_fault_sync2,video_fault_sync2,memory_fault_sync2,memory_init_sync2,
          card_ready,i2c_done,audio_locked,pixel_locked}),
  .lba(logical_lba),.frame_word(frame_word),.tx(uart_tx));
endmodule


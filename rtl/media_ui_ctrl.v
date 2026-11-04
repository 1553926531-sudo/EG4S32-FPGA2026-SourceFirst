`timescale 1ns/1ps
                                                                           
                                                                             
module media_ui_ctrl #(
 parameter integer CLK_HZ=50000000,KEY_SCAN_HZ=1000,DEBOUNCE_SCANS=10,START_BROWSER=0
)(
 input wire clk,input wire rst_n,input wire [3:0] key_col_n,input wire [7:0] switches,
 output reg [3:0] key_row_n,output reg [1:0] media_select,output reg [9:0] media_index,
 output wire paused,output reg has_opened,output reg [7:0] brightness,output reg [7:0] contrast,
 output reg [1:0] zoom_mode,output reg waveform_enable,output reg subtitle_enable,
 output reg overlay_enable,output reg [1:0] transition_mode,output reg restart_pulse,
 output wire [7:0] switch_state,output wire [7:0] led_state,
 input wire [9:0] video_count,input wire [9:0] image_count,input wire [9:0] music_count,
 input wire [1:0] actual_media,input wire [9:0] actual_index,
 input wire [31:0] playback_position,input wire [31:0] playback_duration,
 output reg seek_request,output reg [15:0] seek_seconds,
 output reg [1:0] ui_page,output reg [10:0] browser_cursor,
 output reg [1:0] seek_step,output reg [4:0] volume,output reg muted,
 output wire [15:0] play_seconds,output wire [15:0] total_seconds,
 output wire [10:0] progress_mark,output wire [10:0] library_count,
 output wire [23:0] play_time,output wire [23:0] total_time,output wire [23:0] target_time
);
 localparam integer ROW_DIV=(CLK_HZ/(KEY_SCAN_HZ*4)<1)?1:CLK_HZ/(KEY_SCAN_HZ*4);
 localparam integer REPEAT_DELAY=(KEY_SCAN_HZ/2<1)?1:KEY_SCAN_HZ/2;
 localparam integer REPEAT_RATE=(KEY_SCAN_HZ/12<1)?1:KEY_SCAN_HZ/12;
 localparam integer ROW_BITS=(ROW_DIV<2)?1:$clog2(ROW_DIV);
 localparam integer REPEAT_BITS=(REPEAT_DELAY<2)?1:$clog2(REPEAT_DELAY+1);
 localparam integer DEBOUNCE_BITS=(DEBOUNCE_SCANS<2)?1:$clog2(DEBOUNCE_SCANS+1);
 reg [1:0] row_index;reg [ROW_BITS-1:0] row_div_count;
 (* async_reg="true" *) reg [3:0] col_meta,col_sync;
 (* async_reg="true" *) reg [7:0] sw_meta,sw_sync;
 reg [7:0] sw_stable,sw_candidate,sw_seen;
 reg [DEBOUNCE_BITS-1:0] sw_count;
 reg [15:0] raw_keys,previous_sample,stable_keys,stable_keys_d;
 reg [DEBOUNCE_BITS-1:0] stable_scan_count;
 reg [REPEAT_BITS-1:0] repeat_count;reg repeating;reg [15:0] repeat_pulse;
 reg key_paused,selection_pending;
 reg [REPEAT_BITS-1:0] volume_hold_count;
 reg volume_armed,volume_held;
 reg [1:0] volume_return_page;
 reg volume_open_pulse,volume_mute_pulse;
 reg [1:0] zoom_previous;
                                                                             
                                                               
 reg [9:0] videos,images,songs;
 always @(posedge clk)begin
  if(!rst_n)begin videos<=0;images<=0;songs<=0;end
  else begin
   videos<=((^video_count!==1'bx)&&video_count<=600)?video_count:10'd0;
   images<=((^image_count!==1'bx)&&image_count<=600)?image_count:10'd0;
   songs<=((^music_count!==1'bx)&&music_count<=600)?music_count:10'd0;
  end
 end
 wire [10:0] image_end={1'b0,videos}+{1'b0,images};
 assign library_count=image_end+{1'b0,songs};
 wire actual_known=(^actual_index!==1'bx)&&actual_media<3;
 wire [1:0] base_media=(!selection_pending&&actual_known)?actual_media:media_select;
 wire [9:0] base_index=(!selection_pending&&actual_known)?actual_index:media_index;
 wire [9:0] base_count=(base_media==0)?videos:(base_media==1)?images:songs;
 wire [10:0] base_global=(base_media==0)?{1'b0,base_index}:
                              (base_media==1)?({1'b0,videos}+{1'b0,base_index}):(image_end+{1'b0,base_index});
 wire single_key=stable_keys!=0 && (stable_keys&(stable_keys-16'd1))==0;
 wire [15:0] key_press=single_key?(stable_keys&~stable_keys_d&16'h7fff):16'd0;
 wire [15:0] action=key_press|repeat_pulse;
 wire row_tick=row_div_count==ROW_DIV-1;
 wire [15:0] scan_candidate={~col_sync,raw_keys[11:0]};
 wire [7:0] sw_change=sw_stable^sw_seen;
 wire [15:0] step_seconds=(seek_step==0)?16'd1:(seek_step==1)?16'd10:16'd60;
 wire [16:0] seek_sum={1'b0,seek_seconds}+{1'b0,step_seconds};
 wire [15:0] max_seek=(total_seconds==0)?16'd0:total_seconds-1'b1;
 assign paused=key_paused || ui_page==2 || (ui_page==3 && volume_return_page==2) || !has_opened;
 assign switch_state=sw_stable;
 assign led_state={ui_page!=0,transition_mode!=0,zoom_mode!=0,overlay_enable,
                   subtitle_enable,waveform_enable,paused,restart_pulse|seek_request};
 media_ui_timeline clock_display(.clk(clk),.rst_n(rst_n),.position(playback_position),
  .duration(playback_duration),.preview(ui_page==2 || (ui_page==3 && volume_return_page==2)),.target(seek_seconds),
  .seconds(play_seconds),.length(total_seconds),.mark(progress_mark));
 media_ui_times times(.clk(clk),.rst_n(rst_n),.play_seconds(play_seconds),
  .total_seconds(total_seconds),.target_seconds(seek_seconds),
  .play_time(play_time),.total_time(total_time),.target_time(target_time));
 always @*begin key_row_n=4'hf;key_row_n[row_index]=0;end
 task open_file;
  input [1:0] kind;input [9:0] number;
  begin
   media_select<=kind;media_index<=number;
   selection_pending<=1;restart_pulse<=1;seek_request<=0;seek_seconds<=0;
   key_paused<=0;ui_page<=0;overlay_enable<=1;has_opened<=1;
  end
 endtask
 task choose_file;
  input [10:0] ordinal;
  begin
   if(ordinal<videos)open_file(2'd0,ordinal[9:0]);
   else if(ordinal<image_end)open_file(2'd1,ordinal-videos);
   else if(ordinal<library_count)open_file(2'd2,ordinal-image_end);
  end
 endtask
 task preserve_position;
  begin
   media_select<=base_media;media_index<=base_index;selection_pending<=1;
   seek_seconds<=(play_seconds>max_seek)?max_seek:play_seconds;
   if(base_media==1)restart_pulse<=1;else seek_request<=1;
  end
 endtask
 always @(posedge clk)begin
  if(!rst_n)begin col_meta<=15;col_sync<=15;sw_meta<=0;sw_sync<=0;end
  else begin col_meta<=key_col_n;col_sync<=col_meta;sw_meta<=switches;sw_sync<=sw_meta;end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   row_div_count<=0;row_index<=0;raw_keys<=0;previous_sample<=0;stable_keys<=0;stable_keys_d<=0;stable_scan_count<=0;
   sw_stable<=0;sw_candidate<=0;sw_count<=0;sw_seen<=0;
   repeat_count<=0;repeating<=0;repeat_pulse<=0;
   volume<=16;muted<=0;volume_hold_count<=0;volume_armed<=0;volume_held<=0;
   volume_return_page<=0;volume_open_pulse<=0;volume_mute_pulse<=0;
   media_select<=0;media_index<=0;key_paused<=0;selection_pending<=0;has_opened<=!START_BROWSER;
   brightness<=128;contrast<=128;zoom_mode<=0;zoom_previous<=0;
   waveform_enable<=0;subtitle_enable<=0;overlay_enable<=1;transition_mode<=0;
   restart_pulse<=0;seek_request<=0;seek_seconds<=0;ui_page<=START_BROWSER?2'd1:2'd0;browser_cursor<=0;seek_step<=1;
  end else begin
   stable_keys_d<=stable_keys;restart_pulse<=0;seek_request<=0;repeat_pulse<=0;
   volume_open_pulse<=0;volume_mute_pulse<=0;
   if(stable_keys==16'h8000 && stable_keys_d==0)begin
    volume_armed<=1;volume_held<=0;volume_hold_count<=0;
   end
   if(selection_pending && actual_media==media_select && actual_index==media_index)selection_pending<=0;
   if(browser_cursor>=library_count)browser_cursor<=0;
   if(zoom_mode!=zoom_previous)begin
    zoom_previous<=zoom_mode;
                                                                          
                                                                          
    if(!restart_pulse && has_opened)preserve_position;
   end
   if(row_tick)begin
    row_div_count<=0;
    case(row_index)
     0:raw_keys[3:0]<=~col_sync;1:raw_keys[7:4]<=~col_sync;
     2:raw_keys[11:8]<=~col_sync;3:raw_keys[15:12]<=~col_sync;
    endcase
    if(row_index==3)begin
     if(stable_keys==16'h8000)begin
      if(volume_armed && !volume_held)begin
       if(volume_hold_count>=REPEAT_DELAY)begin volume_open_pulse<=1;volume_held<=1;end
       else volume_hold_count<=volume_hold_count+1'b1;
      end
     end else begin
      if(stable_keys==0 && volume_armed && !volume_held)volume_mute_pulse<=1;
      volume_armed<=0;volume_held<=0;volume_hold_count<=0;
     end
     if(sw_sync!=sw_candidate)begin sw_candidate<=sw_sync;sw_count<=0;end
     else if(sw_count<DEBOUNCE_SCANS)sw_count<=sw_count+1'b1;else sw_stable<=sw_candidate;
     if(scan_candidate!=previous_sample)begin previous_sample<=scan_candidate;stable_scan_count<=0;end
     else if(stable_scan_count<DEBOUNCE_SCANS)stable_scan_count<=stable_scan_count+1'b1;
     else stable_keys<=scan_candidate;
                                                                            
                                                                                    
     if(ui_page!=0 && single_key && (stable_keys==16'h0002 || stable_keys==16'h0004) && stable_keys==stable_keys_d)begin
      if(repeat_count>=((repeating)?REPEAT_RATE:REPEAT_DELAY))begin
       repeat_pulse<=stable_keys;repeat_count<=0;repeating<=1;
      end else repeat_count<=repeat_count+1'b1;
     end else begin repeat_count<=0;repeating<=0;end
    end
    row_index<=row_index+1'b1;
   end else row_div_count<=row_div_count+1'b1;
   if(volume_open_pulse)begin
    if(ui_page==3)ui_page<=volume_return_page;
    else begin volume_return_page<=ui_page;ui_page<=3;end
    overlay_enable<=1;
   end else if(volume_mute_pulse)begin
    muted<=~muted;overlay_enable<=1;
   end else if(action!=0)begin
    if(action[0])begin
     if(ui_page==1)begin if(has_opened)ui_page<=0;end
     else begin ui_page<=1;browser_cursor<=base_global;end
     overlay_enable<=1;
    end else if(action[13])begin
     if(has_opened)begin ui_page<=0;overlay_enable<=(ui_page!=0)?1'b0:~overlay_enable;end
    end else if(action[1] || action[2])begin
     if(ui_page==3)begin
      muted<=0;
      if(action[1])volume<=(volume==0)?5'd0:volume-1'b1;
      else volume<=(volume>=16)?5'd16:volume+1'b1;
     end else if(ui_page==2)begin
      if(action[1])seek_seconds<=(seek_seconds<step_seconds)?16'd0:seek_seconds-step_seconds;
      else seek_seconds<=(seek_sum>{1'b0,max_seek})?max_seek:seek_sum[15:0];
     end else if(ui_page==1 && library_count!=0)begin
      if(action[1])browser_cursor<=(browser_cursor==0)?library_count-1'b1:browser_cursor-1'b1;
      else browser_cursor<=(browser_cursor+11'd1>=library_count)?11'd0:browser_cursor+1'b1;
     end else if(ui_page==0 && library_count!=0)begin
      if(action[1])choose_file(base_global==0?library_count-11'd1:base_global-11'd1);
      else choose_file(base_global+11'd1>=library_count?11'd0:base_global+11'd1);
     end
    end else if(action[3])begin
     if(ui_page==3)muted<=~muted;
     else if(ui_page==1 && library_count!=0)choose_file(browser_cursor);
     else if(ui_page==2)begin
      media_select<=base_media;media_index<=base_index;selection_pending<=1;
      seek_request<=1;ui_page<=0;overlay_enable<=1;
     end else if(ui_page==0 && has_opened)begin key_paused<=~key_paused;overlay_enable<=1;end
    end else if(action[4])begin
     if(ui_page==3)ui_page<=volume_return_page;
     else if(ui_page==2)ui_page<=0;
     else if(ui_page==0 && total_seconds!=0)begin
      ui_page<=2;seek_seconds<=(play_seconds>max_seek)?max_seek:play_seconds;overlay_enable<=1;
     end
    end else if(action[14])begin
     if(ui_page==2)seek_step<=(seek_step==2)?2'd0:seek_step+1'b1;
     else if(ui_page==0 && has_opened)begin
      media_select<=base_media;media_index<=base_index;selection_pending<=1;
      restart_pulse<=1;seek_request<=0;seek_seconds<=0;overlay_enable<=1;
     end
    end else if(ui_page==0)begin
     overlay_enable<=1;
     if(action[5])transition_mode<=transition_mode+1'b1;
     else if(action[6])brightness<=(brightness<16)?8'd0:brightness-8'd16;
     else if(action[7])brightness<=(brightness>239)?8'd255:brightness+8'd16;
     else if(action[8])contrast<=(contrast<16)?8'd0:contrast-8'd16;
     else if(action[9])contrast<=(contrast>239)?8'd255:contrast+8'd16;
     else if(action[10])zoom_mode<=zoom_mode+1'b1;
     else if(action[11])waveform_enable<=~waveform_enable;
     else if(action[12])subtitle_enable<=~subtitle_enable;
    end
   end else if(sw_change!=0)begin
    sw_seen<=sw_stable;
    if(sw_change[7:6]!=0 && sw_stable[7:6]!=0)begin
     if((sw_stable[7:6]==1 && videos!=0) || (sw_stable[7:6]==2 && images!=0) ||
        (sw_stable[7:6]==3 && songs!=0))open_file(sw_stable[7:6]-2'd1,10'd0);
    end
    if(sw_change[5:4]!=0)begin zoom_mode<=sw_stable[5:4];if(has_opened)ui_page<=0;overlay_enable<=1;end
    if(sw_change[0])waveform_enable<=~waveform_enable;
    if(sw_change[1])subtitle_enable<=~subtitle_enable;
    if(sw_change[3])transition_mode<=(transition_mode==0)?2'd1:2'd0;
    if(sw_change[2] && has_opened)begin ui_page<=0;overlay_enable<=~overlay_enable;end
   end
  end
 end
endmodule

                                                                             
                                                                   
module media_ui_timeline(input wire clk,input wire rst_n,
 input wire [31:0] position,input wire [31:0] duration,input wire preview,input wire [15:0] target,
 output reg [15:0] seconds,output reg [15:0] length,output reg [10:0] mark);
 reg [2:0] phase;reg [5:0] bits;
 reg [41:0] q;reg [31:0] r,d,position_pending,duration_pending;
 reg [15:0] seconds_pending,length_pending;
 wire [32:0] trial={r,q[41]};
 wire [32:0] difference=trial-{1'b0,d};
 wire subtract=!difference[32];
 wire [31:0] next_r=subtract?difference[31:0]:trial[31:0];
 wire [41:0] next_q={q[40:0],subtract};
 wire [31:0] safe_duration=(^duration===1'bx)?32'd0:duration;
 wire [31:0] safe_position=(^position===1'bx)?32'd0:position;
 wire [31:0] preview_sample={16'd0,target}*32'd48000;
 wire [31:0] bar_sample=preview?preview_sample:position_pending;
 always @(posedge clk)begin
  if(!rst_n)begin
   phase<=0;bits<=0;q<=0;r<=0;d<=48000;seconds<=0;length<=0;mark<=0;
   seconds_pending<=0;length_pending<=0;position_pending<=0;duration_pending<=0;
  end else if(bits!=0)begin q<=next_q;r<=next_r;bits<=bits-1'b1;end
  else case(phase)
   0:begin
    q<={10'd0,safe_duration};r<=0;d<=48000;bits<=42;phase<=1;
    duration_pending<=safe_duration;position_pending<=(safe_position>safe_duration)?safe_duration:safe_position;
   end
   1:begin
    length_pending<=q[15:0]+(r!=0);q<={10'd0,position_pending};r<=0;d<=48000;bits<=42;phase<=2;
   end
   2:begin seconds_pending<=q[15:0];phase<=3;end
   3:begin
    q<={bar_sample,10'd0};r<=0;d<=(duration_pending==0)?32'd1:duration_pending;bits<=42;phase<=4;
   end
   4:begin
    seconds<=seconds_pending;length<=length_pending;
    mark<=(duration_pending==0)?11'd0:(q>1024)?11'd1024:q[10:0];phase<=0;
   end
  endcase
 end
endmodule

                                                                        
                                                                          
module media_ui_times(input wire clk,input wire rst_n,
 input wire [15:0] play_seconds,total_seconds,target_seconds,
 output reg [23:0] play_time,total_time,target_time);
 reg [15:0] remaining;reg [4:0] hours;
 reg [3:0] minutes_tens,minutes_units,seconds_tens;
 reg [1:0] phase,which;
                                                                         
                                                                        
 wire [15:0] unit_seconds=(phase==1)?16'd3600:(phase==2)?16'd60:16'd10;
 wire [16:0] remainder_difference={1'b0,remaining}-{1'b0,unit_seconds};
 wire [23:0] formatted={(hours>=10)?4'd1:4'd0,
  (hours>=10)?(hours[3:0]-4'd10):hours[3:0],minutes_tens,minutes_units,seconds_tens,remaining[3:0]};
 always @(posedge clk)begin
  if(!rst_n)begin
   remaining<=0;hours<=0;minutes_tens<=0;minutes_units<=0;seconds_tens<=0;phase<=0;which<=0;
   play_time<=0;total_time<=0;target_time<=0;
  end else case(phase)
   0:begin
    remaining<=(which==0)?play_seconds:(which==1)?total_seconds:target_seconds;
    hours<=0;minutes_tens<=0;minutes_units<=0;seconds_tens<=0;phase<=1;
   end
   1:if(!remainder_difference[16])begin remaining<=remainder_difference[15:0];hours<=hours+1'b1;end else phase<=2;
   2:if(!remainder_difference[16])begin
    remaining<=remainder_difference[15:0];
    if(minutes_units==9)begin minutes_units<=0;minutes_tens<=minutes_tens+1'b1;end else minutes_units<=minutes_units+1'b1;
   end else phase<=3;
   3:if(!remainder_difference[16])begin remaining<=remainder_difference[15:0];seconds_tens<=seconds_tens+1'b1;end
    else begin
     if(which==0)play_time<=formatted;else if(which==1)total_time<=formatted;else target_time<=formatted;
     which<=(which==2)?2'd0:which+1'b1;phase<=0;
    end
  endcase
 end
endmodule

                                                                           
                                                                     
module media_ui_time_format(input wire clk,input wire rst_n,input wire [15:0] seconds,
 output reg [23:0] digits);
 reg [15:0] seen,remaining;reg [4:0] hours;reg [3:0] minutes_tens,minutes_units,seconds_tens;
 reg [1:0] phase;
 always @(posedge clk)begin
  if(!rst_n)begin seen<=65535;remaining<=0;hours<=0;minutes_tens<=0;minutes_units<=0;seconds_tens<=0;phase<=0;digits<=0;end
  else case(phase)
   0:if(seconds!=seen)begin seen<=seconds;remaining<=seconds;hours<=0;minutes_tens<=0;minutes_units<=0;seconds_tens<=0;phase<=1;end
   1:if(remaining>=3600)begin remaining<=remaining-16'd3600;hours<=hours+1'b1;end else phase<=2;
   2:if(remaining>=60)begin
    remaining<=remaining-16'd60;
    if(minutes_units==9)begin minutes_units<=0;minutes_tens<=minutes_tens+1'b1;end else minutes_units<=minutes_units+1'b1;
   end else phase<=3;
   3:if(remaining>=10)begin remaining<=remaining-16'd10;seconds_tens<=seconds_tens+1'b1;end
    else begin digits<={(hours>=10)?4'd1:4'd0,(hours>=10)?(hours[3:0]-4'd10):hours[3:0],minutes_tens,minutes_units,seconds_tens,remaining[3:0]};phase<=0;end
  endcase
 end
endmodule

                                                                              
                                                                               
module media_ui_snapshot #(parameter WIDTH=129)(
 input wire src_clk,input wire src_reset_n,input wire [WIDTH-1:0] source,
 input wire dst_clk,input wire dst_reset_n,output reg [WIDTH-1:0] value);
 reg [WIDTH-1:0] payload;
 reg request,acknowledge;
 (* async_reg="true" *) reg ack_sync1,ack_sync2,req_sync1,req_sync2;
 (* keep = "true" *) (* async_reg="true" *) reg [WIDTH-1:0] payload_sync1;                 
 always @(posedge src_clk)begin
  if(!src_reset_n)begin payload<=0;request<=0;ack_sync1<=0;ack_sync2<=0;end
  else begin
   ack_sync1<=acknowledge;ack_sync2<=ack_sync1;
   if(ack_sync2==request)begin payload<=source;request<=~request;end
  end
 end
 always @(posedge dst_clk)begin
  if(!dst_reset_n)begin req_sync1<=0;req_sync2<=0;payload_sync1<=0;acknowledge<=0;value<=0;end
  else begin
   req_sync1<=request;req_sync2<=req_sync1;payload_sync1<=payload;
   if(req_sync2!=acknowledge)begin value<=payload_sync1;acknowledge<=req_sync2;end
  end
 end
endmodule

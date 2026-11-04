`timescale 1ns/1ps
                                                               
module ui_osd_layout #(parameter FRAME_CONTROLS=0)(input wire pclk,input wire reset_n,input wire frame_tick,
 input wire [10:0] x,input wire [9:0] y,input wire invalid,
 input wire paused,input wire [1:0] media_select,input wire [9:0] media_index,
 input wire [7:0] brightness,input wire [7:0] contrast,
 input wire waveform_enable,input wire subtitle_enable,input wire overlay_enable,
 input wire [1:0] zoom_mode,input wire [1:0] transition_mode,
 input wire [4:0] volume,input wire muted,
 input wire [639:0] lyric_text,input wire lyric_valid,input wire lyric_toggle,
 output reg [7:0] code,output reg [3:0] row,output reg [3:0] col,output wire region,output wire lyric_active);
 reg [10:0] scroll_offset;
 reg [11:0] index_bcd,brightness_bcd,contrast_bcd;
                                                                          
                                                                    
 reg [21:0] decimal_shift,decimal_adjusted;
 reg [7:0] brightness_binary,contrast_binary;
 reg [3:0] decimal_left;reg [1:0] decimal_field;integer decimal_digit;
 reg [1:0] media_q,zoom_q,transition_q;
 reg paused_q,wave_q,subtitle_q,overlay_q;
 reg [4:0] volume_q;reg muted_q;
 (* keep = "true" *) (* async_reg="true" *) reg lyric_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg lyric_s2;                 
                                                                      
                                                                           
                                                                             
                                                                          
                                                                
 (* keep = "true" *) reg [31:0] lyric_capture;                 
 (* keep = "true" *) (* async_reg="true" *) reg lyric_valid_sync1;                 
 reg lyric_seen,lyric_available,lyric_pending_valid;
 reg lyric_front,lyric_writing,lyric_ready;
 reg [4:0] lyric_write_index;reg lyric_copy_phase;reg [1:0] lyric_guard;
 wire lyric_event=lyric_s2!=lyric_seen;
 wire [31:0] lyric_word;
 assign lyric_active=lyric_available;
 wire [10:0] scroll_position=x+scroll_offset;
 wire music_layout=FRAME_CONTROLS && media_q==2;
 wire [10:0] text_x=x-(FRAME_CONTROLS?11'd48:11'd16);
 wire [6:0] text_cell=FRAME_CONTROLS?text_x[10:4]:{1'b0,text_x[10:5]};
 wire [9:0] lyric_top=music_layout?10'd496:10'd584;
 wire [9:0] lyric_bottom=music_layout?10'd536:10'd624;
 wire [10:0] lyric_left=FRAME_CONTROLS?11'd328:11'd16;
 wire [10:0] lyric_x=x-lyric_left;
 wire lyric_second=FRAME_CONTROLS?(y>=lyric_bottom):(y>=10'd744);
 wire [6:0] lyric_character=(FRAME_CONTROLS?{1'b0,lyric_x[9:4]}:text_cell)+(lyric_second?7'd39:7'd0);
                                                                            
                                                                       
                                                                       
 wire [10:0] lyric_next_text_x=x-lyric_left+11'd1;
 wire [6:0] lyric_next_character=(FRAME_CONTROLS?{1'b0,lyric_next_text_x[9:4]}:
                                    {1'b0,lyric_next_text_x[10:5]})+(lyric_second?7'd39:7'd0);
 eg_dual_clock_mem #(.WIDTH(32),.AW(6),.IMPLEMENT("9K")) lyric_memory(
  .wclk(pclk),.wrst(!reset_n),.we(lyric_writing && lyric_copy_phase && !lyric_event),
  .waddr({!lyric_front,lyric_write_index}),.wdata(lyric_capture),
  .rclk(pclk),.rrst(!reset_n),.re(1'b1),
  .raddr({lyric_front,lyric_next_character[6:2]}),.rdata(lyric_word));
                                                                         
                                                                     
 wire fault_region=invalid && x>=528 && x<752 && y>=360 && y<392;
 wire draw_overlay=FRAME_CONTROLS?overlay_q:overlay_enable;
 wire draw_subtitle=FRAME_CONTROLS?subtitle_q:subtitle_enable;
 wire status_region=draw_overlay && x>=(FRAME_CONTROLS?48:16) && x<(FRAME_CONTROLS?1232:1264) &&
  ((y>=8 && y<40)||(y>=44 && y<76));
 wire lyric_region=lyric_available && draw_subtitle && x>=lyric_left && x<lyric_left+(FRAME_CONTROLS?624:1248) &&
  (FRAME_CONTROLS?((y>=lyric_top && y<lyric_top+32)||(y>=lyric_bottom && y<lyric_bottom+32)):
                   ((y>=704 && y<736)||(y>=744 && y<776)));
 wire [9:0] subtitle_top=FRAME_CONTROLS?lyric_bottom:10'd744;
 wire subtitle_region=draw_subtitle && x>=(FRAME_CONTROLS?48:16) && x<(FRAME_CONTROLS?1232:1264) && y>=subtitle_top && y<subtitle_top+32 && !lyric_available;
 assign region=fault_region || status_region || subtitle_region || lyric_region;
 always @*begin
  decimal_adjusted=decimal_shift;
  for(decimal_digit=0;decimal_digit<3;decimal_digit=decimal_digit+1)
   if(decimal_shift[10+decimal_digit*4+:4]>=5)
    decimal_adjusted[10+decimal_digit*4+:4]=decimal_shift[10+decimal_digit*4+:4]+4'd3;
 end
 always @(posedge pclk)begin
  if(!reset_n)begin
   scroll_offset<=0;index_bcd<=0;brightness_bcd<=12'h128;contrast_bcd<=12'h128;
   decimal_shift<=0;decimal_left<=0;decimal_field<=3;brightness_binary<=128;contrast_binary<=128;
   media_q<=0;zoom_q<=0;transition_q<=0;paused_q<=0;wave_q<=0;subtitle_q<=0;overlay_q<=0;
   volume_q<=16;muted_q<=0;
   lyric_sync1<=0;lyric_s2<=0;lyric_seen<=0;lyric_available<=0;
   lyric_capture<=0;lyric_valid_sync1<=0;lyric_copy_phase<=0;lyric_guard<=0;
   lyric_pending_valid<=0;lyric_front<=0;lyric_writing<=0;lyric_ready<=0;lyric_write_index<=0;
  end else begin
   lyric_sync1<=(lyric_toggle===1'b1);lyric_s2<=lyric_sync1;
   lyric_capture<=lyric_text[{lyric_write_index,5'b00000}+:32];
   lyric_valid_sync1<=(lyric_valid===1'b1);
   if(lyric_event)begin
    lyric_seen<=lyric_s2;lyric_copy_phase<=0;lyric_guard<=0;
    lyric_pending_valid<=lyric_valid_sync1;
    lyric_writing<=lyric_valid_sync1;lyric_write_index<=0;lyric_ready<=!lyric_valid_sync1;
   end else if(lyric_writing)begin
    lyric_copy_phase<=!lyric_copy_phase;
    if(lyric_copy_phase)begin
     if(lyric_write_index==19)begin lyric_writing<=0;lyric_guard<=3;end
     else lyric_write_index<=lyric_write_index+1'b1;
    end
   end else if(lyric_guard!=0)begin
    lyric_guard<=lyric_guard-1'b1;
    if(lyric_guard==1)lyric_ready<=1;
   end
   if(frame_tick)begin
   if(lyric_ready && !lyric_event)begin
    if(lyric_pending_valid)lyric_front<=!lyric_front;
    lyric_available<=lyric_pending_valid;lyric_ready<=0;
   end
   if(!paused)scroll_offset<=scroll_offset+11'd2;
   decimal_shift<={12'd0,media_index};decimal_left<=10;decimal_field<=0;
   brightness_binary<=brightness;contrast_binary<=contrast;
   media_q<=media_select;zoom_q<=zoom_mode;transition_q<=transition_mode;
   paused_q<=paused;wave_q<=waveform_enable;subtitle_q<=subtitle_enable;overlay_q<=overlay_enable;
   volume_q<=volume;muted_q<=muted;
   end else if(decimal_left!=0)begin
    decimal_shift<=decimal_adjusted<<1;decimal_left<=decimal_left-1'b1;
   end else case(decimal_field)
    0:begin index_bcd<=decimal_shift[21:10];decimal_shift<={14'd0,brightness_binary};decimal_left<=10;decimal_field<=1;end
    1:begin brightness_bcd<=decimal_shift[21:10];decimal_shift<={14'd0,contrast_binary};decimal_left<=10;decimal_field<=2;end
    2:begin contrast_bcd<=decimal_shift[21:10];decimal_field<=3;end
    default:begin end
   endcase
  end
 end
 always @*begin
  code=0;row=0;col=0;
  if(fault_region)begin
   row=(y-360)>>1;col=(x-528)>>1;
   case((x-528)>>5)
    0:code=8'd73;
    1:code=8'd78;
    2:code=8'd86;
    3:code=8'd65;
    4:code=8'd76;
    5:code=8'd73;
    6:code=8'd68;
    default:code=0;
   endcase
  end else if(status_region)begin
   col=FRAME_CONTROLS?{1'b0,text_x[3:1]}:text_x[4:1];
   if(y<40)begin
    row=(y-8)>>1;
    case(text_cell)
    0:code=(media_q==0)?8'd86:(media_q==1)?8'd73:8'd65;
    1:code=(media_q==0)?8'd73:(media_q==1)?8'd77:8'd85;
    2:code=(media_q==0)?8'd68:(media_q==1)?8'd65:8'd68;
    3:code=(media_q==0)?8'd69:(media_q==1)?8'd71:8'd73;
    4:code=(media_q==0)?8'd79:(media_q==1)?8'd69:8'd79;
    6:code=8'd48+index_bcd[11:8];
    7:code=8'd48+index_bcd[7:4];
    8:code=8'd48+index_bcd[3:0];
    10:code=paused_q?8'd80:8'd80;
    11:code=paused_q?8'd65:8'd76;
    12:code=paused_q?8'd85:8'd65;
    13:code=paused_q?8'd83:8'd89;
    14:code=paused_q?8'd69:8'd0;
    16:code=8'd66;
    17:code=8'd48+brightness_bcd[11:8];
    18:code=8'd48+brightness_bcd[7:4];
    19:code=8'd48+brightness_bcd[3:0];
    21:code=8'd67;
    22:code=8'd48+contrast_bcd[11:8];
    23:code=8'd48+contrast_bcd[7:4];
    24:code=8'd48+contrast_bcd[3:0];
    default:code=0;
    endcase
    if(FRAME_CONTROLS)case(text_cell)
     34:code=86;35:code=79;36:code=76;
     38:code=(volume_q>=10)?49:48;
     39:code=48+((volume_q>=10)?volume_q-5'd10:volume_q);
     40:code=47;41:code=49;42:code=54;
     45:code=muted_q?77:83;46:code=muted_q?85:79;47:code=muted_q?84:85;
     48:code=muted_q?69:78;49:code=68;50:code=muted_q?0:32;
     51:code=muted_q?0:79;52:code=muted_q?0:78;
     default:begin end
    endcase
   end else begin
    row=(y-44)>>1;
    case(text_cell)
    0:code=8'd87;
    1:code=8'd65;
    2:code=8'd86;
    3:code=8'd69;
    5:code=wave_q?8'd79:8'd79;
    6:code=wave_q?8'd78:8'd70;
    7:code=wave_q?8'd0:8'd70;
    9:code=8'd83;
    10:code=8'd85;
    11:code=8'd66;
    13:code=subtitle_q?8'd79:8'd79;
    14:code=subtitle_q?8'd78:8'd70;
    15:code=subtitle_q?8'd0:8'd70;
    17:code=8'd79;
    18:code=8'd83;
    19:code=8'd68;
    21:code=overlay_q?8'd79:8'd79;
    22:code=overlay_q?8'd78:8'd70;
    23:code=overlay_q?8'd0:8'd70;
    25:code=8'd90;
    26:code=8'd48+zoom_q;
    28:code=8'd70;
    29:code=8'd88;
    30:code=8'd48+transition_q;
    default:code=0;
    endcase
   end
  end else if(lyric_region || (subtitle_region && lyric_available))begin
   row=FRAME_CONTROLS?((y-(lyric_second?lyric_bottom:lyric_top))>>1):((y<736)?((y-704)>>1):((y-744)>>1));
   col=FRAME_CONTROLS?{1'b0,lyric_x[3:1]}:text_x[4:1];
   code=lyric_word[{lyric_character[1:0],3'b000}+:8];
  end else if(subtitle_region)begin
   row=(y-subtitle_top)>>1;col=FRAME_CONTROLS?{1'b0,scroll_position[3:1]}:scroll_position[4:1];
   case(FRAME_CONTROLS?scroll_position[10:4]:{1'b0,scroll_position[10:5]})
    0:code=8'd70;
    1:code=8'd80;
    2:code=8'd71;
    3:code=8'd65;
    5:code=8'd77;
    6:code=8'd69;
    7:code=8'd68;
    8:code=8'd73;
    9:code=8'd65;
    11:code=8'd80;
    12:code=8'd76;
    13:code=8'd65;
    14:code=8'd89;
    15:code=8'd69;
    16:code=8'd82;
    19:code=8'd82;
    20:code=8'd69;
    21:code=8'd65;
    22:code=8'd76;
    24:code=8'd65;
    25:code=8'd85;
    26:code=8'd68;
    27:code=8'd73;
    28:code=8'd79;
    30:code=8'd87;
    31:code=8'd65;
    32:code=8'd86;
    33:code=8'd69;
    34:code=8'd70;
    35:code=8'd79;
    36:code=8'd82;
    37:code=8'd77;
    40:code=8'd85;
    41:code=8'd83;
    42:code=8'd69;
    44:code=8'd75;
    45:code=8'd69;
    46:code=8'd89;
    47:code=8'd83;
    49:code=8'd84;
    50:code=8'd79;
    52:code=8'd65;
    53:code=8'd68;
    54:code=8'd74;
    55:code=8'd85;
    56:code=8'd83;
    57:code=8'd84;
    default:code=0;
   endcase
  end
 end
endmodule

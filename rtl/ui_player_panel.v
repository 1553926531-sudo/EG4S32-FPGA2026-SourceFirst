`timescale 1ns/1ps
module ui_player_panel(input wire pclk,input wire reset_n,input wire frame_tick,
 input wire [10:0] x,input wire [9:0] y,input wire visible,input wire [1:0] page,
 input wire [1:0] media,input wire [9:0] item,input wire [10:0] cursor,
 input wire [9:0] video_count,input wire [9:0] image_count,input wire [10:0] library_count,
 input wire library_ready,input wire has_opened,input wire [7:0] name_code,input wire [7:0] media_error,
 output wire [11:0] name_id,output wire [4:0] name_char,
 input wire [23:0] play_time,input wire [23:0] total_time,input wire [23:0] target_time,
 input wire [10:0] progress,input wire [1:0] seek_step,
 input wire [4:0] volume,input wire muted,
 output reg [7:0] code,output wire [3:0] row,output wire [3:0] col,
 output wire text_region,output wire backdrop,output wire highlight,
 output wire bar_background,output wire bar_fill,output wire bar_cursor);
 reg show,ready_q,opened_q;reg [7:0] error_q;reg [1:0] page_q,media_q,step_q;
 reg [4:0] volume_q;reg muted_q;
 reg [9:0] item_q,videos_q,images_q;
 reg [10:0] cursor_q,count_q,mark_q;
 reg [23:0] time_q,length_q;reg [15:0] cursor_bcd,count_bcd;
 reg [26:0] bcd_shift,bcd_adjusted;reg [3:0] bcd_bits;reg bcd_count;integer bcd_digit;
 wire [10:0] tx=x-11'd48;
 wire [6:0] text_cell=tx[10:4];
 wire [10:0] next_tx=x-11'd47;
 wire [9:0] list_y=y-10'd224;
 wire [2:0] list_row=list_y[8:6];
 wire [10:0] ordinal={cursor_q[10:3],list_row};
 wire [10:0] image_end={1'b0,videos_q}+{1'b0,images_q};
 wire [1:0] list_kind=(ordinal<videos_q)?2'd0:(ordinal<image_end)?2'd1:2'd2;
 wire [9:0] list_item=(ordinal<videos_q)?ordinal[9:0]:
                            (ordinal<image_end)?(ordinal-videos_q):(ordinal-image_end);
 reg [1:0] list_kind_q;reg [9:0] list_item_q;
 always @(posedge pclk)begin
  if(!reset_n)begin list_kind_q<=0;list_item_q<=0;end
  else begin list_kind_q<=list_kind;list_item_q<=list_item;end
 end
 wire top_name=y>=104 && y<136;
 wire heading=y>=168 && y<200;
 wire browser_line=page_q==1 && y>=224 && y<704 && list_y[5:0]<32 && ordinal<count_q;
 wire browser_hint=page_q==1 && y>=736 && y<768;
 wire empty_line=page_q==1 && count_q==0 && y>=288 && y<320;
 wire time_line=y>=720 && y<752;
 wire hint_line=y>=760 && y<792;
 wire error_line=error_q!=0 && ((page_q!=1 && y>=256 && y<288)||(page_q==1 && !ready_q && empty_line));
 wire option_line=page_q==0 && ((y>=168 && y<200)||(y>=208 && y<240));
 wire seek_line=page_q==2 && ((y>=256 && y<288)||(y>=320 && y<352)||(y>=384 && y<416));
 wire volume_line=page_q==3 && y>=320 && y<352;
 wire filename=(top_name && opened_q) || browser_line;
 wire [1:0] label_kind=browser_line?list_kind_q:media_q;
 assign name_id=(page_q==1 && !top_name)?{list_kind_q,list_item_q}:{media_q,item_q};
 assign name_char=next_tx[8:4]-5'd8;
 assign text_region=show && x>=48 && x<1232 &&
   (top_name || (page_q==1?(heading||browser_line||browser_hint||empty_line):
                                       (option_line||seek_line||volume_line||time_line||hint_line||error_line)));
 assign row=top_name?((y-104)>>1):page_q==1?
              heading?((y-168)>>1):browser_hint?((y-736)>>1):empty_line?((y-288)>>1):{1'b0,list_y[4:1]}:
              error_line?((y-256)>>1):time_line?((y-720)>>1):hint_line?((y-760)>>1):
              option_line?(y<208?((y-168)>>1):((y-208)>>1)):
              (y<320?((y-256)>>1):y<384?((y-320)>>1):((y-384)>>1));
 assign col={1'b0,tx[3:1]};
 assign backdrop=show && x>=32 && x<1248 &&
   ((y>=96 && y<144) || (page_q==0 && y>=152 && y<248) ||
    (page_q==1 && y>=152 && y<776) || (page_q[1] && y>=248 && y<432) ||
    (page_q!=1 && (y>=672 || error_line)));
 assign highlight=show && browser_line && ordinal==cursor_q && x>=32 && x<1248;
 assign bar_background=show && page_q!=1 && x>=128 && x<1152 && y>=688 && y<704;
 wire [10:0] bar_x=x-11'd128;
 assign bar_fill=bar_background && bar_x<mark_q;
 assign bar_cursor=show && page_q!=1 && x>=126 && x<1154 && y>=684 && y<708 &&
                  x+11'd2>=11'd128+mark_q && x<=11'd130+mark_q;
 always @*begin
  bcd_adjusted=bcd_shift;
  for(bcd_digit=0;bcd_digit<4;bcd_digit=bcd_digit+1)
   if(bcd_shift[11+bcd_digit*4+:4]>=5)
    bcd_adjusted[11+bcd_digit*4+:4]=bcd_shift[11+bcd_digit*4+:4]+4'd3;
 end
 always @(posedge pclk)begin
  if(!reset_n)begin
   show<=0;ready_q<=0;opened_q<=0;error_q<=0;page_q<=0;media_q<=0;step_q<=0;item_q<=0;
   volume_q<=16;muted_q<=0;
   videos_q<=0;images_q<=0;cursor_q<=0;count_q<=0;mark_q<=0;time_q<=0;length_q<=0;
   cursor_bcd<=0;count_bcd<=0;bcd_shift<=0;bcd_bits<=0;bcd_count<=0;
  end else if(frame_tick)begin
   show<=visible;ready_q<=library_ready;opened_q<=has_opened;error_q<=media_error;
   page_q<=page;media_q<=media;item_q<=item;step_q<=seek_step;
   volume_q<=volume;muted_q<=muted;
   videos_q<=video_count;images_q<=image_count;cursor_q<=cursor;count_q<=library_count;
   mark_q<=progress;time_q<=(page==2)?target_time:play_time;length_q<=total_time;
   bcd_shift<={16'd0,library_count==0?11'd0:cursor+11'd1};bcd_bits<=11;bcd_count<=0;
  end else if(bcd_bits!=0)begin bcd_shift<=bcd_adjusted<<1;bcd_bits<=bcd_bits-1'b1;end
  else if(!bcd_count)begin
   cursor_bcd<=bcd_shift[26:11];bcd_shift<={16'd0,count_q};bcd_bits<=11;bcd_count<=1;
  end else count_bcd<=bcd_shift[26:11];
 end
 reg [3:0] text_line;
 wire [7:0] text_code;
 ui_panel_text text_rom(.clk(pclk),.line_id(text_line),.character(next_tx[10:4]),.code(text_code));
 always @*begin
  text_line=0;
  if(top_name)text_line=opened_q?4'd0:
                            4'd1;
  else if(error_line)text_line=4'd2;
  else if(page_q==1)begin
   if(heading)text_line=4'd3;
   else if(browser_hint)text_line=4'd4;
   else if(empty_line)text_line=ready_q?4'd5:
                                        4'd6;
  end else if(time_line)text_line=4'd7;
  else if(hint_line)text_line=(page_q==3)?4'd0:(page_q==2)?4'd8:
                                                 4'd9;
  else if(option_line)text_line=(y<208)?4'd10:
                                                       4'd11;
  else if(seek_line)text_line=(y<320)?4'd12:
                               (y<384)?4'd13:
                                           4'd14;
  else if(volume_line)text_line=4'd15;
 end
 always @*begin
  code=text_cell<74?text_code:8'd0;
  if(filename)begin
   code=32;
   case(text_cell)
    0:code=(label_kind==0)?86:(label_kind==1)?73:65;
    1:code=(label_kind==0)?73:(label_kind==1)?77:85;
    2:code=(label_kind==0)?68:(label_kind==1)?65:68;
    3:code=(label_kind==0)?69:(label_kind==1)?71:73;
    4:code=(label_kind==0)?79:(label_kind==1)?69:79;
    default:if(text_cell>=8 && text_cell<40)code=name_code;
   endcase
  end
  if(time_line && page_q!=1)case(text_cell)
   0:code=48+time_q[23:20];1:code=48+time_q[19:16];3:code=48+time_q[15:12];4:code=48+time_q[11:8];
   6:code=48+time_q[7:4];7:code=48+time_q[3:0];
   11:code=48+length_q[23:20];12:code=48+length_q[19:16];14:code=48+length_q[15:12];15:code=48+length_q[11:8];
   17:code=48+length_q[7:4];18:code=48+length_q[3:0];default:begin end
  endcase
  if(page_q==1 && heading)case(text_cell)
   6:code=48+cursor_bcd[15:12];7:code=48+cursor_bcd[11:8];8:code=48+cursor_bcd[7:4];9:code=48+cursor_bcd[3:0];
   13:code=48+count_bcd[15:12];14:code=48+count_bcd[11:8];15:code=48+count_bcd[7:4];16:code=48+count_bcd[3:0];default:begin end
  endcase
  if(page_q==2 && y>=384 && y<416)begin
   if(text_cell==5)code=(step_q==0)?48:(step_q==1)?49:54;
   if(text_cell==6)code=(step_q==0)?49:48;
  end
  if(page_q==3 && time_line && text_cell>=19)code=32;
  if(volume_line)begin
   if(text_cell==7)code=(volume_q>=10)?49:48;
   if(text_cell==8)code=48+((volume_q>=10)?volume_q-5'd10:volume_q);
   if(muted_q)case(text_cell)
    17:code=77;18:code=85;19:code=84;20:code=69;21:code=68;
    22,23,24:code=32;default:begin end
   endcase
  end
  if(error_line && (text_cell==11 || text_cell==12))begin
   if(text_cell==11)code=(error_q[7:4]<10)?48+error_q[7:4]:55+error_q[7:4];
   else code=(error_q[3:0]<10)?48+error_q[3:0]:55+error_q[3:0];
  end
  if(!text_region)code=0;
 end
endmodule

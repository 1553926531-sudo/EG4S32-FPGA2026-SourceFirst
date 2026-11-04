`timescale 1ns/1ps
module tb_ui_raster;
 reg clk=0,reset_n=0;always #5 clk=~clk;
 reg [1:0] page=1,fx=0,media=0;
 reg overlay=1,subtitle=1,wave=1,ready=0,opened=0,muted=0;
 reg [4:0] volume=16;reg [7:0] error=0,brightness=128;
 reg [10:0] cursor=0,mark=256,count=0;
 reg [9:0] item=0,videos=0,images=0;
 reg [23:0] target=24'h010203;
 reg [639:0] lyrics=0;reg lyric_toggle=0,sample_toggle=0;
 wire de,under;wire [23:0] rgb;wire [11:0] name_id;wire [4:0] name_char;
 reg [7:0] name_code;reg [255:0] name_text;
 integer frame=0,pixels=0,x=0,y=0,fd=0,i;
 reg [7:0] sample_clock=0;
 reg [4095:0] output_path;
 reg [2047:0] output_dir;
 function [255:0] filename;
  input [11:0] id;
  begin case(id)
   0:filename="Movie A.TFV                     ";
   1:filename="Second movie.TFV                ";
   1024:filename="First image.bmp                 ";
   1025:filename="Second image.BMP                ";
   1026:filename="A long image filename 03.bmp    ";
   1027:filename="image 04.bmp                    ";
   1028:filename="image 05.bmp                    ";
   2048:filename="Ferry.wav                       ";
   2049:filename="Hotel California.wav            ";
   2050:filename="Third song.wav                  ";
   default:filename="                                ";
  endcase end
 endfunction
 always @*name_text=filename(name_id);
 always @(posedge clk)name_code<=name_text[255-name_char*8-:8];
 video_scan_enhanced #(.PLAYER_UI(1)) dut(
  .pclk(clk),.reset_n(reset_n),.enable(1'b1),.fatal(1'b0),
  .pixel_data(32'h00224466),.pixel_valid(1'b1),.pixel_level(14'd8192),.pixel_ready(),
  .underrun(under),.brightness(brightness),.contrast(8'd128),.zoom_mode(2'd0),
  .waveform_enable(wave),.subtitle_enable(subtitle),.overlay_enable(overlay),
  .transition_mode(fx),.paused(1'b1),.media_select(media),.media_index(item),
  .audio_level(16'd0),.audio_pcm(16'd0),.audio_sample_toggle(sample_toggle),
  .audio_flush_toggle(1'b0),.frame_commit_toggle(1'b0),
  .lyric_text(lyrics),.lyric_valid(1'b1),.lyric_toggle(lyric_toggle),
  .ui_page(page),.browser_cursor(cursor),.library_count(count),.video_count(videos),.image_count(images),
  .play_time(24'h000123),.total_time(24'h000631),.target_time(target),.progress_mark(mark),.seek_step(2'd1),
  .volume(volume),.muted(muted),.library_ready(ready),.has_opened(opened),.media_error(error),
  .name_code(name_code),.name_id(name_id),.name_char(name_char),.rgb(rgb),.de(de),.hs(),.vs());
 task scene;
  input integer n;
  begin
   page=0;fx=0;media=2;overlay=1;subtitle=1;wave=1;ready=1;opened=1;
   volume=16;muted=0;error=0;brightness=128;cursor=7;mark=256;count=10;videos=2;images=5;item=1;
   case(n)
    1:begin page=1;media=0;ready=0;opened=0;count=0;videos=0;images=0;cursor=0;end
    2:begin page=1;media=0;opened=0;count=0;videos=0;images=0;cursor=0;end
    3:begin page=1;media=0;opened=0;cursor=7;end
    4:begin page=1;cursor=9;end
    5:begin end
    6:subtitle=0;
    7:wave=0;
    8:begin wave=0;subtitle=0;end
    9:begin page=2;fx=1;mark=768;end
    10:begin page=3;volume=7;end
    11:begin page=3;volume=7;muted=1;end
    12:overlay=0;
    13:begin wave=0;subtitle=0;brightness=144;end
    14:begin media=1;item=0;wave=0;subtitle=0;error=8'h54;end
    15:begin media=0;item=1;wave=0;subtitle=0;end
    default:begin end
   endcase
  end
 endtask
 initial begin
  if(!$value$plusargs("out=%s",output_dir))output_dir="verification/revision_20261103_native_files/pixels";
  for(i=0;i<80;i=i+1)lyrics[i*8+:8]=33+(i%94);
  scene(1);repeat(5)@(negedge clk);reset_n=1;lyric_toggle=1;
 end
 always @(negedge clk)if(reset_n)begin
  sample_clock<=sample_clock+1'b1;if(sample_clock==0)sample_toggle<=~sample_toggle;
 end
 always @(posedge clk)begin
  #1;
  if(reset_n && de)begin
   if(dut.pipe_x!==x || dut.pipe_y!==y || under)begin
    $display("FAIL raster frame=%0d expected=%0d,%0d got=%0d,%0d under=%b",frame,x,y,dut.pipe_x,dut.pipe_y,under);$finish;
   end
   if(frame>0)$fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   if(frame>0 && x==100 && y==100)scene(frame+1);
   pixels=pixels+1;
   if(x==1279)begin x=0;y=y+1;end else x=x+1;
   if(pixels==1024000)begin
    if(frame>0)$fclose(fd);
    $display("RASTER frame %0d complete",frame);$fflush();
    frame=frame+1;pixels=0;x=0;y=0;
    if(frame==16)begin $display("PASS ui_raster captured 15360000 pixels with synchronous names and mid-frame input changes");$finish;end
    $sformat(output_path,"%0s/rtl_%02d.ppm",output_dir,frame);
    fd=$fopen(output_path,"wb");
    if(!fd)begin $display("FAIL raster cannot open %0s",output_path);$fatal;end
    $fwrite(fd,"P3\n1280 800\n255\n");
   end
  end
 end
 initial begin #230000000;$display("FAIL raster timeout frame=%0d",frame);$finish;end
endmodule

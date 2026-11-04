`timescale 1ns/1ps
module tb_ui;
 reg clk=0,rst_n=0;always #1 clk=~clk;
 reg [15:0] pressed=0;reg [7:0] switches=0;reg [3:0] cols;
 wire [3:0] rows;wire [1:0] media,zoom,fx,page,step;wire [9:0] item;
 reg [9:0] videos=1,images=5,songs=2,actual_index=0;reg [1:0] actual_media=0;
 reg [31:0] position=48000*67+24000,duration=48000*125+24000;
 wire pause,wave,lyrics,overlay,restart,seek;
 wire [7:0] bri,ct,sw,led;wire [15:0] seconds,length,target;
 wire [10:0] cursor,mark,count;wire [23:0] pt,tt,st;
 wire [4:0] volume;wire muted;
 integer restarts=0,seeks=0,i,n,ordinal;reg was_restart=0,was_seek=0;
 reg [35:0] saved;
 media_ui_ctrl #(.CLK_HZ(10000),.KEY_SCAN_HZ(100),.DEBOUNCE_SCANS(2)) dut(
 .clk(clk),.rst_n(rst_n),.key_col_n(cols),.switches(switches),.key_row_n(rows),
 .media_select(media),.media_index(item),.paused(pause),.brightness(bri),.contrast(ct),
 .zoom_mode(zoom),.waveform_enable(wave),.subtitle_enable(lyrics),.overlay_enable(overlay),
 .transition_mode(fx),.restart_pulse(restart),.switch_state(sw),.led_state(led),
 .video_count(videos),.image_count(images),.music_count(songs),.actual_media(actual_media),.actual_index(actual_index),
 .playback_position(position),.playback_duration(duration),.seek_request(seek),.seek_seconds(target),
 .ui_page(page),.browser_cursor(cursor),.seek_step(step),.volume(volume),.muted(muted),.play_seconds(seconds),.total_seconds(length),
 .progress_mark(mark),.library_count(count),.play_time(pt),.total_time(tt),.target_time(st));
 always @*begin
  cols=15;
  if(!rows[0])cols=~pressed[3:0];else if(!rows[1])cols=~pressed[7:4];
  else if(!rows[2])cols=~pressed[11:8];else if(!rows[3])cols=~pressed[15:12];
 end
 task bad;input [511:0] msg;begin
  $display("FAIL UI %0s page=%d media=%d item=%d target=%d mark=%d restart=%d seek=%d",msg,page,media,item,target,mark,restarts,seeks);$finish;
 end endtask
 task settle;begin repeat(600)@(negedge clk);end endtask
 task key;input integer k;begin
  @(negedge clk);pressed=16'b1<<k;repeat(800)@(negedge clk);pressed=0;settle;
 end endtask
 always @(posedge clk)if(rst_n)begin
  if(restart)begin restarts=restarts+1;if(was_restart)bad("restart wider than one cycle");end
  if(seek)begin seeks=seeks+1;if(was_seek)bad("seek wider than one cycle");end
  was_restart=restart;was_seek=seek;
 end
 initial begin
  repeat(3)@(negedge clk);rst_n=1;settle;
  if(count!=8 || seconds!=67 || length!=126 || mark!=550 || pt!=24'h000107 || tt!=24'h000206)bad("sample timeline/BCD");
                                                                           
  pressed=4;repeat(40)@(negedge clk);pressed=0;settle;if(restarts)bad("key bounce");
  pressed=6;repeat(800)@(negedge clk);pressed=0;settle;if(restarts)bad("multiple keys");
  key(1);if(media!=2 || item!=1 || restarts!=1)bad("global previous wraps to last song");
  key(2);if(media!=0 || item!=0 || restarts!=2)bad("pending next wraps to first video");
  actual_media=0;actual_index=0;settle;
  key(0);if(page!=1 || cursor!=0)bad("open files");
  for(i=0;i<7;i=i+1)key(2);
  if(cursor!=7 || restarts!=2)bad("browse changes playback before confirmation");
  key(3);if(media!=2 || item!=1 || page!=0 || restarts!=3)bad("open arbitrary file");
  actual_media=2;actual_index=1;settle;
  key(3);if(!pause)bad("pause");
  key(4);if(page!=2 || !pause || target!=67)bad("seek preview holds paused state");
  key(2);if(target!=77 || seeks!=0)bad("seek preview committed early");
  key(14);if(step!=2)bad("60 second step");
  key(2);if(target!=125)bad("seek upper clamp");
  key(3);if(page!=0 || seeks!=1 || !pause || target!=125)bad("seek confirmation/pause preservation");
  key(4);key(1);key(4);if(page!=0 || seeks!=1 || !pause)bad("cancel seek changed playback");
  key(3);if(pause)bad("resume");
  key(4);key(14);if(step!=0)bad("one second step");
  key(1);if(target!=66)bad("one second decrement");
  key(14);if(step!=1)bad("10 second step");
  pressed=2;repeat(18000)@(negedge clk);pressed=0;settle;
  if(target!=0)bad("held seek/backward lower clamp");
  key(13);if(page!=0 || pause || overlay)bad("clean cancels preview and restores playing state");
  key(13);if(!overlay)bad("recall UI");
                                                                        
  switches=3;settle;settle;if(!wave || !lyrics)bad("switch toggles");
  key(11);key(12);if(wave || lyrics)bad("cannot turn off effect while switch stays on");
  key(11);key(12);key(13);if(overlay || !wave || !lyrics)bad("clean destroyed saved options");
  key(13);if(!overlay || !wave || !lyrics)bad("recall destroyed options");
  key(6);key(7);if(bri!=128)bad("brightness steps");
  key(8);key(9);if(ct!=128)bad("contrast steps");
  for(i=0;i<10;i=i+1)key(6);if(bri!=0)bad("brightness lower clamp");
  for(i=0;i<18;i=i+1)key(7);if(bri!=255)bad("brightness upper clamp");
  for(i=0;i<4;i=i+1)begin key(5);if(fx!=((i+1)%4))bad("FX cycle and off");end
  n=seeks;key(10);if(zoom!=1 || seeks!=n+1 || target!=67)bad("zoom lost playback position");
  n=restarts;key(14);if(restarts!=n+1)bad("restart from zero");
                                                                         
                                                                           
  n=seeks;i=restarts;switches=8'ha3;settle;settle;
  if(media!=1 || item!=0 || zoom!=2 || restarts!=i+1 || seeks!=n)bad("class plus zoom leaked previous file position");
  actual_media=1;actual_index=0;settle;
  saved={media,item,pause,bri,ct,zoom,wave,lyrics,overlay,fx};n=seeks;
  key(15);if(!muted || volume!=16 || page!=0 || saved!=={media,item,pause,bri,ct,zoom,wave,lyrics,overlay,fx} || seeks!=n)bad("global mute altered player state");
  key(15);if(muted)bad("global unmute");
  pressed=16'h8000;repeat(7000)@(negedge clk);
  if(page!=3 || muted)bad("volume hold must not toggle mute");
  pressed=0;settle;if(muted || page!=3)bad("volume release toggled mute");
  key(1);if(volume!=15 || muted)bad("volume down");
  key(3);if(!muted)bad("volume page mute");
  key(2);if(volume!=16 || muted)bad("volume adjustment unmute");
  pressed=2;repeat(22000)@(negedge clk);pressed=0;settle;
  if(volume!=0)bad("held volume lower clamp");
  pressed=4;repeat(22000)@(negedge clk);pressed=0;settle;
  if(volume!=16)bad("held volume upper clamp");
  key(4);if(page!=0 || seeks!=n)bad("volume back alters playback");
  key(4);if(page!=2 || !pause)bad("seek before volume");
  pressed=16'h8000;repeat(7000)@(negedge clk);pressed=0;settle;
  if(page!=3 || !pause)bad("volume released seek pause");
  key(4);if(page!=2 || !pause)bad("volume return lost seek");
  key(4);if(page!=0)bad("seek cancel after volume");
  key(0);key(15);if(page!=1 || !muted)bad("browser global mute");
  key(15);key(0);
  pressed=16'h8000;repeat(800)@(negedge clk);pressed=16'h8002;
  repeat(800)@(negedge clk);pressed=16'h8000;repeat(800)@(negedge clk);pressed=0;settle;
  if(muted || page!=0)bad("multi-key volume gesture must be suppressed");
                                                                     
                                                                       
  actual_media=0;actual_index=0;settle;n=restarts;
  for(i=1;i<=8;i=i+1)begin
   key(2);ordinal=i%8;
   if(ordinal==0)begin if(media!=0 || item!=0)bad("forward video boundary");end
   else if(ordinal<6)begin if(media!=1 || item!=ordinal-1)bad("forward image boundary");end
   else if(media!=2 || item!=ordinal-6)bad("forward audio boundary");
  end
  for(i=1;i<=8;i=i+1)begin
   key(1);ordinal=(8-i)%8;
   if(ordinal==0)begin if(media!=0 || item!=0)bad("backward video boundary");end
   else if(ordinal<6)begin if(media!=1 || item!=ordinal-1)bad("backward image boundary");end
   else if(media!=2 || item!=ordinal-6)bad("backward audio boundary");
  end
  if(restarts!=n+16)bad("library traversal restart count");
  videos=0;images=601;songs=10'bx;settle;
  if(count!=0)bad("invalid library counts must produce an empty library");
  n=restarts;key(0);key(3);key(1);key(2);
  if(restarts!=n || count!=0 || cursor!=0)bad("empty library opened a file");
  key(0);
                                                                             
  videos=600;images=600;songs=600;actual_media=2;actual_index=599;settle;
  key(0);if(cursor!=1799 || count!=1800)bad("large library last ordinal");
  key(2);if(cursor!=0)bad("large browser wrap");key(1);if(cursor!=1799)bad("large browser previous");
  key(0);if(page!=0)bad("browser back");
  duration=2073600000;position=2073599999;settle;
  if(length!=43200 || seconds!=43199 || mark!=1023 || pt!=24'h115959 || tt!=24'h120000)bad("12 hour maximum timeline");
  position=duration;settle;if(mark!=1024)bad("full progress");
  duration=0;position=0;settle;key(4);if(page!=0 || length!=0 || mark!=0)bad("zero duration");
  $display("PASS UI: physical matrix debounce/multikey, every key, global files/1800 ordinals, modal seek/steps/repeat/clamps/pause/cancel, clean/recall, switches, global volume/mute/tap/hold/repeat/bounds/seek preservation, fractional/12h timeline");$finish;
 end
 initial begin #1000000;bad("timeout");end
endmodule

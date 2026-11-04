`timescale 1ns/1ps
module tb_ui_start;
 reg clk=0,reset_n=0;always #1 clk=~clk;
 reg [15:0] keys=0;reg [3:0] columns;reg [7:0] switches=0;
 reg [9:0] videos=0,images=0,songs=0;
 wire [3:0] rows;wire [1:0] page,media;wire [9:0] item;
 wire paused,opened,restart,overlay,seek;wire [10:0] cursor;
 integer opens=0,seeks=0,i;
 media_ui_ctrl #(.CLK_HZ(10000),.KEY_SCAN_HZ(100),.DEBOUNCE_SCANS(2),.START_BROWSER(1)) dut(
  .clk(clk),.rst_n(reset_n),.key_col_n(columns),.switches(switches),.key_row_n(rows),
  .video_count(videos),.image_count(images),.music_count(songs),
  .actual_media(2'd0),.actual_index(10'd0),.playback_position(32'd0),.playback_duration(32'd4800000),
  .paused(paused),.has_opened(opened),.restart_pulse(restart),.overlay_enable(overlay),
  .ui_page(page),.media_select(media),.media_index(item),.browser_cursor(cursor),.seek_request(seek));
 always @*begin columns=15;
  if(!rows[0])columns=~keys[3:0];else if(!rows[1])columns=~keys[7:4];
  else if(!rows[2])columns=~keys[11:8];else if(!rows[3])columns=~keys[15:12];
 end
 always @(posedge clk)if(reset_n)begin if(restart)opens=opens+1;if(seek)seeks=seeks+1;end
 task settle;begin repeat(700)@(negedge clk);end endtask
 task key;input integer k;begin keys=16'd1<<k;repeat(800)@(negedge clk);keys=0;settle;end endtask
 task bad;input [511:0] why;begin $display("FAIL ui_start %0s page=%0d opens=%0d",why,page,opens);$finish;end endtask
 initial begin
  repeat(4)@(negedge clk);reset_n=1;settle;
  if(page!=1 || !paused || opened || !overlay || opens!=0)bad("boot must wait in file list");
  for(i=0;i<15;i=i+1)key(i);
  if(opened || opens!=0 || seeks!=0 || page!=1 || !overlay)bad("empty library accepts playback or closes list");
  songs=3;settle;key(2);key(2);
  if(cursor!=2 || opens!=0)bad("audio-only navigation");
  key(0);key(13);if(page!=1 || !overlay || opened)bad("unopened list can be hidden");
  key(3);if(page!=0 || paused || !opened || media!=2 || item!=2 || opens!=1)bad("first explicit open");
  key(13);if(overlay)bad("clean");key(13);if(!overlay)bad("recall");
  key(0);key(1);key(0);if(page!=0 || opens!=1)bad("cancel browser opens item");
  videos=1;images=1;songs=1;settle;key(0);key(2);key(3);
  if(opens!=2 || media>2)bad("mixed library open");
  $display("PASS ui_start: cold boot/empty/one category/mixed, no autoplay, modal protection, explicit open, clean and recall");$finish;
 end
endmodule

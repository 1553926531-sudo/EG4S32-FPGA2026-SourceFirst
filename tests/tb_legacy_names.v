`timescale 1ns/1ps
module tb_legacy_names;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0;reg [11:0] id=0;reg [4:0] character=0;
 wire [7:0] code;
 integer kind,item,column,checks=0;reg [255:0] expected;
 media_library dut(.clk50(clk),.reset_n(reset_n),.system_ready(1'b0),.external_fault(1'b0),
  .rd_accept(1'b0),.rd_data(32'd0),.rd_valid(1'b0),.rd_done(1'b0),.rd_error(1'b0),.card_fatal(1'b0),
  .wr_ready(1'b0),.commit_toggle(1'b0),.audio_done_toggle(1'b0),.audio_write_level(13'd0),.audio_ready(1'b0),
  .pause(1'b0),.restart(1'b0),.media_select(2'd0),.media_index(10'd0),.scale_mode(2'd0),
  .audio_position(32'd0),.audio_position_epoch(1'b0),.seek_request(1'b0),.seek_seconds(16'd0),
  .name_clk(clk),.name_reset_n(reset_n),.name_id(id),.name_char(character),.name_code(code));
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  force dut.legacy_library=1'b1;
  for(kind=0;kind<3;kind=kind+1)for(item=0;item<600;item=item+1)begin
   id={kind[1:0],item[9:0]};character=0;
   expected=kind==0?"VIDEO_000                       ":kind==1?"IMAGE_000                       ":"AUDIO_000                       ";
   expected[207:200]=48+(item+1)/100;
   expected[199:192]=48+((item+1)/10)%10;
   expected[191:184]=48+(item+1)%10;
   repeat(24)@(negedge clk);
   for(column=0;column<32;column=column+1)begin
    character=column;@(negedge clk);
    if(code!==expected[255-column*8-:8])$fatal(1,"FAIL legacy name kind=%0d item=%0d char=%0d got=%h expected=%h",kind,item,column,code,expected[255-column*8-:8]);
    checks=checks+1;
   end
  end
  $display("PASS legacy_names: %0d synchronous characters, 1800 names and decimal boundaries 9/10/99/100/599/600",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL legacy name timeout");end
endmodule

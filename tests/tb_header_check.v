`timescale 1ns/1ps
                                                                           
                                                                         
module tb_header_check;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,external_fault=0,card_fatal=0;
 reg [31:0] metadata_data=0;reg metadata_valid=0;
 reg [31:0] header_input[0:23],descriptor_input[0:7];
 wire [5:0] state;wire [7:0] error_code;
 wire rd_req,rd_ready,wr_valid,audio_valid,publish_toggle;
 media_sequencer_v2 dut(.clk50(clk),.reset_n(reset_n),.system_ready(1'b0),.external_fault(external_fault),
 .rd_req(rd_req),.rd_accept(1'b0),.rd_data(metadata_data),.rd_valid(metadata_valid),.rd_ready(rd_ready),.rd_done(1'b0),.rd_error(1'b0),.card_fatal(card_fatal),
 .wr_valid(wr_valid),.wr_ready(1'b1),.publish_toggle(publish_toggle),.commit_toggle(1'b0),
 .audio_done_toggle(1'b0),.audio_write_level(13'd0),.audio_valid(audio_valid),.audio_ready(1'b1),
 .state(state),.error_code(error_code),.pause(1'b0),.restart(1'b0),.media_select(2'd0),.media_index(10'd0),.scale_mode(2'd0));
 integer cases=0,descriptor_cases=0,fault_cases=0,i,j,cycles,seed=713517;
 reg [31:0] span,samples;
 reg [31:0] test_width,test_height,test_lba,test_stride,test_length;
 task fail;input [255:0] reason;begin
  $display("FAIL header validation case=%0d span=%0d samples=%0d state=%0d err=%h: %0s",cases,span,samples,state,error_code,reason);$finish;
 end endtask
 task check_fault;input card;input [5:0] phase;begin
  @(negedge clk);reset_n=0;external_fault=0;card_fatal=0;
  repeat(3)@(negedge clk);reset_n=1;dut.state=phase;
  external_fault=!card;card_fatal=card;
  #1;if(rd_req || wr_valid || audio_valid)fail("fault output not immediately inhibited");
  @(negedge clk);
  if(publish_toggle || dut.scale_start || dut.audio_start_toggle)fail("side effect during fault capture");
  external_fault=0;card_fatal=0;
  @(negedge clk);
  if(state!=31 || error_code!=(card?8'h02:8'h07) || !dut.audio_flush_toggle)
   fail("one-cycle fault pulse not reported");
  repeat(3)begin @(negedge clk);
   if(rd_req || wr_valid || audio_valid || publish_toggle || !dut.audio_flush_toggle)
    fail("fault repeated flush or media escaped");
  end
  fault_cases=fault_cases+1;
 end endtask
 task load_header;input [31:0] sectors,count;begin
  @(negedge clk);reset_n=0;repeat(3)@(negedge clk);reset_n=1;
  span=sectors;samples=count;
  for(j=0;j<20;j=j+1)header_input[j]=0;
  header_input[0]=32'h314d4654;header_input[1]=2;header_input[2]=1280;header_input[3]=800;
  header_input[4]=1;header_input[5]=1024000;header_input[6]=2;header_input[7]=60000;
  header_input[8]=1;header_input[9]=1;header_input[10]=3;header_input[11]=100;
  header_input[12]=count;header_input[13]=48000;header_input[14]=16;header_input[15]=2;
  header_input[16]=1000;header_input[17]=100+sectors;header_input[18]=3;header_input[19]=1;
  dut.fixed_addresses.address_map.sectors=100+sectors;dut.state=13;
 end endtask
 task feed_metadata;input descriptor_mode;integer m;begin
  dut.state=2;dut.mode=descriptor_mode?1:0;dut.word_index=0;
  if(descriptor_mode)dut.descriptor_input_bad=0;else dut.header_input_bad=0;
  for(m=0;m<(descriptor_mode?8:24);m=m+1)begin
   metadata_valid=1;metadata_data=descriptor_mode?descriptor_input[m]:header_input[m];
   @(posedge clk);
   while(!rd_ready)@(posedge clk);
   @(negedge clk);
  end
  metadata_valid=0;
  while(dut.crc_bytes!=0)@(negedge clk);
  dut.state=descriptor_mode?4:13;
 end endtask
 task check;input expected;begin
  feed_metadata(0);
  cycles=0;
  while(state!=6 && state!=31 && cycles<12)begin
   if(rd_req || wr_valid || audio_valid || publish_toggle)fail("media escaped validation");
   @(negedge clk);cycles=cycles+1;
  end
  if(expected)begin
   if(state!=6 || error_code!=0)fail("valid header rejected");
   if(dut.hold_cycles!==32'd3000000000)fail("maximum dwell multiplication");
  end else if(state!=31 || error_code!=4)fail("invalid header accepted");
  cases=cases+1;
 end endtask
 task load_descriptor;input [31:0] width,height,lba,stride,length;begin
  load_header(1,1);
  header_input[11]=100000;header_input[17]=100001;dut.fixed_addresses.address_map.sectors=100001;
  check(1);
  descriptor_input[0]=32'h32474d49;descriptor_input[1]=0;
  descriptor_input[2]=width;descriptor_input[3]=height;descriptor_input[4]=lba;
  descriptor_input[5]=stride;descriptor_input[6]=length;descriptor_input[7]=0;
  dut.mode=1;dut.state=4;
 end endtask
 task check_descriptor;
  reg expected;
  reg [63:0] row_sectors,payload_sectors,end_lba;
  begin
                                                                         
                                                                         
   row_sectors=({32'd0,descriptor_input[2]}+64'd127)/128;
   payload_sectors={32'd0,descriptor_input[5]}*{32'd0,descriptor_input[3]};
   end_lba={32'd0,descriptor_input[4]}+{32'd0,descriptor_input[6]};
   expected=descriptor_input[0]==32'h32474d49 && descriptor_input[1]==0 &&
    descriptor_input[2]>=1 && descriptor_input[2]<=2048 &&
    descriptor_input[3]>=1 && descriptor_input[3]<=2048 &&
    descriptor_input[4]>=6 && descriptor_input[4]<100000 &&
    descriptor_input[5]==row_sectors && descriptor_input[6]==payload_sectors && end_lba<=100000;
   feed_metadata(1);
   cycles=0;
   while(state!=6 && state!=31 && cycles<8)begin
    if(rd_req || wr_valid || audio_valid || publish_toggle || dut.scale_start)fail("descriptor side effect before validation");
    @(negedge clk);cycles=cycles+1;
   end
   if(expected)begin
    if(state!=6 || error_code!=0 || !dut.scale_start || !dut.image_active ||
       dut.image_lba!==descriptor_input[4] || dut.image_remaining!==descriptor_input[6])fail("legal descriptor rejected");
   end else if(state!=31 || error_code!=8 || dut.scale_start || dut.image_active)fail("invalid descriptor accepted");
   descriptor_cases=descriptor_cases+1;
  end
 endtask
 initial begin
  load_header(1,1);check(1);load_header(1,127);check(1);
  load_header(1,0);check(0);load_header(1,128);check(0);
  load_header(2,128);check(1);load_header(2,254);check(1);
  load_header(2,127);check(0);load_header(2,255);check(0);
  load_header(0,1);check(0);load_header(1360630,172800000);check(1);
  load_header(1360630,172800001);check(0);load_header(1360631,172800000);check(0);
  load_header(32'hfffffff0,1);check(0);
  load_header(1,1);header_input[11]=99;check(0);
  load_header(1,1);header_input[6]=32'h40000002;check(0);
  load_header(1,1);header_input[18]=601;check(0);
  load_header(1,1);header_input[7]=60001;check(0);
  load_header(1,1);header_input[10]=4;check(0);
  for(i=0;i<300;i=i+1)begin
   span=1+($random(seed)&32'h3fffffff)%1360629;
   samples=span*127-(($random(seed)&32'h3fffffff)%127);
   load_header(span,samples);check(1);
   load_header(span,span*127+1);check(0);
   load_header(span,(span-1)*127);check(0);
  end
  load_descriptor(1,1,6,1,1);check_descriptor;
  load_descriptor(127,2048,6,1,2048);check_descriptor;
  load_descriptor(128,2048,6,1,2048);check_descriptor;
  load_descriptor(129,2048,6,2,4096);check_descriptor;
  load_descriptor(2048,2048,67232,16,32768);check_descriptor;
  load_descriptor(2048,2048,67233,16,32768);check_descriptor;
  load_descriptor(128,1,99999,1,1);check_descriptor;
  load_descriptor(128,2,99999,1,2);check_descriptor;
  load_descriptor(128,1,5,1,1);check_descriptor;
  load_descriptor(128,1,100000,1,1);check_descriptor;
  load_descriptor(128,1,32'hfffffff0,1,1);check_descriptor;
  load_descriptor(0,1,6,0,0);check_descriptor;
  load_descriptor(2049,1,6,17,17);check_descriptor;
  load_descriptor(32'h80000080,1,6,1,1);check_descriptor;
  load_descriptor(128,0,6,1,0);check_descriptor;
  load_descriptor(128,2049,6,1,2049);check_descriptor;
  load_descriptor(128,32'h80000001,6,1,1);check_descriptor;
  load_descriptor(128,1,6,32'h80000001,1);check_descriptor;
  load_descriptor(128,1,6,1,32'h80000001);check_descriptor;
  load_descriptor(128,1,6,1,1);descriptor_input[0]=0;check_descriptor;
  load_descriptor(128,1,6,1,1);descriptor_input[1]=1;check_descriptor;
  for(i=0;i<240;i=i+1)begin
   test_width=1+($random(seed)&32'h7fffffff)%2048;
   test_height=1+($random(seed)&32'h7fffffff)%2048;
   test_stride=(test_width+127)/128;test_length=test_stride*test_height;
   test_lba=6+($random(seed)&32'h7fffffff)%(100000-test_length-5);
   case(i%8)
    0:test_width=test_width|32'h80000000;
    1:test_stride=test_stride|32'h40000000;
    2:test_length=test_length+1;
    3:test_height=test_height|32'h10000000;
    4:test_lba=100001-test_length;
    default:begin end
   endcase
   load_descriptor(test_width,test_height,test_lba,test_stride,test_length);check_descriptor;
  end
  for(i=0;i<2;i=i+1)begin
   check_fault(i!=0,0);check_fault(i!=0,1);check_fault(i!=0,5);
   check_fault(i!=0,6);check_fault(i!=0,10);check_fault(i!=0,23);
  end
  $display("PASS header_check: %0d header, %0d descriptor legal/boundary/overflow and %0d one-cycle fault cases, no early media side effects",cases,descriptor_cases,fault_cases);$finish;
 end
 initial begin #5000000;fail("timeout");end
endmodule
module media_extent_map(input [31:0] logical_lba,output [31:0] physical_lba,
 output valid,output [31:0] expected_header_crc,output [31:0] file_sectors);
 reg [31:0] sectors=0;
 assign physical_lba=logical_lba;assign valid=logical_lba<sectors;
 assign expected_header_crc=0;assign file_sectors=sectors;
endmodule


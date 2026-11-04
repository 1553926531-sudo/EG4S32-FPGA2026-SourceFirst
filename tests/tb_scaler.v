`timescale 1ns/1ps
`ifdef SCALER_FULL_TEST
module tb_scaler_full;
 localparam D_W=1280,D_H=800;
`else
module tb_scaler;
 localparam D_W=8,D_H=6;
`endif
 reg clk=0,reset_n=0,start=0,abort=0;always #5 clk=~clk;
 reg [11:0] width=0,height=0;reg [1:0] mode=0;
 wire in_ready,out_valid,busy,done,error;
 wire [19:0] address;wire [31:0] data;
 integer in_index=0,out_index=0,cycles=0,stride=0;
 integer dw,dh,sample_w,sample_h,cx,cy,left,top,sx,sy,ox,oy;
 reg active=0;reg [31:0] expected,last_data;reg [19:0] last_address;reg was_stalled=0;
 wire in_valid=active && in_index<stride*height && (cycles%7!=1);
 wire out_ready=(cycles%5!=0 && cycles%11!=2);
 wire [31:0] input_data=(in_index%stride<width)?(32'h00100000|((in_index/stride)<<12)|(in_index%stride)):32'd0;
 image_scaler #(.DEST_WIDTH(D_W),.DEST_HEIGHT(D_H)) dut(.clk(clk),.reset_n(reset_n),.start(start),.abort(abort),
  .width(width),.height(height),.mode(mode),.in_data(input_data),.in_valid(in_valid),.in_ready(in_ready),
  .out_address(address),.out_data(data),.out_valid(out_valid),.out_ready(out_ready),.busy(busy),.done(done),.error(error));
 always @(posedge clk)if(reset_n)begin
  cycles<=cycles+1;
  if(in_valid && in_ready)in_index<=in_index+1;
  if(was_stalled && (!out_valid || data!==last_data || address!==last_address))begin
   $display("FAIL scaler unstable under backpressure");$finish;
  end
  was_stalled<=out_valid && !out_ready;last_data<=data;last_address<=address;
  if(out_valid && out_ready)begin
   ox=out_index%D_W;oy=out_index/D_W;expected=0;
   if(ox>=left && ox<left+dw && oy>=top && oy<top+dh)begin
    sx=cx+((ox-left)*sample_w)/dw;sy=cy+((oy-top)*sample_h)/dh;
    expected=32'h00100000|(sy<<12)|sx;
   end
   if(address!==out_index || data!==expected)begin
    $display("FAIL scaler %dx%d mode%d pixel%d got=%h exp=%h addr=%d dw=%d dh=%d srcx=%d srcy=%d",width,height,mode,out_index,data,expected,address,dw,dh,dut.source_x,dut.source_row);$finish;
   end
   out_index<=out_index+1;
  end
 end
 task run_case;
  input integer w,h,m;
  begin
   @(negedge clk);width=w;height=h;mode=m;stride=((w+127)/128)*128;
   in_index=0;out_index=0;cx=0;cy=0;sample_w=w;sample_h=h;
   if(m==3)begin
    dw=(w>D_W)?D_W:w;dh=(h>D_H)?D_H:h;sample_w=dw;sample_h=dh;cx=(w-dw)/2;cy=(h-dh)/2;
   end else if(m==2)begin dw=D_W;dh=D_H;end
   else if(w*D_H>=h*D_W)begin dw=D_W;dh=h*D_W/w;if(dh==0)dh=1;end
   else begin dh=D_H;dw=w*D_H/h;if(dw==0)dw=1;end
   left=(D_W-dw)/2;top=(D_H-dh)/2;active=1;start=1;
   @(negedge clk);start=0;
   wait(done);@(negedge clk);active=0;
   if(error || busy || out_index!=D_W*D_H || in_index!=stride*h)begin
    $display("FAIL scaler completion %dx%d mode%d output=%d input=%d expected input=%d",w,h,m,out_index,in_index,stride*h);$finish;
   end
  end
 endtask
 integer w,h,m;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
`ifdef SCALER_FULL_TEST
  run_case(641,479,0);
  run_case(1280,800,1);
  run_case(1920,1080,2);
  run_case(2048,1201,3);
  $display("PASS scaler full: 4096000 reference-checked output pixels at 1280x800, four modes, padded/HD/crop, row padding and backpressure");
  $finish;
`else
  for(m=0;m<4;m=m+1)begin
   for(w=1;w<=12;w=w+1)for(h=1;h<=10;h=h+1)run_case(w,h,m);
   run_case(2048,1,m);run_case(1,2048,m);run_case(127,17,m);run_case(128,9,m);run_case(129,11,m);
  end
  @(negedge clk);width=0;height=3;start=1;@(negedge clk);start=0;
  if(!error || busy)begin $display("FAIL scaler accepted invalid dimensions");$finish;end
  $display("PASS scaler: 500 independent full-pixel geometry cases, all modes, extremes, row padding, backpressure, drain");$finish;
`endif
 end
 initial begin #2000000000;$display("FAIL scaler timeout w=%d h=%d state=%d input=%d output=%d",width,height,dut.state,in_index,out_index);$finish;end
endmodule

`timescale 1ns/1ps
                                                                             
                                                                            
module tb_sd_dma;
 reg clk=0,reset_n=0,req=0;always #10 clk=~clk;
 tri1 cmd;tri1 [3:0] dat;
 wire sdclk,accept,valid,done,err,init,fatal,unused_tx;
 wire [31:0] data;
 reg card_cmd_en=0,card_cmd=1,card_dat_en=0;
 reg [3:0] card_dat=15;
 integer cycles=0,words=0,round=0;
 wire ready=cycles%5!=0 && cycles%211>=80;
 reg stalled=0;reg [31:0] held;
 assign cmd=card_cmd_en?card_cmd:1'bz;
 assign dat=card_dat_en?card_dat:4'bz;
 tf_native_media_reader dut(clk,unused_tx,reset_n,req,32'd12345,accept,data,valid,ready,done,err,init,fatal,sdclk,cmd,dat);
 function [15:0] c16;input [15:0] c;input b;
  begin c16=(c<<1)^((c[15]^b)?16'h1021:16'd0);end
 endfunction
 function [6:0] c7;input [39:0] b;reg [6:0] c;integer j;
  begin c=0;for(j=39;j>=0;j=j-1)c=(c<<1)^((c[6]^b[j])?7'h09:7'h00);c7=c;end
 endfunction
 function [7:0] byte_at;input integer b;begin byte_at=b^8'h5a^(round*8'h37);end endfunction
 function [31:0] word_at;input integer w;
  begin word_at={byte_at(w*4+3),byte_at(w*4+2),byte_at(w*4+1),byte_at(w*4)};end
 endfunction
 reg [47:0] observed,response;
 reg [15:0] c0,c1,c2,c3;
 reg [3:0] nib;
 integer i,j,k;
 initial begin
  for(k=0;k<3;k=k+1)begin
   wait(dut.cmd_state==2);observed=0;
   for(i=0;i<48;i=i+1)begin @(posedge sdclk);observed={observed[46:0],cmd};end
   if(observed[45:40]!=17 || observed[39:8]!=12345 || observed[7:1]!=c7(observed[47:8]))begin
    $display("FAIL CMD17 frame %h",observed);$finish;
   end
   repeat(3)@(negedge sdclk);
   response={2'b00,6'd17,32'd0,7'd0,1'b1};response[7:1]=c7(response[47:8]);
   card_cmd_en=1;
   for(i=47;i>=0;i=i-1)begin card_cmd=response[i];@(negedge sdclk);end
   card_cmd_en=0;
   repeat(4)@(negedge sdclk);
   card_dat_en=1;card_dat=0;@(negedge sdclk);
   c0=0;c1=0;c2=0;c3=0;
   for(j=0;j<1024;j=j+1)begin
    nib=byte_at(j/2);if(j%2==0)nib=byte_at(j/2)>>4;
    card_dat=nib;c0=c16(c0,nib[0]);c1=c16(c1,nib[1]);c2=c16(c2,nib[2]);c3=c16(c3,nib[3]);
    @(negedge sdclk);
   end
   if(k==2)c2=c2^1;
   for(i=15;i>=0;i=i-1)begin card_dat={c3[i],c2[i],c1[i],c0[i]};@(negedge sdclk);end
   card_dat=15;@(negedge sdclk);card_dat_en=0;
   wait(dut.phase==26);
  end
 end
 always @(posedge clk)if(reset_n)begin
  cycles<=cycles+1;
  if(stalled && (!valid || data!==held))begin $display("FAIL SD stalled word changed");$finish;end
  stalled<=valid && !ready;held<=data;
  if(valid && ready)begin
   if(round==2 || data!==word_at(words%128))begin $display("FAIL SD DMA round %d word %d data %h",round,words,data);$finish;end
   words=words+1;
  end
 end
 initial begin
  #61 reset_n=1;
                                                                              
  @(negedge clk);dut.startup_count=100000;dut.phase=26;dut.bus_4bit=1;
  dut.high_capacity=1;dut.rca=1;dut.half_period=0;
  @(negedge clk);req=1;wait(accept);@(negedge clk);req=0;
  wait(done);#1;if(err || words!=128)begin $display("FAIL SD good sector err=%d words=%d",err,words);$finish;end
  round=1;@(negedge clk);req=1;wait(accept);@(negedge clk);req=0;
  wait(done);#1;
  if(err || words!=256 || fatal)begin $display("FAIL SD second sector err=%d words=%d",err,words);$finish;end
  round=2;@(negedge clk);req=1;wait(accept);@(negedge clk);req=0;
  wait(done);#1;
  if(!err || words!=256 || fatal)$display("FAIL SD CRC rejection err=%d words=%d",err,words);
  else $display("PASS sd_dma: actual CMD17, two distinct 512-byte sectors, long and intermittent backpressure with stable output; corrupt lane CRC rejected before any DMA word");
  $finish;
 end
 initial begin #1000000;$display("FAIL SD DMA timeout phase=%d cmd=%d words=%d",dut.phase,dut.cmd_state,words);$finish;end
endmodule

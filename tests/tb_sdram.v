`timescale 1ns/1ps
module tb_sdram;
 reg clk=0,reset_n=0,req=0,write=0;
 always #6 clk=~clk;
 reg [20:0] address=0;
 wire ready,done,init,wr_ready,rd_valid,fault;
 wire [31:0] rd;
 integer wi=0,ri=0;
 reg [31:0] seed=0,expect_seed=0;
 sdram_burst #(.INIT_CYCLES(20),.REFRESH_CYCLES(600)) dut(
  clk,reset_n,req,write,address,ready,done,init,seed+wi,1'b1,wr_ready,rd,rd_valid,fault);
 always @(posedge clk)if(reset_n)begin
  if(wr_ready)wi<=wi+1;
  if(rd_valid)begin
   if(rd!==(expect_seed+ri))begin $display("FAIL SDRAM word %d got %h expected %h",ri,rd,expect_seed+ri);$finish;end
   ri=ri+1;
  end
 end
 task put;input [20:0] a;input [31:0] d;
  begin wait(ready);@(negedge clk);address=a;seed=d;wi=0;write=1;req=1;
   @(negedge clk);req=0;wait(done);@(negedge clk);
   if(wi!=128)begin $display("FAIL write count %d",wi);$finish;end
  end
 endtask
 task get;input [20:0] a;input [31:0] d;
  begin wait(ready);@(negedge clk);address=a;expect_seed=d;ri=0;write=0;req=1;
   @(negedge clk);req=0;wait(done);@(negedge clk);
   if(ri!=256)begin $display("FAIL read count %d",ri);$finish;end
  end
 endtask
 initial begin
  #31 reset_n=1;wait(init);
  put(0,32'h12340000);put(128,32'h12340080);
  put(1048576,32'habcd0000);put(1048704,32'habcd0080);
  get(0,32'h12340000);get(1048576,32'habcd0000);
  if(fault)$display("FAIL SDRAM fault");else $display("PASS sdram: 512 written/read words across both banks, CAS3, refresh arbitration");
  $finish;
 end
 initial begin #100000;$display("FAIL SDRAM timeout");$finish;end
endmodule

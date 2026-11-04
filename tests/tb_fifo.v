`timescale 1ns/1ps
module tb_fifo;
 reg clk=0, wclk=0, rclk=0, reset_n=0;
 always #5 clk=~clk;
 always #7 wclk=~wclk;
 always #11 rclk=~rclk;
 reg [31:0] sin=0, ain=0;
 reg sv=0,sr=0,av=0,ar=0;
 wire si,so,ai,ao;
 wire [31:0] sout,aout;
 wire [4:0] sl;
 wire [4:0] wl,rl;
 sync_stream_fifo #(.AW(4)) s(clk,reset_n,sin,sv,si,sout,so,sr,sl);
 async_stream_fifo #(.AW(4)) a(wclk,reset_n,ain,av,ai,wl,rclk,reset_n,aout,ao,ar,rl,1'b0);
 integer sent=0,got=0,asent=0,agot=0,cycle=0;
 always @(negedge clk)if(reset_n)begin
  cycle=cycle+1;sv=(sent<10000 && cycle%7!=0);sr=(cycle%5!=1);
 end
 always @(posedge clk)if(reset_n)begin
  if(sv && si)begin sent=sent+1;sin<=sent;end
  if(so && sr)begin
   if(sout!==got)begin $display("FAIL sync got=%h expected=%h",sout,got);$finish;end
   got=got+1;
  end
 end
 always @(negedge wclk)if(reset_n)av=(asent<10000 && $random%4!=0);
 always @(negedge rclk)if(reset_n)ar=($random%3!=0);
 always @(posedge wclk)if(reset_n && av && ai)begin asent=asent+1;ain<=asent;end
 always @(posedge rclk)if(reset_n && ao && ar)begin
  if(aout!==agot)begin $display("FAIL async got=%h expected=%h",aout,agot);$finish;end
  agot=agot+1;
 end
 initial begin
  #41 reset_n=1;
  wait(got==10000 && agot==10000);
  #100;$display("PASS fifo: 10000 sync + 10000 async words with wrap/backpressure");$finish;
 end
 initial begin #1000000;$display("FAIL FIFO timeout");$finish;end
endmodule

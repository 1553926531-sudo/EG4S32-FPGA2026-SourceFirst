`timescale 1ns/1ps
                                                                 
                                                                          
module status_uart #(parameter integer REPORT_CYCLES=50000000)(input wire clk50,input wire reset_n,input wire [5:0] state,
 input wire [7:0] error_code,input wire [7:0] flags,input wire [31:0] lba,
 input wire [19:0] frame_word,output reg tx);
 localparam integer INTERVAL_BITS=(REPORT_CYCLES<2)?1:$clog2(REPORT_CYCLES);
 reg [INTERVAL_BITS-1:0] interval;
 reg [4:0] index;
 reg [5:0] baud;
 reg [3:0] bit_no;
 reg [9:0] shift;
 reg busy,report;
 reg [5:0] state_q;reg [7:0] error_q,flags_q;reg [31:0] lba_q;reg [19:0] word_q;
 reg [7:0] ch;reg [3:0] nibble;
 function [7:0] hexchar;input [3:0] n;begin hexchar=n<10?8'h30+n:8'h41+n-10;end endfunction
                                                                           
                                                                           
 always @* begin
  nibble=0;
  case(index)
   4:nibble={2'b0,state_q[5:4]};5:nibble=state_q[3:0];
   7:nibble=error_q[7:4];8:nibble=error_q[3:0];
   10:nibble=flags_q[7:4];11:nibble=flags_q[3:0];
   13:nibble=lba_q[31:28];14:nibble=lba_q[27:24];
   15:nibble=lba_q[23:20];16:nibble=lba_q[19:16];
   17:nibble=lba_q[15:12];18:nibble=lba_q[11:8];
   19:nibble=lba_q[7:4];20:nibble=lba_q[3:0];
   22:nibble=word_q[19:16];23:nibble=word_q[15:12];
   24:nibble=word_q[11:8];25:nibble=word_q[7:4];26:nibble=word_q[3:0];
   default:begin end
  endcase
 end
 always @* begin
  ch=" ";
  case(index)
   0:ch="T";1:ch="F";2:ch="M";
   4,5,7,8,10,11,13,14,15,16,17,18,19,20,22,23,24,25,26:ch=hexchar(nibble);
   27:ch=13;28:ch=10;default:begin end
  endcase
 end
 always @(posedge clk50)begin
  if(!reset_n)begin interval<=0;index<=0;baud<=0;bit_no<=0;shift<=10'h3ff;tx<=1;
   busy<=0;report<=0;state_q<=0;error_q<=0;flags_q<=0;lba_q<=0;word_q<=0;end
  else begin
   if(interval==REPORT_CYCLES-1)begin
    interval<=0;
    if(!report)begin report<=1;index<=0;state_q<=state;error_q<=error_code;
     flags_q<=flags;lba_q<=lba;word_q<=frame_word;end
   end else interval<=interval+1'b1;
   if(!busy && report)begin shift<={1'b1,ch,1'b0};tx<=0;baud<=0;bit_no<=0;busy<=1;end
   else if(busy)begin
    if(baud==49)begin
     baud<=0;
     if(bit_no==9)begin busy<=0;tx<=1;if(index==28)report<=0;else index<=index+1'b1;end
     else begin shift<={1'b1,shift[9:1]};tx<=shift[1];bit_no<=bit_no+1'b1;end
    end else baud<=baud+1'b1;
   end
  end
 end
endmodule

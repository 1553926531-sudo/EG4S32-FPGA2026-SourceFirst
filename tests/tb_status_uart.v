`timescale 1ns/1ps
                                                                          
module tb_status_uart;
 reg clk=0,reset_n=0;always #1 clk=~clk;
 reg [5:0] state=0;reg [7:0] error_code=0,flags=0;
 reg [31:0] lba=0;reg [19:0] frame_word=0;
 wire tx;
 reg [231:0] expected;reg [215:0] formatted;
 reg [7:0] received,expected_byte;
 integer i,j,k,checked=0;
 status_uart #(.REPORT_CYCLES(20000)) dut(.clk50(clk),.reset_n(reset_n),
  .state(state),.error_code(error_code),.flags(flags),.lba(lba),.frame_word(frame_word),.tx(tx));
 task receive;
  begin
   @(negedge tx);
   repeat(25)@(negedge clk);
   if(tx!==0)begin $display("FAIL UART start bit");$finish;end
   for(j=0;j<8;j=j+1)begin repeat(50)@(negedge clk);received[j]=tx;end
   repeat(50)@(negedge clk);
   if(tx!==1)begin $display("FAIL UART stop bit");$finish;end
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  for(k=0;k<16;k=k+1)begin
                                                                           
   state=k*3;error_code=k*17;flags=(15-k)*17;
   lba=32'h01234567+32'h11111111*k;frame_word=20'h89abc+20'h11111*k;
   $sformat(formatted,"TFM %02X %02X %02X %08X %05X",state,error_code,flags,lba,frame_word);
   expected={formatted,8'd13,8'd10};
   for(i=0;i<29;i=i+1)begin
    receive;
    expected_byte=expected[231:224];
                                                                   
    if(expected_byte>=8'd97 && expected_byte<=8'd102)expected_byte=expected_byte-8'd32;
    if(received!==expected_byte)begin
     $display("FAIL UART report=%0d byte=%0d got=%h expected=%h",k,i,received,expected_byte);$finish;
    end
    expected={expected[223:0],8'd0};checked=checked+1;
                                                                              
    if(i==0)begin state=~state;error_code=~error_code;flags=~flags;lba=~lba;frame_word=~frame_word;end
   end
  end
                                                                           
  @(negedge tx);repeat(55)@(negedge clk);reset_n=0;
  repeat(3)@(negedge clk);if(tx!==1)begin $display("FAIL UART reset idle");$finish;end
  $display("PASS status_uart: %0d wire-decoded bytes, all hexadecimal fields, immutable snapshots, reset abort, 1 Mbaud 8N1",checked);$finish;
 end
 initial begin #2000000;$display("FAIL UART timeout");$finish;end
endmodule

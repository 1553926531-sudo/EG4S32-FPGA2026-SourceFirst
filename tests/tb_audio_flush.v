`timescale 1ns/1ps
                                                                           
                                                                  
module audio_flush_case #(parameter W_HALF=5, R_HALF=1, ID=0)(output reg passed=0);
 reg wclk=0, mclk=0, reset_n=0;
 always #(W_HALF) wclk=~wclk;
 always #(R_HALF) mclk=~mclk;
 reg [31:0] in_data=0;
 reg in_valid=0;
 wire in_ready;
 wire [4:0] write_level,read_level;
 wire [31:0] sample_data;
 wire sample_valid,sample_ready;
 reg start_toggle=0, flush_toggle=0;
 wire done_toggle,underrun,bclk,lrclk,sdata;
 reg paused=0;
 reg [31:0] total_samples=2;
 reg [31:0] expected[0:31];
 integer consumed=0, allowed=0, epoch, n, before_count;

 async_stream_fifo #(.WIDTH(32),.AW(4)) fifo(
   .wclk(wclk),.wrst_n(reset_n),.in_data(in_data),.in_valid(in_valid),
   .in_ready(in_ready),.write_level(write_level),.rclk(mclk),.rrst_n(reset_n),
   .out_data(sample_data),.out_valid(sample_valid),.out_ready(sample_ready),
   .read_level(read_level),.flush_toggle(flush_toggle));
 i2s_player player(.mclk(mclk),.reset_n(reset_n),.start_toggle(start_toggle),
   .total_samples(total_samples),.done_toggle(done_toggle),.underrun(underrun),
   .sample_data(sample_data),.sample_valid(sample_valid),.sample_ready(sample_ready),
   .bclk(bclk),.lrclk(lrclk),.sdata(sdata),.pause(paused),.flush_toggle(flush_toggle));

 task push_sample;
   input [31:0] value;
   begin
     @(negedge wclk); in_data=value; in_valid=1'b1;
     while (!in_ready) @(negedge wclk);
     @(negedge wclk); in_valid=1'b0;
   end
 endtask

 always @(posedge mclk) begin
   if (reset_n && sample_ready && sample_valid) begin
     if (consumed>=allowed || sample_data !== expected[consumed]) begin
       $display("FAIL audio flush case=%d word=%d got=%h expected=%h allowed=%d",
                ID,consumed,sample_data,expected[consumed],allowed); $finish;
     end
     consumed=consumed+1;
   end
 end

 task flush_and_check;
   begin
     @(negedge mclk); flush_toggle=~flush_toggle;
     repeat (32) @(negedge wclk);
     repeat (32) @(negedge mclk);
     if (read_level !== 0 || write_level !== 0 || sample_valid !== 0 ||
         player.running !== 0 || underrun || done_toggle !== start_toggle) begin
       $display("FAIL audio flush case=%d epoch=%d read=%d write=%d valid=%b running=%b done=%b start=%b",
                ID,epoch,read_level,write_level,sample_valid,player.running,done_toggle,start_toggle);
       $finish;
     end
   end
 endtask

 task play_pair;
   input [31:0] base;
   begin
     total_samples=2;
     expected[allowed]=base; expected[allowed+1]=base+1; allowed=allowed+2;
     push_sample(base); push_sample(base+1);
     repeat (16) @(negedge mclk);
     @(negedge mclk); paused=0; start_toggle=~start_toggle;
     repeat (8) @(negedge mclk);
     if(done_toggle===start_toggle) begin
       $display("FAIL audio flush premature completion case=%d epoch=%d",ID,epoch); $finish;
     end
     wait(done_toggle===start_toggle);
     @(negedge mclk);
     if(underrun || consumed!=allowed) begin
       $display("FAIL audio flush completion case=%d consumed=%d expected=%d underrun=%b",
                ID,consumed,allowed,underrun); $finish;
     end
   end
 endtask

 initial begin
   #13 reset_n=1;
   push_sample(32'hdead0001);
   push_sample(32'hdead0002);
   repeat (24) @(posedge mclk);
   flush_and_check;
   play_pair(32'hbeef0001);
                                                                          
                                                                        
   for(epoch=0;epoch<4;epoch=epoch+1) begin
     total_samples=8; before_count=consumed;
     expected[allowed]=32'ha0000000+epoch*16; allowed=allowed+1;
     for(n=0;n<8;n=n+1) push_sample(32'ha0000000+epoch*16+n);
     repeat(16) @(negedge mclk);
     @(negedge mclk); start_toggle=~start_toggle;
     wait(consumed==before_count+1);
     @(negedge mclk); paused=1;
     flush_and_check;
     play_pair(32'hb0000000+epoch*16);
                                                                           
     flush_and_check;
   end
   passed=1;
 end
endmodule

module tb_audio_flush;
 wire a,b;
 audio_flush_case #(.W_HALF(5),.R_HALF(1),.ID(0)) fast_read(a);
 audio_flush_case #(.W_HALF(1),.R_HALF(7),.ID(1)) fast_write(b);
 initial begin
   wait(a&&b);
   $display("PASS audio_flush: idle/running cancellation, repeated epochs, both clock ratios"); $finish;
 end
 initial begin #500000; $display("FAIL audio flush timeout"); $finish; end
endmodule

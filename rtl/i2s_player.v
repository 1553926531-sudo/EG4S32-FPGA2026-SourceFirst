`timescale 1ns/1ps
                                                                         
                                                                            
module i2s_player #(parameter VOLUME_CONTROL=0)(input wire mclk, input wire reset_n,
 input wire start_toggle, input wire [31:0] total_samples,
 output reg done_toggle, output reg underrun,
 input wire [31:0] sample_data, input wire sample_valid, output wire sample_ready,
 output wire bclk, output wire lrclk, output reg sdata,
 input wire pause, input wire flush_toggle,output reg [31:0] playhead_gray,
 output reg playhead_epoch,input wire [4:0] volume,input wire muted);
 wire signed [5:0] gain=VOLUME_CONTROL?((muted || volume>16)?6'sd0:$signed({1'b0,volume})):6'sd16;
 wire signed [21:0] left_scaled=$signed(sample_data[15:0])*gain;
 wire signed [21:0] right_scaled=$signed(sample_data[31:16])*gain;
 wire [31:0] scaled_sample={right_scaled[19:4],left_scaled[19:4]};
 reg [7:0] phase;
 (* async_reg="true" *) reg start_sync1,start_sync2;
                                                                         
                                                                              
 (* keep = "true" *) (* async_reg="true" *) reg [31:0] count_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg [31:0] count_sync2;                 
 (* async_reg="true" *) reg flush_sync1,flush_sync2;
 reg flush_seen;
 reg seen, running;
 reg [31:0] remaining,current_sample;
 reg [31:0] played_samples;
 wire [31:0] played_next=played_samples+1'b1;
 wire sample_boundary=(phase==8'hff);
 wire pause_safe=(pause === 1'b1);
 assign bclk=phase[1];
 assign lrclk=phase[7];
                                                                          
                                                                           
                                       
 assign sample_ready=running && remaining!=0 && sample_boundary && !underrun && !pause_safe &&
                     (flush_sync2==flush_seen);
 always @(posedge mclk) begin
  if(!reset_n) begin
   phase<=0; start_sync1<=0;start_sync2<=0;seen<=0;running<=0;
   done_toggle<=0;underrun<=0;remaining<=0;current_sample<=0;sdata<=0;
   count_sync1<=0;count_sync2<=0;flush_sync1<=0;flush_sync2<=0;flush_seen<=0;
   played_samples<=0;playhead_gray<=0;playhead_epoch<=0;
  end else begin
   phase<=phase+1'b1; start_sync1<=start_toggle;start_sync2<=start_sync1;
   count_sync1<=total_samples;count_sync2<=count_sync1;
   flush_sync1 <= (flush_toggle === 1'b1);
   flush_sync2 <= flush_sync1;
   if(flush_sync2 != flush_seen) begin
                                                                            
                                                                            
    flush_seen<=flush_sync2; seen<=start_sync2; done_toggle<=start_sync2; running<=0;
    remaining<=0; current_sample<=0; underrun<=0;
    played_samples<=0;playhead_gray<=0;
   end else begin
    if(start_sync2!=seen && !running) begin
     seen<=start_sync2; remaining<=count_sync2; running<=1;
     played_samples<=0;playhead_gray<=0;playhead_epoch<=start_sync2;
    end
    if(sample_boundary) begin
     if(running && remaining!=0) begin
      if(pause_safe) begin current_sample<=0; end
      else if(sample_valid) begin
       current_sample<=scaled_sample;remaining<=remaining-1'b1;
       played_samples<=played_next;playhead_gray<=played_next^(played_next>>1);
      end
      else begin underrun<=1;running<=0;current_sample<=0;end
     end else begin
      current_sample<=0;
      if(running) begin running<=0; done_toggle<=seen; end
     end
    end
   end
   if(phase[1:0]==2'b11) begin
    if(phase[7:2]<=15) sdata<=current_sample[15-phase[7:2]];
    else if(phase[7:2]>=32 && phase[7:2]<=47) sdata<=current_sample[47-phase[7:2]+16];
    else sdata<=0;
   end
  end
 end
endmodule

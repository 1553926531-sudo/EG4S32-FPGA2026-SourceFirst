`timescale 1ns/1ps
                                                                           
                                                                           
                                                                           
module audio_waveform(input wire pclk,input wire reset_n,
 input wire [15:0] pcm,input wire sample_toggle,input wire flush_toggle,
 input wire frame_tick,input wire [8:0] read_index,
 output wire [9:0] sample_y,output wire sample_valid);
 (* async_reg="true" *) reg toggle_s1,toggle_s2,flush_s1,flush_s2;
                                                                         
                                                                       
 (* async_reg="true" *) reg [7:0] pcm_s1,pcm_s2;
 reg sample_seen,flush_seen;
 reg [8:0] write_pointer,frame_pointer;
 reg [9:0] count,frame_count;
 reg read_valid;
 wire flushing=(flush_s2!=flush_seen);
 wire store=(toggle_s2!=sample_seen) && !flushing;
 wire [8:0] read_address=frame_pointer+read_index;
 wire [7:0] value;
 eg_dual_clock_mem #(.WIDTH(8),.AW(9),.IMPLEMENT("9K")) history(
  .wclk(pclk),.wrst(!reset_n),.we(store),.waddr(write_pointer),.wdata(pcm_s2),
  .rclk(pclk),.rrst(!reset_n),.re(1'b1),.raddr(read_address),.rdata(value));
 wire signed [10:0] signed_value={{3{value[7]}},value};
 wire signed [10:0] y_value=11'sd720-(signed_value>>>1);
 assign sample_y=y_value[9:0];
                                                                         
 assign sample_valid=read_valid;
 always @(posedge pclk)begin
  if(!reset_n)begin
   toggle_s1<=0;toggle_s2<=0;pcm_s1<=0;pcm_s2<=0;sample_seen<=0;
   flush_s1<=0;flush_s2<=0;flush_seen<=0;
   write_pointer<=0;frame_pointer<=0;count<=0;frame_count<=0;read_valid<=0;
  end else begin
   toggle_s1<=(sample_toggle===1'b1);toggle_s2<=toggle_s1;
   pcm_s1<=pcm[15:8];pcm_s2<=pcm_s1;
   flush_s1<=(flush_toggle===1'b1);flush_s2<=flush_s1;
   read_valid<=({1'b0,read_index}<frame_count);
   if(flushing)begin
    flush_seen<=flush_s2;sample_seen<=toggle_s2;
    write_pointer<=0;frame_pointer<=0;count<=0;frame_count<=0;read_valid<=0;
   end else begin
    if(store)begin
     sample_seen<=toggle_s2;write_pointer<=write_pointer+1'b1;
     if(count<512)count<=count+1'b1;
    end
    if(frame_tick)begin
     frame_count<=count;
     frame_pointer<=(count==512)?write_pointer:9'd0;
    end
   end
  end
 end
endmodule

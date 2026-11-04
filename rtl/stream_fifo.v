`timescale 1ns/1ps
                                                                             
                                                                            
                                                                                
module sync_stream_fifo #(parameter WIDTH=32, parameter AW=12)(
 input wire clk, input wire reset_n,
 input wire [WIDTH-1:0] in_data, input wire in_valid, output wire in_ready,
 output wire [WIDTH-1:0] out_data, output reg out_valid, input wire out_ready,
 output wire [AW:0] level);
 localparam DEPTH=(1<<AW);
 reg [AW-1:0] wp, rp;
 reg [AW:0] used;
 wire put=in_valid && in_ready;
 wire fetch=(used!=0) && (!out_valid || out_ready);
 assign in_ready=(used < DEPTH-1);
 assign level=used + out_valid;
 eg_dual_clock_mem #(.WIDTH(WIDTH),.AW(AW),
                     .IMPLEMENT((WIDTH*DEPTH >= 200000) ? "32K" : "9K"))
 mem(.wclk(clk),.wrst(!reset_n),.we(put),.waddr(wp),.wdata(in_data),
     .rclk(clk),.rrst(!reset_n),.re(reset_n && fetch),.raddr(rp),.rdata(out_data));
 always @(posedge clk) begin
  if(!reset_n) begin wp<=0; rp<=0; used<=0; out_valid<=0; end
  else begin
   if(put) wp<=wp+1'b1;
   if(out_ready) out_valid<=0;
   if(fetch) begin rp<=rp+1'b1; out_valid<=1; end
   case({put,fetch}) 2'b10:used<=used+1'b1; 2'b01:used<=used-1'b1; default:begin end endcase
  end
 end
endmodule

module async_stream_fifo #(parameter WIDTH=32, parameter AW=10)(
 input wire wclk, input wire wrst_n, input wire [WIDTH-1:0] in_data,
 input wire in_valid, output wire in_ready, output wire [AW:0] write_level,
 input wire rclk, input wire rrst_n, output wire [WIDTH-1:0] out_data,
 output reg out_valid, input wire out_ready, output wire [AW:0] read_level,
                                                                          
                                                            
 input wire flush_toggle);
 localparam DEPTH=(1<<AW);
 reg [AW:0] wbin,wgray,rbin,rgray;
                                                                         
                                                                       
                                                                
 (* keep = "true" *) (* async_reg="true" *) reg [AW:0] rgray_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg [AW:0] rgray_sync2;                 
 (* keep = "true" *) (* async_reg="true" *) reg [AW:0] wgray_sync1;                 
 (* keep = "true" *) (* async_reg="true" *) reg [AW:0] wgray_sync2;                 
 (* async_reg="true" *) reg flush_wsync1,flush_wsync2,flush_rsync1,flush_rsync2;
 (* async_reg="true" *) reg rseen_sync1,rseen_sync2,wseen_sync1,wseen_sync2;
 reg flush_wseen,flush_rseen;
 function [AW:0] ungray;
  input [AW:0] g; integer i;
  begin ungray[AW]=g[AW]; for(i=AW-1;i>=0;i=i-1) ungray[i]=ungray[i+1]^g[i]; end
 endfunction
 wire [AW:0] next_w=wbin+1'b1;
 wire [AW:0] next_wgray=(next_w>>1)^next_w;
 wire full=(wgray=={~rgray_sync2[AW:AW-1],rgray_sync2[AW-2:0]});
 wire empty=(rgray==wgray_sync2);
 wire put=in_valid && in_ready;
                                                                        
                                                                             
                                                                             
                                                                           
                                                        
 wire write_epoch_ready=(flush_wsync2==flush_wseen) && (rseen_sync2==flush_wseen);
 wire read_epoch_ready=(flush_rsync2==flush_rseen) && (wseen_sync2==flush_rseen);
 wire fetch=read_epoch_ready && !empty && (!out_valid || out_ready);
 assign in_ready=wrst_n && write_epoch_ready && !full;
 assign write_level=write_epoch_ready ? wbin-ungray(rgray_sync2) : 0;
 assign read_level=read_epoch_ready ? ungray(wgray_sync2)-rbin+out_valid : 0;
 eg_dual_clock_mem #(.WIDTH(WIDTH),.AW(AW),
                     .IMPLEMENT((WIDTH*DEPTH >= 200000) ? "32K" : "9K"))
 mem(.wclk(wclk),.wrst(!wrst_n),.we(put),.waddr(wbin[AW-1:0]),.wdata(in_data),
     .rclk(rclk),.rrst(!rrst_n),.re(rrst_n && fetch),.raddr(rbin[AW-1:0]),.rdata(out_data));
 always @(posedge wclk) begin
  if(!wrst_n) begin
   wbin<=0; wgray<=0; rgray_sync1<=0; rgray_sync2<=0;
   flush_wsync1<=0; flush_wsync2<=0; flush_wseen<=0;
   rseen_sync1<=0;rseen_sync2<=0;
  end else begin
   flush_wsync1 <= (flush_toggle === 1'b1);
   flush_wsync2 <= flush_wsync1;
   rseen_sync1<=flush_rseen;rseen_sync2<=rseen_sync1;
   if(flush_wsync2 != flush_wseen) begin
    flush_wseen <= flush_wsync2;
    wbin <= 0; wgray <= 0; rgray_sync1 <= 0; rgray_sync2 <= 0;
   end else if(!write_epoch_ready) begin
    rgray_sync1<=0;rgray_sync2<=0;
   end else begin
    rgray_sync1<=rgray; rgray_sync2<=rgray_sync1;
    if(put) begin wbin<=next_w; wgray<=next_wgray; end
   end
  end
 end
 always @(posedge rclk) begin
  if(!rrst_n) begin
   rbin<=0; rgray<=0; wgray_sync1<=0; wgray_sync2<=0;
   out_valid<=0;
   flush_rsync1<=0; flush_rsync2<=0; flush_rseen<=0;
   wseen_sync1<=0;wseen_sync2<=0;
  end else begin
   flush_rsync1 <= (flush_toggle === 1'b1);
   flush_rsync2 <= flush_rsync1;
   wseen_sync1<=flush_wseen;wseen_sync2<=wseen_sync1;
   if(flush_rsync2 != flush_rseen) begin
    flush_rseen <= flush_rsync2;
    rbin <= 0; rgray <= 0; wgray_sync1 <= 0; wgray_sync2 <= 0;
    out_valid <= 0;
   end else if(!read_epoch_ready) begin
    wgray_sync1<=0;wgray_sync2<=0;out_valid<=0;
   end else begin
    wgray_sync1<=wgray; wgray_sync2<=wgray_sync1;
    if(out_ready) out_valid<=0;
    if(fetch) begin
     out_valid<=1;
     rbin<=rbin+1'b1; rgray<=((rbin+1'b1)>>1)^(rbin+1'b1);
    end
   end
  end
 end
endmodule

module reset_release(input wire clk, input wire async_reset_n, output wire reset_n);
                                                                        
                                                                         
                                                                            
                                                                          
                                                                         
                                                                      
                                                                            
                                                               
 (* async_reg="true" *) reg sync1 = 1'b0;
 (* async_reg="true" *) reg sync2 = 1'b0;
 (* async_reg="true" *) reg sync3 = 1'b0;
 always @(posedge clk) begin
  if(!async_reset_n) begin
   sync1<=1'b0; sync2<=1'b0; sync3<=1'b0;
  end else begin
   sync1<=1'b1; sync2<=sync1; sync3<=sync2;
  end
 end
 assign reset_n=sync3;
endmodule

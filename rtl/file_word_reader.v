`timescale 1ns/1ps
module file_word_reader(
 input wire clk,input wire reset_n,input wire invalidate,
 input wire request,input wire [8:0] file_id,input wire [40:0] offset,input wire [2:0] bytes,
 output wire accept,output reg done,output reg error,output reg [31:0] data,
 output wire file_req,output wire [8:0] file_select,output wire [31:0] file_sector,
 input wire file_accept,input wire [31:0] file_data,input wire file_valid,
 output wire file_ready,input wire file_done,input wire file_error
);
 localparam IDLE=0,CHECK=1,FETCH=2,RECEIVE=3,WAIT_DONE=4,READ_WAIT=5,READ_GOT=6,FINISH=7;
 reg [2:0] state;
 reg [8:0] current_file,cached_file;
 reg [40:0] address;
 reg [31:0] cached_sector,partial;
 reg [2:0] count,total;
 reg [6:0] word_address,write_address;
 reg cache_valid,second;
 wire [31:0] ram_data;
 wire store=state==RECEIVE && file_valid;
 wire [2:0] available=3'd4-{1'b0,address[1:0]};
 wire [31:0] shifted=ram_data>>{address[1:0],3'b000};
 eg_dual_clock_mem #(.WIDTH(32),.AW(7),.IMPLEMENT("9K")) cache(
  .wclk(clk),.wrst(!reset_n),.we(store),.waddr(write_address),.wdata(file_data),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(word_address),.rdata(ram_data));
 assign accept=state==IDLE && request;
 assign file_req=state==FETCH;
 assign file_select=current_file;
 assign file_sector=address[40:9];
 assign file_ready=state==RECEIVE;
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=IDLE;done<=0;error<=0;data<=0;current_file<=0;cached_file<=0;
   address<=0;cached_sector<=0;partial<=0;count<=0;total<=0;word_address<=0;write_address<=0;
   cache_valid<=0;second<=0;
  end else begin
   done<=0;
   if(invalidate)cache_valid<=0;
   case(state)
    IDLE:if(request)begin
     current_file<=file_id;address<=offset;count<=bytes;total<=bytes;second<=0;partial<=0;error<=0;
     if(bytes<1 || bytes>4)begin error<=1;state<=FINISH;end else state<=CHECK;
    end
    CHECK:begin
     word_address<=address[8:2];
     if(cache_valid && !invalidate && cached_file==current_file && cached_sector==address[40:9])state<=READ_WAIT;
     else begin cache_valid<=0;state<=FETCH;end
    end
    FETCH:if(file_accept)begin write_address<=0;state<=RECEIVE;end
    RECEIVE:begin
     if(file_valid)begin
      write_address<=write_address+1'b1;
      if(write_address==127)state<=WAIT_DONE;
     end
     if(file_done && file_error)begin error<=1;state<=FINISH;end
    end
    WAIT_DONE:if(file_done)begin
     if(file_error)begin error<=1;state<=FINISH;end
     else begin cache_valid<=1;cached_file<=current_file;cached_sector<=address[40:9];state<=READ_WAIT;end
    end
    READ_WAIT:state<=READ_GOT;
    READ_GOT:begin
     if(second)begin data<=partial|(shifted<<{(total-count),3'b000});state<=FINISH;end
     else if(count>available)begin
      partial<=shifted;count<=count-available;address<=(address+41'd4)&~41'd3;second<=1;state<=CHECK;
     end else begin data<=shifted;state<=FINISH;end
    end
    FINISH:begin done<=1;state<=IDLE;end
    default:begin error<=1;state<=FINISH;end
   endcase
  end
 end
endmodule

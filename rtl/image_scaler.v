`timescale 1ns/1ps
                                                                             
                                                                            
                                                                              
module image_scaler #(parameter DEST_WIDTH=1280,DEST_HEIGHT=800)(
 input wire clk,input wire reset_n,input wire start,input wire abort,
 input wire [11:0] width,input wire [11:0] height,input wire [1:0] mode,
 input wire [31:0] in_data,input wire in_valid,output wire in_ready,
 output wire [19:0] out_address,output wire [31:0] out_data,
 output wire out_valid,input wire out_ready,
 output wire busy,output reg done,output reg error);
 localparam IDLE=0,DIVIDE=1,GEOMETRY=2,FILL=3,EMIT=4,X_STEP=5,Y_STEP=6,DRAIN=7;
 reg [3:0] state;
 reg [11:0] source_width,source_height,stride;
 reg [11:0] draw_width,draw_height,sample_width,sample_height,crop_x,crop_y;
 reg [11:0] left_edge,top_edge,right_edge,bottom_edge;
 reg [11:0] input_x,source_row,next_source_y,source_x,out_x,out_y;
 reg [12:0] x_accum,y_accum;
 reg [20:0] output_count;
 reg source_complete;
 reg [31:0] dividend,quotient;
 reg [16:0] remainder;
 reg [15:0] divisor;
 reg [5:0] divide_count;
 reg divide_height;
 wire [16:0] divide_trial={remainder[15:0],dividend[31]};
 wire divide_ge=divide_trial>={1'b0,divisor};
 wire [31:0] quotient_next={quotient[30:0],divide_ge};
 wire filling=state==FILL;
 wire inside_image=out_x>=left_edge && out_x<right_edge &&
                        out_y>=top_edge && out_y<bottom_edge;
 wire [31:0] row_pixel;
 wire row_write=in_valid && in_ready && filling && input_x<source_width && !abort;
 eg_dual_clock_mem #(.WIDTH(32),.AW(11),.IMPLEMENT("32K")) line_buffer(
  .wclk(clk),.wrst(!reset_n),.we(row_write),.waddr(input_x[10:0]),.wdata(in_data),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(source_x[10:0]),.rdata(row_pixel));
 assign busy=state!=IDLE;
 assign in_ready=!abort && ((state==FILL)||(state==DRAIN && !source_complete));
                                                                        
                                                                            
 assign out_valid=abort ? (busy && output_count[6:0]!=0) : (state==EMIT);
 assign out_address=output_count[19:0];
 assign out_data=(!abort && inside_image)?row_pixel:32'd0;
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=IDLE;done<=0;error<=0;source_width<=0;source_height<=0;stride<=0;
   draw_width<=0;draw_height<=0;sample_width<=0;sample_height<=0;crop_x<=0;crop_y<=0;
   left_edge<=0;top_edge<=0;right_edge<=0;bottom_edge<=0;
   input_x<=0;source_row<=0;next_source_y<=0;source_x<=0;out_x<=0;out_y<=0;
   x_accum<=0;y_accum<=0;output_count<=0;source_complete<=0;
   dividend<=0;quotient<=0;remainder<=0;divisor<=1;divide_count<=0;divide_height<=0;
  end else begin
   done<=0;
   if(abort && busy)begin
    if(output_count[6:0]==0)begin state<=IDLE;done<=1;end
    else if(out_ready)output_count<=output_count+1'b1;
   end else case(state)
    IDLE:if(start)begin
     error<=0;source_width<=width;source_height<=height;stride<=(width+127)&12'hf80;
     sample_width<=width;sample_height<=height;crop_x<=0;crop_y<=0;
     if(width==0 || width>2048 || height==0 || height>2048)begin error<=1;done<=1;end
     else if(mode==3)begin
      draw_width<=(width>DEST_WIDTH)?DEST_WIDTH:width;
      draw_height<=(height>DEST_HEIGHT)?DEST_HEIGHT:height;
      sample_width<=(width>DEST_WIDTH)?DEST_WIDTH:width;
      sample_height<=(height>DEST_HEIGHT)?DEST_HEIGHT:height;
      crop_x<=(width>DEST_WIDTH)?((width-DEST_WIDTH)>>1):0;
      crop_y<=(height>DEST_HEIGHT)?((height-DEST_HEIGHT)>>1):0;
      state<=GEOMETRY;
     end else if(mode==2)begin draw_width<=DEST_WIDTH;draw_height<=DEST_HEIGHT;state<=GEOMETRY;end
     else begin
      quotient<=0;remainder<=0;divide_count<=0;
      if(width*DEST_HEIGHT>=height*DEST_WIDTH)begin
       draw_width<=DEST_WIDTH;dividend<=height*DEST_WIDTH;divisor<=width;divide_height<=1;
      end else begin
       draw_height<=DEST_HEIGHT;dividend<=width*DEST_HEIGHT;divisor<=height;divide_height<=0;
      end
      state<=DIVIDE;
     end
    end
    DIVIDE:begin
     dividend<=dividend<<1;quotient<=quotient_next;
     remainder<=divide_ge?(divide_trial-{1'b0,divisor}):divide_trial;
     if(divide_count==31)begin
      if(divide_height)draw_height<=(quotient_next==0)?12'd1:quotient_next[11:0];
      else draw_width<=(quotient_next==0)?12'd1:quotient_next[11:0];
      state<=GEOMETRY;
     end else divide_count<=divide_count+1'b1;
    end
    GEOMETRY:begin
     left_edge<=(DEST_WIDTH-draw_width)>>1;right_edge<=((DEST_WIDTH-draw_width)>>1)+draw_width;
     top_edge<=(DEST_HEIGHT-draw_height)>>1;bottom_edge<=((DEST_HEIGHT-draw_height)>>1)+draw_height;
     input_x<=0;source_row<=0;next_source_y<=crop_y;source_x<=crop_x;
     out_x<=0;out_y<=0;x_accum<=0;y_accum<=0;output_count<=0;source_complete<=0;
     state<=(((DEST_HEIGHT-draw_height)>>1)!=0)?EMIT:FILL;
    end
    FILL:if(in_valid && in_ready)begin
     if(input_x==stride-1)begin
      input_x<=0;
      if(source_row==source_height-1)source_complete<=1;
      if(source_row==next_source_y)state<=EMIT;
      else source_row<=source_row+1'b1;
     end else input_x<=input_x+1'b1;
    end
    EMIT:if(out_ready)begin
     output_count<=output_count+1'b1;
     if(out_x==DEST_WIDTH-1)begin
      out_x<=0;source_x<=crop_x;x_accum<=0;
      if(out_y==DEST_HEIGHT-1)begin
       state<=DRAIN;
       if(!source_complete)source_row<=source_row+1'b1;
      end
      else begin
       out_y<=out_y+1'b1;
       if(out_y+1<top_edge || out_y+1>=bottom_edge)state<=EMIT;
       else if(out_y<top_edge)state<=FILL;
       else begin y_accum<=y_accum+sample_height;state<=Y_STEP;end
      end
     end else begin
      out_x<=out_x+1'b1;
      if(inside_image && out_x+1<right_edge)begin x_accum<=x_accum+sample_width;state<=X_STEP;end
     end
    end
    X_STEP:begin
     if(x_accum>=draw_width)begin x_accum<=x_accum-draw_width;source_x<=source_x+1'b1;end
     else state<=EMIT;
    end
    Y_STEP:begin
     if(y_accum>=draw_height)begin y_accum<=y_accum-draw_height;next_source_y<=next_source_y+1'b1;end
     else if(next_source_y==source_row)state<=EMIT;
     else begin source_row<=source_row+1'b1;state<=FILL;end
    end
    DRAIN:begin
     if(source_complete)begin state<=IDLE;done<=1;end
     else if(in_valid && in_ready)begin
      if(input_x==stride-1)begin
       input_x<=0;
       if(source_row==source_height-1)source_complete<=1;
       else source_row<=source_row+1'b1;
      end else input_x<=input_x+1'b1;
     end
    end
    default:begin error<=1;state<=IDLE;done<=1;end
   endcase
  end
 end
endmodule

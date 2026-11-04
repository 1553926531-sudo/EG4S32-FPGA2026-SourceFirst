`timescale 1ns/1ps
module storage_cpu #(parameter PROGRAM_BITS=32)(input wire clk,input wire reset_n,
 output wire bus_valid,output wire [31:0] bus_address,output wire [31:0] bus_data,
 output wire [3:0] bus_write,input wire bus_ready,input wire [31:0] bus_read,
 output reg trapped);
 localparam FETCH=0,DECODE=1,READ_A=2,READ_B=3,EXEC=4,MEMORY=5,SHIFT=6,DIVIDE=7,
  MULTIPLY=8,MUL_FIX_A=9,MUL_FIX_B=10,MUL_WRITE=11,
  DIV_INIT_A=12,DIV_INIT_B=13,DIV_WRITE=14;
 reg [3:0] state;
 reg [PROGRAM_BITS-1:0] pc;
 reg [31:0] instruction,operand_a,operand_b,address,result,shift_value;
 reg [4:0] shift_count;
 reg [3:0] store_mask;
 reg shift_right,shift_signed;
 reg [31:0] div_q,div_r,div_d;
 reg [5:0] div_count;
 reg div_negative,rem_negative;
 reg [63:0] multiply_work;
 reg [5:0] multiply_count;
 wire [4:0] rs1=instruction[19:15],rs2=instruction[24:20],rd=instruction[11:7];
 wire [6:0] opcode=instruction[6:0];
 wire [2:0] fun=instruction[14:12];
 wire [31:0] immediate_i={{20{instruction[31]}},instruction[31:20]};
 wire [31:0] immediate_s={{20{instruction[31]}},instruction[31:25],instruction[11:7]};
 wire [31:0] immediate_b={{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
 wire [31:0] immediate_j={{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
 wire [31:0] immediate_u={instruction[31:12],12'd0};
 wire [31:0] register_data;
 reg register_write;reg [31:0] register_value;
 wire [4:0] register_address=(state==DECODE)?rs1:rs2;
 eg_dual_clock_mem #(.WIDTH(32),.AW(5),.IMPLEMENT("9K")) registers(
  .wclk(clk),.wrst(!reset_n),.we(register_write && rd!=0 && !trapped),.waddr(rd),.wdata(register_value),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(register_address),.rdata(register_data));
 reg [31:0] add_a,add_b;reg subtract;
 wire [32:0] sum={1'b0,add_a}+{1'b0,(add_b^{32{subtract}})}+subtract;
 wire [31:0] alu_b=opcode==7'h13 ? immediate_i:operand_b;
 wire multiply=opcode==7'h33 && instruction[31:25]==7'd1 && !fun[2];
 wire division=opcode==7'h33 && instruction[31:25]==7'd1 && fun[2];
 wire [32:0] div_trial={div_r,div_q[31]};
 wire div_subtract=div_trial[32] || sum[32];
 wire less_unsigned=!sum[32];
 wire less_signed=(operand_a[31]!=alu_b[31])?operand_a[31]:less_unsigned;
 reg branch_taken;
 always @*begin
  add_a=operand_a;add_b=alu_b;subtract=0;
  if(opcode==7'h03)add_b=immediate_i;
  else if(opcode==7'h23)add_b=immediate_s;
  else if(opcode==7'h17)begin add_a=pc;add_b=immediate_u;end
  else if(opcode==7'h6f)begin add_a=pc;add_b=immediate_j;end
  else if(opcode==7'h67)add_b=immediate_i;
  else if(opcode==7'h63)begin add_b=operand_b;subtract=1;end
  else if(fun==2 || fun==3 || (opcode==7'h33 && fun==0 && instruction[30]))subtract=1;
  if(state==MUL_FIX_A || state==MUL_FIX_B)begin
   add_a=multiply_work[63:32];subtract=1;
   add_b=state==MUL_FIX_A ? (((fun==1 || fun==2) && operand_a[31])?operand_b:32'd0):
                                   ((fun==1 && operand_b[31])?operand_a:32'd0);
  end
  if(state==MULTIPLY)begin
   add_a=multiply_work[63:32];add_b=multiply_work[0]?operand_a:32'd0;subtract=0;
  end
  if(state==DIVIDE)begin add_a=div_trial[31:0];add_b=div_d;subtract=1;end
  if(state==DIV_INIT_A || state==DIV_INIT_B || state==DIV_WRITE)begin
   add_a=0;subtract=1;
   add_b=state==DIV_INIT_A?operand_a:state==DIV_INIT_B?operand_b:fun[1]?div_r:div_q;
  end
  branch_taken=0;
  case(fun)
   0:branch_taken=operand_a==operand_b;
   1:branch_taken=operand_a!=operand_b;
   4:branch_taken=(operand_a[31]!=operand_b[31])?operand_a[31]:less_unsigned;
   5:branch_taken=(operand_a[31]!=operand_b[31])?!operand_a[31]:!less_unsigned;
   6:branch_taken=less_unsigned;7:branch_taken=!less_unsigned;
  endcase
 end
 wire [31:0] load_shifted=bus_read>>{address[1:0],3'b000};
 assign bus_valid=!trapped && (state==FETCH || state==MEMORY);
 assign bus_address=state==FETCH?pc:{address[31:2],2'b00};
 assign bus_data=fun==0?{4{operand_b[7:0]}}:fun==1?{2{operand_b[15:0]}}:operand_b;
 assign bus_write=state==MEMORY?store_mask:4'd0;
 always @*begin
  register_write=0;register_value=0;
  if(state==EXEC)case(opcode)
   7'h37:begin register_write=1;register_value=immediate_u;end
   7'h17:begin register_write=1;register_value=sum[31:0];end
   7'h6f,7'h67:begin register_write=1;register_value=pc+32'd4;end
   7'h13,7'h33:begin
    register_write=!division && !multiply && fun!=1 && fun!=5;
    case(fun)
     0:register_value=sum[31:0];2:register_value={31'd0,less_signed};3:register_value={31'd0,less_unsigned};
     4:register_value=operand_a^alu_b;6:register_value=operand_a|alu_b;7:register_value=operand_a&alu_b;
    endcase
   end
  endcase
  if(state==SHIFT && shift_count==0)begin register_write=1;register_value=shift_value;end
  if(state==MUL_WRITE)begin register_write=1;register_value=fun==0?multiply_work[31:0]:multiply_work[63:32];end
  if(state==DIV_WRITE)begin
   register_write=1;
   register_value=fun[1]?(rem_negative?sum[31:0]:div_r):(div_negative?sum[31:0]:div_q);
  end
  if(state==MEMORY && bus_ready && opcode==7'h03)begin
   register_write=1;
   case(fun)
    0:register_value={{24{load_shifted[7]}},load_shifted[7:0]};
    1:register_value={{16{load_shifted[15]}},load_shifted[15:0]};
    2:register_value=bus_read;4:register_value={24'd0,load_shifted[7:0]};
    5:register_value={16'd0,load_shifted[15:0]};default:register_value=0;
   endcase
  end
 end
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=FETCH;pc<=0;instruction<=0;operand_a<=0;operand_b<=0;address<=0;
   store_mask<=0;result<=0;shift_value<=0;shift_count<=0;shift_right<=0;shift_signed<=0;trapped<=0;
   div_q<=0;div_r<=0;div_d<=0;div_count<=0;div_negative<=0;rem_negative<=0;
   multiply_work<=0;multiply_count<=0;
  end else if(!trapped)case(state)
   FETCH:if(bus_ready)begin instruction<=bus_read;state<=DECODE;end
   DECODE:state<=READ_A;
   READ_A:begin operand_a<=rs1==0?32'd0:register_data;state<=READ_B;end
   READ_B:begin operand_b<=rs2==0?32'd0:register_data;state<=EXEC;end
   EXEC:begin
    case(opcode)
     7'h03,7'h23:begin
      address<=sum[31:0];
      store_mask<=opcode==7'h03 ? 4'd0:(fun==0?(4'b0001<<sum[1:0]):fun==1?(4'b0011<<sum[1:0]):4'b1111);
      state<=MEMORY;
      if((fun==2 && sum[1:0]!=0)||(fun==1 && sum[0]))trapped<=1;
     end
     7'h63:begin pc<=branch_taken?(pc+immediate_b):(pc+32'd4);state<=FETCH;end
     7'h6f:begin pc<=sum[31:0];state<=FETCH;end
     7'h67:begin pc<={sum[31:1],1'b0};state<=FETCH;end
     7'h37,7'h17:begin pc<=pc+32'd4;state<=FETCH;end
     7'h13,7'h33:if(division)begin
      div_r<=0;div_count<=32;
      div_negative<=!fun[0] && (operand_a[31]^operand_b[31]) && operand_b!=0;
      rem_negative<=!fun[0] && operand_a[31];state<=DIV_INIT_A;
     end else if(multiply)begin
      multiply_work<={32'd0,operand_b};multiply_count<=32;state<=MULTIPLY;
     end else if(fun==1 || fun==5)begin
      shift_value<=operand_a;shift_count<=alu_b[4:0];shift_right<=fun==5;
      shift_signed<=instruction[30];state<=SHIFT;
     end else begin pc<=pc+32'd4;state<=FETCH;end
     default:trapped<=1;
    endcase
   end
   MEMORY:if(bus_ready)begin pc<=pc+32'd4;state<=FETCH;end
   SHIFT:if(shift_count==0)begin pc<=pc+32'd4;state<=FETCH;end
    else begin shift_count<=shift_count-1'b1;shift_value<=shift_right?{shift_signed && shift_value[31],shift_value[31:1]}:{shift_value[30:0],1'b0};end
   DIV_INIT_A:begin div_q<=!fun[0] && operand_a[31]?sum[31:0]:operand_a;state<=DIV_INIT_B;end
   DIV_INIT_B:begin div_d<=!fun[0] && operand_b[31]?sum[31:0]:operand_b;state<=DIVIDE;end
   DIV_WRITE:begin pc<=pc+32'd4;state<=FETCH;end
   DIVIDE:if(div_count==0)state<=DIV_WRITE;
    else begin div_count<=div_count-1'b1;div_q<={div_q[30:0],div_subtract};
     div_r<=div_subtract?sum[31:0]:div_trial[31:0];end
   MULTIPLY:begin
    multiply_work<={sum,multiply_work[31:1]};multiply_count<=multiply_count-1'b1;
    if(multiply_count==1)state<=MUL_FIX_A;
   end
   MUL_FIX_A:begin multiply_work[63:32]<=sum[31:0];state<=MUL_FIX_B;end
   MUL_FIX_B:begin multiply_work[63:32]<=sum[31:0];state<=MUL_WRITE;end
   MUL_WRITE:begin pc<=pc+32'd4;state<=FETCH;end
   default:trapped<=1;
  endcase
 end
endmodule

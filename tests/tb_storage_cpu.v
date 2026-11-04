`timescale 1ns/1ps
module tb_storage_cpu #(parameter PROGRAM_BITS=32);
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0;
 wire valid,trapped;wire [31:0] address,data;wire [3:0] write;
 reg ready=0;reg [31:0] read=0;
 storage_cpu #(.PROGRAM_BITS(PROGRAM_BITS)) dut(.clk(clk),.reset_n(reset_n),.bus_valid(valid),.bus_address(address),
  .bus_data(data),.bus_write(write),.bus_ready(ready),.bus_read(read),.trapped(trapped));
 reg [31:0] program_words[0:32767],golden[0:8191],ram[0:1023];
 integer nwords,nchecks,checks=0,cycles=0,n,phase=0,delay=0;
 initial begin
  if(!$value$plusargs("words=%d",nwords))$fatal(1,"words missing");
  if(!$value$plusargs("checks=%d",nchecks))$fatal(1,"checks missing");
  $readmemh("program.hex",program_words,0,nwords-1);$readmemh("expected.hex",golden,0,nchecks-1);
  for(n=0;n<1024;n=n+1)ram[n]=32'ha55a3cc3;
  repeat(5)@(negedge clk);reset_n=1;
 end
 always @(negedge clk)begin
  if(reset_n)begin
   cycles=cycles+1;
   if(trapped)$fatal(1,"CPU trapped pc=%h insn=%h",dut.pc,dut.instruction);
   if(cycles>1000000)$fatal(1,"CPU timeout");
   case(phase)
    0:if(valid)begin delay=(cycles%5);phase=1;end
    1:if(delay!=0)delay=delay-1;else begin
     if(address<131072)read=program_words[address>>2];
     if(address>=32'h10000000 && address<32'h10001000)read=ram[address[11:2]];
     ready=1;phase=2;
    end
    2:begin ready=0;phase=0;end
   endcase
  end
 end
 always @(posedge clk)if(reset_n && valid && ready && |write)begin
  if(address==32'h20000004)begin
   if(checks!=nchecks)$fatal(1,"Missing checks %d/%d",checks,nchecks);
   $display("PASS storage CPU: %0d independent arithmetic, branch and memory vectors; %0d cycles",checks,cycles);$finish;
  end else if(address==32'h20000000)begin
   if(write!=15 || checks>=nchecks || data!==golden[checks])
    $fatal(1,"CPU vector %0d got=%h expected=%h pc=%h instruction=%h",checks,data,golden[checks],dut.pc,dut.instruction);
   checks=checks+1;
  end else if(address>=32'h10000000 && address<32'h10001000)begin
   for(n=0;n<4;n=n+1)if(write[n])ram[address[11:2]][n*8+:8]=data[n*8+:8];
  end else $fatal(1,"Unexpected CPU write %h",address);
 end
endmodule

`timescale 1ns/1ps
module media_storage(input wire clk,input wire reset_n,input wire enable,
 output wire sd_req,output wire [31:0] sd_lba,input wire sd_accept,
 input wire [31:0] sd_data,input wire sd_valid,output wire sd_ready,input wire sd_done,input wire sd_error,
 output wire mounted,output wire legacy_library,output wire [9:0] videos,output wire [9:0] images,output wire [9:0] songs,
 input wire prepare,input wire [8:0] select_file,input wire [1:0] select_kind,input wire legacy,
 output reg prepared,output reg raw_media,output wire [7:0] error,output wire [31:0] sectors,
 input wire rd_req,input wire [31:0] rd_lba,output wire rd_accept,
 output wire [31:0] rd_data,output wire rd_valid,input wire rd_ready,output reg rd_done,output reg rd_error,
 input wire name_clk,input wire name_reset_n,input wire [8:0] name_id,input wire [4:0] name_char,output wire [7:0] name_code);
 wire cpu_valid,cpu_ready,cpu_trapped;wire [31:0] cpu_address,cpu_data,cpu_read;wire [3:0] cpu_write;
 storage_cpu #(.PROGRAM_BITS(14)) cpu(.clk(clk),.reset_n(reset_n),.bus_valid(cpu_valid),.bus_address(cpu_address),
  .bus_data(cpu_data),.bus_write(cpu_write),.bus_ready(cpu_ready),.bus_read(cpu_read),.trapped(cpu_trapped));
 reg bus_pending;
 always @(posedge clk)if(!reset_n)bus_pending<=0;else bus_pending<=cpu_valid && !bus_pending;
 assign cpu_ready=cpu_valid && bus_pending;
 wire store=cpu_valid && !bus_pending && |cpu_write;
 wire io_store=store && cpu_address[31:12]==20'h20000;
 wire [5:0] io_address=cpu_address[7:2];
 wire [31:0] rom[0:2],ram[0:2];
 reg [2:0] memory_bank;reg [1:0] memory_region;
 always @(posedge clk)begin memory_bank<=cpu_address[14:12];memory_region<=cpu_address[29:28];end
 genvar bank,byte_index;
 generate for(bank=0;bank<3;bank=bank+1)begin: program_memory
`ifdef __ICARUS__
  reg [31:0] words[0:1023];reg [31:0] q;
  initial begin
   case(bank)
    0:$readmemh("storage_rom_0.hex",words);1:$readmemh("storage_rom_1.hex",words);
    2:$readmemh("storage_rom_2.hex",words);
   endcase
  end
  always @(posedge clk)q<=words[cpu_address[11:2]];
  assign rom[bank]=q;
`else
  EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),.MODE("SP"),
   .REGMODE_A("NOREG"),.RESETMODE("ASYNC"),.BYTE_ENABLE(0),.IMPLEMENT(bank==2?"9K":"32K"),
   .INIT_FILE(bank==0?"storage_rom_0.mif":bank==1?"storage_rom_1.mif":"storage_rom_2.mif")) code_memory(
   .dia(32'd0),.addra(cpu_address[11:2]),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(!reset_n),.bea(1'b1),.doa(rom[bank]));
`endif
 end
 for(bank=0;bank<3;bank=bank+1)begin: work_memory
  for(byte_index=0;byte_index<4;byte_index=byte_index+1)begin: byte_memory
   eg_dual_clock_mem #(.WIDTH(8),.AW(10),.IMPLEMENT("9K")) bytes_mem(
    .wclk(clk),.wrst(!reset_n),.we(store && cpu_address[31:14]==18'h4 && cpu_address[13:12]==bank && cpu_write[byte_index]),
    .waddr(cpu_address[11:2]),.wdata(cpu_data[byte_index*8+:8]),
    .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(cpu_address[11:2]),.rdata(ram[bank][byte_index*8+:8]));
  end
 end endgenerate
 reg [1:0] library_flags;reg [9:0] count_video,count_image,count_song;
 reg [31:0] file_sectors;reg [7:0] firmware_error;reg [31:0] io_read;
 reg prepare_pending,read_pending;reg [11:0] selection;reg [31:0] request_lba;
 reg [31:0] card_lba;reg [1:0] card_state;reg card_pass,card_error;
 reg [6:0] card_word,out_word;reg out_active,out_wait;
 reg [11:0] name_address;
 reg [31:0] direct_first,direct_physical,direct_length;
 reg direct_enabled;
 wire direct_hit=direct_enabled && rd_lba>=direct_first && (rd_lba-direct_first)<direct_length;
 wire [31:0] card_memory_data,out_memory_data,display_word;
 wire [6:0] output_address=out_active?out_word:cpu_address[8:2];
 eg_dual_clock_mem #(.WIDTH(32),.AW(7),.IMPLEMENT("9K")) card_buffer(
  .wclk(clk),.wrst(!reset_n),.we(card_state==2 && sd_valid && sd_ready && !card_pass),.waddr(card_word),.wdata(sd_data),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(cpu_address[8:2]),.rdata(card_memory_data));
 eg_dual_clock_mem #(.WIDTH(32),.AW(7),.IMPLEMENT("9K")) response_buffer(
  .wclk(clk),.wrst(!reset_n),.we(store && cpu_address[31:12]==20'h20002),.waddr(cpu_address[8:2]),.wdata(cpu_data),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(output_address),.rdata(out_memory_data));
 eg_dual_clock_mem #(.WIDTH(32),.AW(12),.IMPLEMENT("32K")) display_names(
  .wclk(clk),.wrst(!reset_n),.we(io_store && io_address==9),.waddr(name_address),.wdata(cpu_data),
  .rclk(name_clk),.rrst(!name_reset_n),.re(1'b1),.raddr({name_id,name_char[4:2]}),.rdata(display_word));
 reg [1:0] display_byte;
 always @(posedge name_clk)display_byte<=name_char[1:0];
 assign name_code=display_word[{display_byte,3'b000}+:8];
 assign mounted=library_flags[0];assign legacy_library=library_flags[1];
 assign videos=count_video;assign images=count_image;assign songs=count_song;
 assign error=cpu_trapped?8'h6e:firmware_error;assign sectors=file_sectors;
 assign sd_req=card_state==1;assign sd_lba=card_lba;
 assign sd_ready=card_state==2 && (!card_pass || rd_ready);
 assign rd_accept=rd_req && !read_pending && prepared && !out_active && card_state==0;
 assign rd_valid=(card_state==2 && card_pass && sd_valid)||(out_active && !out_wait);
 assign rd_data=card_pass?sd_data:out_memory_data;
 always @*begin
  io_read=0;
  case(io_address)
   0:io_read={28'd0,out_active,read_pending,prepare_pending,enable};
   1:io_read={20'd0,selection};2:io_read=request_lba;
   3:io_read={30'd0,card_error,card_state!=0};
   16:io_read={30'd0,library_flags};17:io_read={22'd0,count_video};
   18:io_read={22'd0,count_image};19:io_read={22'd0,count_song};
   23:io_read=file_sectors;24:io_read={24'd0,firmware_error};
  endcase
 end
 assign cpu_read=cpu_address[31:16]==0?(memory_bank<3?rom[memory_bank]:32'd0):
  cpu_address[31:16]==1?(memory_bank<3?ram[memory_bank]:32'd0):
  cpu_address[31:12]==20'h20000 ? io_read:
  cpu_address[31:12]==20'h20001 ? card_memory_data:32'd0;
 integer n;
 always @(posedge clk)begin
  if(!reset_n)begin
   prepare_pending<=0;read_pending<=0;selection<=0;request_lba<=0;prepared<=0;raw_media<=0;
   card_lba<=0;card_state<=0;card_pass<=0;card_error<=0;card_word<=0;out_word<=0;
   out_active<=0;out_wait<=0;rd_done<=0;rd_error<=0;name_address<=0;
   library_flags<=0;count_video<=0;count_image<=0;count_song<=0;file_sectors<=0;firmware_error<=0;
   direct_first<=0;direct_physical<=0;direct_length<=0;direct_enabled<=0;
  end else begin
   rd_done<=0;
   if(prepare)begin prepare_pending<=1;prepared<=0;selection<={legacy,select_kind,select_file};direct_enabled<=0;firmware_error<=0;end
   if(rd_accept)begin
    request_lba<=rd_lba;rd_error<=0;
    if(direct_hit)begin card_lba<=direct_physical+(rd_lba-direct_first);card_state<=1;card_pass<=1;card_error<=0;end
    else read_pending<=1;
   end
   if(card_state==1 && sd_accept)begin card_state<=2;card_word<=0;end
   if(card_state==2 && sd_valid && sd_ready)card_word<=card_word+1'b1;
   if(card_state==2 && sd_done)begin
    card_state<=0;card_error<=sd_error;
    if(card_pass)begin rd_done<=1;rd_error<=sd_error;read_pending<=0;card_pass<=0;end
   end
   if(out_active)begin
    if(out_wait)out_wait<=0;
    else if(rd_ready)begin
     if(out_word==127)begin out_active<=0;read_pending<=0;rd_done<=1;end
     else begin out_word<=out_word+1'b1;out_wait<=1;end
    end
   end
   if(io_store)case(io_address)
    4:card_lba<=cpu_data;
    5:begin card_state<=1;card_pass<=cpu_data[1];card_error<=0;if(cpu_data[1])read_pending<=0;end
    6:begin prepared<=cpu_data[0];raw_media<=cpu_data[1];prepare_pending<=0;end
    7:if(cpu_data[1])begin rd_error<=1;rd_done<=1;read_pending<=0;end
     else begin out_active<=1;out_wait<=1;out_word<=0;read_pending<=0;end
    8:name_address<=cpu_data[11:0];
    9:name_address<=name_address+1'b1;
    10:direct_first<=cpu_data;11:direct_physical<=cpu_data;12:direct_length<=cpu_data;13:direct_enabled<=cpu_data[0];
    16:library_flags<=cpu_data[1:0];17:count_video<=cpu_data[9:0];18:count_image<=cpu_data[9:0];19:count_song<=cpu_data[9:0];
    23:file_sectors<=cpu_data;24:firmware_error<=cpu_data[7:0];
   endcase
  end
 end
endmodule

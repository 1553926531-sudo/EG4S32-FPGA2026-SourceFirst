`timescale 1ns/1ps
module tb_media_storage;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,prepare=0;
 wire sd_req,sd_ready,mounted,file_accept,file_valid,stat_done,file_done,file_error,pak_found;
 wire [31:0] sd_lba,file_data,stat_hash,file_sector;
 wire [63:0] pak_bytes,stat_bytes;
 wire [9:0] videos,images,songs,legacy_images,legacy_songs;
 wire [7:0] fs_error,lyrics,error;
 reg sd_accept=0,sd_valid=0,sd_done=0,sd_error=0;
 reg [31:0] sd_data=0;
 wire stat_req,file_req,file_ready;
 wire [8:0] stat_id,file_id;
 wire [1:0] file_channel;
 reg [8:0] select_file=0;
 reg [1:0] kind=0;
 wire prepared,raw_media;
 wire [31:0] sectors,rd_data;
 wire rd_accept,rd_valid,rd_done,rd_error;
 reg rd_req=0,rd_ready=0;
 reg [31:0] rd_lba=0;
 media_storage dut(.clk(clk),.reset_n(reset_n),.enable(1'b1),
  .sd_req(sd_req),.sd_lba(sd_lba),.sd_accept(sd_accept),.sd_data(sd_data),.sd_valid(sd_valid),
  .sd_ready(sd_ready),.sd_done(sd_done),.sd_error(sd_error),.mounted(mounted),.error(error),
  .videos(videos),.images(images),.songs(songs),.legacy_library(),
  .prepare(prepare),.select_file(select_file),.select_kind(kind),.legacy(1'b0),.prepared(prepared),
  .raw_media(raw_media),.sectors(sectors),.rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),
  .rd_data(rd_data),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .name_clk(clk),.name_reset_n(reset_n),.name_id(9'd0),.name_char(5'd0),.name_code());
 reg [31:0] lbas[0:4095],disk[0:524287],commands[0:4095],golden[0:65535];
 integer nsectors,ncommands,expected_error;
 integer debug_file;
 initial debug_file=$fopen("progress.log","w");
 integer cycle=0,phase=0,word=0,slot=0,delay=0,i,c,reads=0;
 integer base,received=0,last_file=-1;
 task bad;input [511:0] message;
  begin $fatal(1,"FAIL media storage %0s error=%h cycle=%0d command=%0d word=%0d CPU pc=%h instr=%h state=%0d",
   message,error,cycle,c,received,dut.cpu.pc,dut.cpu.instruction,dut.cpu.state);end
 endtask
 always @(posedge clk)begin
  cycle=cycle+1;
  if(cycle%100000==0)begin $fdisplay(debug_file,"cycle=%0d pc=%h instruction=%h CPU=%0d read=%h mount=%d error=%h reads=%0d c=%0d",cycle,dut.cpu.pc,dut.cpu.instruction,dut.cpu.state,dut.cpu_read,mounted,error,reads,c);$fflush(debug_file);end
  if(cycle>30000000)bad("timeout");
  sd_accept<=0;sd_done<=0;
  if(reset_n)case(phase)
   0:if(sd_req)begin
    slot=-1;for(i=0;i<nsectors;i=i+1)if(lbas[i]==sd_lba)slot=i;
    if(slot<0)begin $display("LBA=%0d",sd_lba);bad("unmapped disk LBA");end
    word=0;sd_accept<=1;delay=2;phase=1;reads=reads+1;
   end
   1:if(delay!=0)delay=delay-1;else begin sd_data<=disk[slot*128+word];sd_valid<=1;phase=2;end
   2:if(sd_valid && sd_ready)begin
    sd_valid<=0;
    if(word==127)begin phase=3;delay=3;end
    else begin word=word+1;phase=1;delay=(cycle%7==0)?2:0;end
   end
   3:if(delay!=0)delay=delay-1;else begin sd_done<=1;phase=0;end
  endcase
 end
 initial begin
  if(!$value$plusargs("sectors=%d",nsectors))bad("missing sector count");
  if(!$value$plusargs("commands=%d",ncommands))bad("missing command count");
  if(!$value$plusargs("error=%d",expected_error))expected_error=0;
  $readmemh("lbas.hex",lbas,0,nsectors-1);$readmemh("disk.hex",disk,0,nsectors*128-1);
  $readmemh("commands.hex",commands,0,ncommands*3-1);$readmemh("golden.hex",golden,0,ncommands*128-1);
  repeat(5)@(negedge clk);reset_n=1;
  while(!mounted && error==0)@(negedge clk);
  if(error!=0)bad("mount error");
  begin: validate_commands
  for(c=0;c<ncommands;c=c+1)begin
   base=c*3;
   if(last_file!=commands[base])begin
    select_file=commands[base];kind=commands[base+1];prepare=1;
    @(negedge clk);prepare=0;
    @(negedge clk);
    while(!prepared && error==0)@(negedge clk);
    if(error!=0)begin
     if(error!==expected_error)bad("unexpected preparation error");
     $display("PASS media storage rejected %h reads=%0d",error,reads);disable validate_commands;
    end
    last_file=commands[base];
   end
   rd_lba=commands[base+2];rd_req=1;@(posedge clk);
   while(!rd_accept)@(posedge clk);
   @(negedge clk);rd_req=0;received=0;
   while(!rd_done)begin
    rd_ready=(cycle%11!=0);
    @(posedge clk);
    if(rd_valid && rd_ready)begin
     if(rd_data!==golden[c*128+received])begin
      $display("got=%h want=%h",rd_data,golden[c*128+received]);bad("sector contents");
     end
     received=received+1;
    end
    @(negedge clk);
   end
   rd_ready=0;
   if(rd_error || received!=128)bad("sector completion");
   $display("QUERY file=%0d lba=%0d cycle=%0d reads=%0d",select_file,rd_lba,cycle,reads);
   @(negedge clk);
  end
  if(expected_error!=0)bad("missing rejection");
  $display("PASS media storage commands=%0d reads=%0d cycles=%0d",ncommands,reads,cycle);
  end
  $finish;
 end
endmodule

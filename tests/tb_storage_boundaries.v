`timescale 1ns/1ps
module tb_storage_boundaries;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,prepare=0,sd_accept=0,sd_valid=0,sd_done=0;
 reg [31:0] sd_data=0,rd_lba=0;
 reg [8:0] select_file=0,name_id=0;
 reg [4:0] name_char=0;
 reg [1:0] kind=0;
 reg rd_req=0,rd_ready=0;
 wire sd_req,sd_ready,mounted,prepared,raw_media,rd_accept,rd_valid,rd_done,rd_error;
 wire [31:0] sd_lba,sectors,rd_data;
 wire [9:0] videos,images,songs;
 wire [7:0] error,name_code;
 media_storage dut(.clk(clk),.reset_n(reset_n),.enable(1'b1),
  .sd_req(sd_req),.sd_lba(sd_lba),.sd_accept(sd_accept),.sd_data(sd_data),
  .sd_valid(sd_valid),.sd_ready(sd_ready),.sd_done(sd_done),.sd_error(1'b0),
  .mounted(mounted),.error(error),.videos(videos),.images(images),.songs(songs),.legacy_library(),
  .prepare(prepare),.select_file(select_file),.select_kind(kind),.legacy(1'b0),
  .prepared(prepared),.raw_media(raw_media),.sectors(sectors),
  .rd_req(rd_req),.rd_lba(rd_lba),.rd_accept(rd_accept),.rd_data(rd_data),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .name_clk(clk),.name_reset_n(reset_n),.name_id(name_id),.name_char(name_char),.name_code(name_code));
 reg [31:0] lbas[0:4095],disk[0:524287],commands[0:8191],golden[0:65535];
 reg [8:0] names[0:511];reg [7:0] name_bytes[0:16383];
 integer nsectors,ncommands,nnames,mount_error,want_v,want_i,want_s;
 integer cycle=0,phase=0,word_index=0,slot=0,delay=0,i,c=0,reads=0;
 integer received=0,base=0,last_file=-1,n,j;
 task bad;input [511:0] message;
  begin $fatal(1,"FAIL storage boundaries %0s error=%h cycle=%0d cmd=%0d word=%0d pc=%h",message,error,cycle,c,received,dut.cpu.pc);end
 endtask
 always @(posedge clk)begin
  cycle=cycle+1;if(cycle>30000000)bad("timeout");
  sd_accept<=0;sd_done<=0;
  if(reset_n)case(phase)
   0:if(sd_req)begin
    slot=-1;for(i=0;i<nsectors;i=i+1)if(lbas[i]==sd_lba)slot=i;
    if(slot<0)begin $display("LBA=%0d",sd_lba);bad("unmapped disk sector");end
    word_index=0;sd_accept<=1;delay=2;phase=1;reads=reads+1;
   end
   1:if(delay!=0)delay=delay-1;else begin sd_data<=disk[slot*128+word_index];sd_valid<=1;phase=2;end
   2:if(sd_valid && sd_ready)begin
    sd_valid<=0;
    if(word_index==127)begin phase=3;delay=3;end
    else begin word_index=word_index+1;phase=1;delay=(cycle%7==0)?2:0;end
   end
   3:if(delay!=0)delay=delay-1;else begin sd_done<=1;phase=0;end
  endcase
 end
 initial begin
  if(!$value$plusargs("sectors=%d",nsectors))bad("missing sectors");
  if(!$value$plusargs("commands=%d",ncommands))bad("missing commands");
  if(!$value$plusargs("names=%d",nnames))nnames=0;
  if(!$value$plusargs("mount_error=%d",mount_error))mount_error=0;
  if(!$value$plusargs("videos=%d",want_v))want_v=0;
  if(!$value$plusargs("images=%d",want_i))want_i=0;
  if(!$value$plusargs("songs=%d",want_s))want_s=0;
  $readmemh("lbas.hex",lbas,0,nsectors-1);$readmemh("disk.hex",disk,0,nsectors*128-1);
  if(ncommands)begin $readmemh("commands.hex",commands,0,ncommands*5-1);$readmemh("golden.hex",golden,0,ncommands*128-1);end
  if(nnames)begin $readmemh("names.hex",names,0,nnames-1);$readmemh("name_bytes.hex",name_bytes,0,nnames*32-1);end
  repeat(5)@(negedge clk);reset_n=1;
  while(!mounted && !error)@(negedge clk);
  if(mount_error)begin
   if(error!==mount_error || mounted)bad("mount rejection");
  end else begin
   if(error || !mounted)bad("mount failed");
   if(videos!==want_v || images!==want_i || songs!==want_s)bad("enumeration counts");
   for(n=0;n<nnames;n=n+1)for(j=0;j<32;j=j+1)begin
    name_id=names[n];name_char=j;repeat(3)@(negedge clk);
    if(name_code!==name_bytes[n*32+j])begin $display("name=%0d char=%0d got=%h want=%h",name_id,j,name_code,name_bytes[n*32+j]);bad("display name");end
   end
   for(c=0;c<ncommands;c=c+1)begin
    base=c*5;
    if(last_file!=commands[base])begin
     select_file=commands[base];kind=commands[base+1];prepare=1;
     @(negedge clk);prepare=0;@(negedge clk);
     while(!prepared && !error)@(negedge clk);
     if(error!==commands[base+3])bad("preparation result");
     if(!error && !prepared)bad("not prepared");
     last_file=commands[base];
    end
    if(!commands[base+3])begin
     rd_lba=commands[base+2];rd_req=1;@(posedge clk);while(!rd_accept)@(posedge clk);
     @(negedge clk);rd_req=0;received=0;
     while(!rd_done)begin
      rd_ready=(cycle%11!=0);@(posedge clk);
      if(rd_valid && rd_ready)begin
       if(received>=128 || (!commands[base+4] && rd_data!==golden[c*128+received]))begin
        $display("got=%h want=%h",rd_data,golden[c*128+received]);bad("sector contents");
       end
       received=received+1;
      end
      @(negedge clk);
     end
     rd_ready=0;
     if(commands[base+4])begin
      if(!rd_error || error!==commands[base+4])bad("read rejection");
     end else if(rd_error || received!=128 || error)bad("read completion");
     @(negedge clk);
    end
   end
  end
  $display("PASS storage boundaries commands=%0d names=%0d reads=%0d cycles=%0d mount_error=%h",ncommands,nnames,reads,cycle,mount_error);
  $finish;
 end
endmodule

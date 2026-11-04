`timescale 1ns/1ps
module tb_file_system;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0;
 wire sd_req,sd_ready,mounted,file_accept,file_valid,stat_done,file_done,file_error,pak_found;
 wire [31:0] sd_lba,file_data,stat_hash;
 wire [63:0] pak_bytes,stat_bytes;
 wire [9:0] videos,images,songs;
 wire [7:0] error,lyrics,name_code;
 reg sd_accept=0,sd_valid=0,sd_done=0,sd_error=0;
 reg [31:0] sd_data=0;
 reg stat_req=0,file_req=0,file_ready=0;
 reg [8:0] stat_id=0,file_id=0,name_id=0;
 reg [4:0] name_char=0;
 reg [31:0] file_sector=0;
 reg [1:0] file_channel=0;
 sd_file_system dut(.clk(clk),.reset_n(reset_n),.enable(1'b1),
  .sd_req(sd_req),.sd_lba(sd_lba),.sd_accept(sd_accept),.sd_data(sd_data),.sd_valid(sd_valid),
  .sd_ready(sd_ready),.sd_done(sd_done),.sd_error(sd_error),.mounted(mounted),.error(error),
  .videos(videos),.images(images),.songs(songs),.lyrics(lyrics),.pak_found(pak_found),.pak_bytes(pak_bytes),
  .stat_req(stat_req),.stat_id(stat_id),.stat_done(stat_done),.stat_bytes(stat_bytes),.stat_hash(stat_hash),
  .file_req(file_req),.file_id(file_id),.file_sector(file_sector),.file_channel(file_channel),
  .file_accept(file_accept),.file_data(file_data),.file_valid(file_valid),.file_ready(file_ready),
  .file_done(file_done),.file_error(file_error),.name_clk(clk),.name_id(name_id),.name_char(name_char),.name_code(name_code));
 reg [31:0] lbas[0:4095],disk[0:524287],commands[0:4095],golden[0:65535];
 reg [7:0] names[0:8191];
 integer nsectors,ncommands,expected_error;
 integer cycle=0,phase=0,word=0,slot=0,delay=0,i,j,c,count=0,reads=0;
 integer base,received;
 reg [31:0] hash_song;
 task bad;input [511:0] message;
  begin $display("FAIL file system %0s state=%0d error=%h cycle=%0d command=%0d word=%0d",message,dut.state,error,cycle,c,received);
   $display("SD phase=%0d lba=%0d word=%0d index=%0d mode=%0d valid=%b ready=%b reads=%0d return=%0d io_complete=%b",phase,sd_lba,word,dut.word_index,dut.io_mode,sd_valid,sd_ready,reads,dut.return_state,dut.io_complete);
   $display("catalog video=%0d image=%0d song=%0d lyric=%0d pak=%b",videos,images,songs,lyrics,pak_found);$finish;end
 endtask
 always @(posedge clk)begin
  cycle=cycle+1;
  if(cycle>200000 || ($test$plusargs("trace") && cycle>50000))bad("timeout");
  if($test$plusargs("trace") && dut.state==14)$display("entry suffix=%h name=%h length=%0d size=%0d cluster=%0d dir=%b",dut.suffix,dut.short_display,dut.actual_name_length,dut.pending_size,dut.pending_cluster,dut.pending_directory);
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
  $readmemh("commands.hex",commands,0,ncommands*7-1);$readmemh("golden.hex",golden,0,ncommands*128-1);
  $readmemh("names.hex",names,0,255);
  repeat(5)@(negedge clk);reset_n=1;
  while(!mounted && error==0)@(negedge clk);
  if(expected_error!=0)begin
   if(error!==expected_error)bad("wrong mount rejection");
   $display("PASS file system rejected %h reads=%0d",error,reads);$finish;
  end
  if(error!=0 || videos!=1 || images!=2 || songs!=2 || lyrics!=1 || !pak_found)bad("catalog counts");
  for(c=0;c<ncommands;c=c+1)begin
   base=c*7;
   stat_id=commands[base];stat_req=1;
   @(negedge clk);stat_req=0;
   while(!stat_done)@(negedge clk);
   if(stat_bytes!=={commands[base+3],commands[base+2]})bad("file byte length");
   if(commands[base]==256)hash_song=stat_hash;
   if(commands[base]==384 && stat_hash!==hash_song)bad("lyric matching hash");
   if(commands[base]!=511 && commands[base]!=510)begin
    name_id=commands[base];
    for(j=0;j<32;j=j+1)begin
     name_char=j;repeat(2)@(negedge clk);
     if(name_code!==names[commands[base+6]*32+j])begin
      $display("name id=%0d char=%0d got=%h want=%h",name_id,j,name_code,names[commands[base+6]*32+j]);bad("display name");
     end
    end
   end
   file_id=commands[base];file_sector=commands[base+1];file_channel=commands[base+5];file_req=1;
   @(posedge clk);while(!file_accept)@(posedge clk);
   @(negedge clk);file_req=0;received=0;
   while(!file_done)begin
    file_ready=(cycle%11!=0);
    @(posedge clk);
    if(file_valid && file_ready)begin
     if(!commands[base+4] && file_data!==golden[c*128+received])begin
      $display("got=%h want=%h",file_data,golden[c*128+received]);bad("file contents");
     end
     received=received+1;
    end
    @(negedge clk);
   end
   file_ready=0;
   if(file_error!==commands[base+4][0])bad("wrong file completion status");
   if(!file_error && received!=128)bad("short sector");
   @(negedge clk);
  end
  $display("PASS file system commands=%0d reads=%0d cycles=%0d",ncommands,reads,cycle);$finish;
 end
endmodule

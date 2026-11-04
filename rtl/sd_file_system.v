`timescale 1ns/1ps
module sd_file_system(
 input wire clk,input wire reset_n,input wire enable,
 output wire sd_req,output wire [31:0] sd_lba,input wire sd_accept,
 input wire [31:0] sd_data,input wire sd_valid,output wire sd_ready,
 input wire sd_done,input wire sd_error,
 output reg mounted,output reg [7:0] error,
 output reg [9:0] videos,output reg [9:0] images,output reg [9:0] songs,
 output reg [7:0] lyrics,output reg pak_found,output reg [63:0] pak_bytes,
 input wire stat_req,input wire [8:0] stat_id,output reg stat_done,
 output reg [63:0] stat_bytes,output reg [31:0] stat_hash,
 input wire file_req,input wire [8:0] file_id,input wire [31:0] file_sector,
 input wire [1:0] file_channel,output wire file_accept,
 output wire [31:0] file_data,output wire file_valid,input wire file_ready,
 output reg file_done,output reg file_error,
 input wire name_clk,input wire [8:0] name_id,input wire [4:0] name_char,
 output wire [7:0] name_code
);
 localparam START=0,REQUEST=1,RECEIVE=2,COMPLETE=3,BOOT_CHECK=4,
  DIR_START=5,DIR_REQUEST=6,DIR_ENTRY=7,DIR_NEXT=8,FAT_RESULT=9,
  ENTRY_CHECK=10,NAME_STEP=11,NAME_WAIT=12,NAME_BYTE=13,NAME_FINISH=14,
  SAVE_NAME=15,SAVE_META=16,DIR_END=17,IDLE=18,META_WAIT=19,META_GOT=20,
  MAP_PREP=21,MAP_STEP=22,MAP_DATA=23,FILE_END=24,STAT_END=25,
  SHORT_NAME=26,SHORT_FINISH=27,ENTRY_SUM=28,ENTRY_PARSE=29,SHORT_DOT=30,
  META_WRITE=31,NAME_PAD=32,FAILED=63;
 reg [5:0] state,return_state;
 reg [1:0] io_mode;
 reg [31:0] io_lba;
 reg [6:0] word_index;
 reg io_complete,io_bad;
 reg [31:0] boot[0:31],entry[0:7];
 reg signature,part_valid;reg [7:0] part_type;reg [15:0] part_low;
 reg [31:0] partition_start,volume_start,fat_start,heap_start,cluster_count,fat_length;
 reg [31:0] volume_sectors;
 reg [5:0] cluster_shift;
 reg exfat,partitioned;
 reg [31:0] root_cluster,dir_cluster,dir_first,dir_sector,dir_remaining,dir_steps;
 reg dir_contiguous;
 reg [31:0] fat_cluster,fat_value;reg [6:0] fat_word;
 reg [1:0] fat_purpose;
 reg [7:0] entry_word;
 reg [5:0] queue_read,queue_write;
 reg [31:0] next_dir_cluster,next_dir_sectors;
 reg next_dir_contiguous;
 wire [64:0] queue_data;
 reg queue_we;
 eg_dual_clock_mem #(.WIDTH(65),.AW(6),.IMPLEMENT("9K")) directories(
  .wclk(clk),.wrst(!reset_n),.we(queue_we),.waddr(queue_write),
  .wdata({next_dir_contiguous,next_dir_sectors,next_dir_cluster}),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(queue_read),.rdata(queue_data));
 reg [31:0] pending_cluster;
 reg [63:0] pending_size,pending_valid;
 reg pending_contiguous,pending_directory;
 reg [7:0] name_length,secondary_left;
 reg [15:0] expected_checksum,set_checksum;
 reg [4:0] checksum_byte;reg checksum_first;
 reg ex_set,ex_stream,ex_names,lfn_valid;
 reg [7:0] lfn_sequence,name_position,lfn_checksum;
 reg [3:0] entry_character;
 reg [7:0] name_write_address;
 reg [15:0] name_write_data;
 reg name_we;
 wire [15:0] name_read_data;
 eg_dual_clock_mem #(.WIDTH(16),.AW(8),.IMPLEMENT("9K")) long_name(
  .wclk(clk),.wrst(!reset_n),.we(name_we),.waddr(name_write_address),.wdata(name_write_data),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr(name_position),.rdata(name_read_data));
 reg [255:0] short_display;
 reg [5:0] display_length;
 reg [31:0] basename_hash;
 reg [63:0] suffix;
 reg [7:0] actual_name_length;
 reg [1:0] save_kind;
 reg [8:0] save_id;
 reg [2:0] save_word;
 reg meta_we;
 wire name_store_we=state==SAVE_NAME;
 reg [8:0] meta_address,meta_query;
 reg [127:0] meta_write_data;
 wire [31:0] meta_data;
 reg [1:0] meta_word;
 reg [31:0] pak_cluster,pak_hash;reg pak_contiguous;
 eg_dual_clock_mem #(.WIDTH(32),.AW(11),.IMPLEMENT("32K")) catalog(
  .wclk(clk),.wrst(!reset_n),.we(state==META_WRITE),.waddr({meta_address,meta_word}),.wdata(meta_write_data[31:0]),
  .rclk(clk),.rrst(!reset_n),.re(1'b1),.raddr({meta_query,meta_word}),.rdata(meta_data));
 wire [31:0] display_word;
 reg [1:0] display_byte;
 eg_dual_clock_mem #(.WIDTH(32),.AW(12),.IMPLEMENT("32K")) display_names(
  .wclk(clk),.wrst(!reset_n),.we(name_store_we),.waddr({save_id,save_word}),
  .wdata(short_display[31:0]),
  .rclk(name_clk),.rrst(!reset_n),.re(1'b1),.raddr({name_id,name_char[4:2]}),.rdata(display_word));
 always @(posedge name_clk)display_byte<=name_char[1:0];
 assign name_code=display_word[{display_byte,3'b000}+:8];
 reg [8:0] request_id;
 reg [31:0] request_sector,map_cluster,map_index,target_index,map_steps;
 reg [1:0] request_channel;
 reg request_stat,map_contiguous;
 reg [63:0] map_bytes;
 reg [31:0] cached_cluster[0:3],cached_index[0:3];
 reg [8:0] cached_id[0:3];reg [3:0] cache_valid;
 wire [31:0] cluster_mask=(32'd1<<cluster_shift)-1'b1;
 wire [31:0] dir_lba=heap_start+((dir_cluster-2)<<cluster_shift)+dir_sector;
 assign sd_req=state==REQUEST;
 assign sd_lba=io_lba;
 assign sd_ready=state==RECEIVE && ((io_mode!=3)||file_ready);
 assign file_accept=state==IDLE && file_req && !stat_req;
 assign file_data=sd_data;
 assign file_valid=state==RECEIVE && io_mode==3 && sd_valid;
 function [15:0] entry_utf;
  input [3:0] n;input [255:0] bytes;input is_exfat;reg [7:0] off;
  begin
   if(is_exfat)off=2+{n,1'b0};
   else if(n<5)off=1+{n,1'b0};
   else if(n<11)off=14+((n-5)<<1);
   else off=28+((n-11)<<1);
   entry_utf=bytes[{off[4:0],3'b000}+:16];
  end
 endfunction
 function [7:0] short_sum;
  input [255:0] bytes;integer b;reg [7:0] c;
  begin c=0;for(b=0;b<11;b=b+1)c={c[0],c[7:1]}+bytes[b*8+:8];short_sum=c;end
 endfunction
 function [15:0] upper;
  input [15:0] c;begin upper=(c>=97 && c<=122)?c-16'd32:c;end
 endfunction
 function [31:0] hash_char;
  input [31:0] h;input [15:0] c;
  begin hash_char=((h<<5)+h)^upper(c);end
 endfunction
 wire [15:0] current_utf=entry_utf(entry_character,{entry[7],entry[6],entry[5],entry[4],entry[3],entry[2],entry[1],entry[0]},exfat);
 wire [7:0] short_byte=entry[entry_character[3:2]]>>{entry_character[1:0],3'b000};
 wire [7:0] sum_byte=entry[checksum_byte[4:2]]>>{checksum_byte[1:0],3'b000};
 wire [63:0] next_suffix={suffix[47:0],upper(name_read_data)};
 wire valid_cluster=pending_cluster>=2 && pending_cluster-2<cluster_count;
 wire request_exists=request_id==511?pak_found:
  request_id[8:7]==0?{3'd0,request_id[6:0]}<videos:
  request_id[8:7]==1?{3'd0,request_id[6:0]}<images:
  request_id[8:7]==2?{3'd0,request_id[6:0]}<songs:
  {1'b0,request_id[6:0]}<lyrics;
 wire [15:0] attr=exfat?entry[1][15:0]:{8'd0,entry[2][31:24]};
 task fatal;
  input [7:0] code;
  begin error<=code;mounted<=0;state<=FAILED;end
 endtask
 task read_sector;
  input [31:0] address;input [1:0] mode;input [5:0] continuation;
  begin io_lba<=address;io_mode<=mode;return_state<=continuation;state<=REQUEST;end
 endtask
 task read_fat;
  input [31:0] cluster;input [1:0] purpose;
  begin
   fat_cluster<=cluster;fat_word<=cluster[6:0];fat_purpose<=purpose;
   read_sector(fat_start+(cluster>>7),2,FAT_RESULT);
  end
 endtask
 integer n;
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=START;return_state<=START;io_mode<=0;io_lba<=0;word_index<=0;io_complete<=0;io_bad<=0;
   mounted<=0;error<=0;videos<=0;images<=0;songs<=0;lyrics<=0;pak_found<=0;pak_bytes<=0;
   stat_done<=0;stat_bytes<=0;stat_hash<=0;file_done<=0;file_error<=0;
   signature<=0;part_valid<=0;part_type<=0;part_low<=0;partition_start<=0;volume_start<=0;
   fat_start<=0;heap_start<=0;cluster_count<=0;fat_length<=0;volume_sectors<=0;cluster_shift<=0;root_cluster<=0;
   exfat<=0;partitioned<=0;dir_cluster<=0;dir_first<=0;dir_sector<=0;dir_remaining<=0;dir_contiguous<=0;dir_steps<=0;
   fat_cluster<=0;fat_value<=0;fat_word<=0;fat_purpose<=0;entry_word<=0;
   queue_read<=0;queue_write<=0;queue_we<=0;next_dir_cluster<=0;next_dir_sectors<=0;next_dir_contiguous<=0;
   pending_cluster<=0;pending_size<=0;pending_valid<=0;pending_contiguous<=0;pending_directory<=0;
   name_length<=0;secondary_left<=0;expected_checksum<=0;set_checksum<=0;checksum_byte<=0;checksum_first<=0;
   ex_set<=0;ex_stream<=0;ex_names<=0;lfn_valid<=0;lfn_sequence<=0;lfn_checksum<=0;
   name_position<=0;entry_character<=0;name_write_address<=0;name_write_data<=0;name_we<=0;
   short_display<={32{8'd32}};display_length<=0;basename_hash<=0;suffix<=0;actual_name_length<=0;
   save_kind<=0;save_id<=0;save_word<=0;meta_we<=0;
   meta_address<=0;meta_query<=0;meta_write_data<=0;meta_word<=0;pak_cluster<=0;pak_hash<=0;pak_contiguous<=0;
   request_id<=0;request_sector<=0;request_channel<=0;request_stat<=0;
   map_cluster<=0;map_index<=0;target_index<=0;map_steps<=0;map_bytes<=0;map_contiguous<=0;cache_valid<=0;
   for(n=0;n<32;n=n+1)boot[n]<=0;
   for(n=0;n<8;n=n+1)entry[n]<=0;
   for(n=0;n<4;n=n+1)begin cached_cluster[n]<=0;cached_index[n]<=0;cached_id[n]<=0;end
  end else begin
   stat_done<=0;file_done<=0;meta_we<=0;name_we<=0;queue_we<=0;
   if(sd_done)begin io_complete<=1;io_bad<=sd_error;end
   case(state)
    START:if(enable)read_sector(0,0,BOOT_CHECK);
    REQUEST:if(sd_accept)begin
     state<=RECEIVE;word_index<=0;entry_word<=0;io_complete<=0;io_bad<=0;
     if(io_mode==0)begin signature<=0;part_valid<=0;end
    end
    RECEIVE:if(sd_valid && sd_ready)begin
     if(io_mode==0)begin
      if(word_index<32)boot[word_index[4:0]]<=sd_data;
      if(word_index[1:0]==0 && word_index>=112)part_type<=sd_data[23:16];
      if(word_index[1:0]==1 && word_index>=113)part_low<=sd_data[31:16];
      if(word_index[1:0]==2 && word_index>=114 && !part_valid &&
       (part_type==7 || part_type==11 || part_type==12))begin
       partition_start<={sd_data[15:0],part_low};part_valid<=1;
      end
      if(word_index==127)signature<=sd_data[31:16]==16'haa55;
     end
     if(io_mode==1)entry[word_index[2:0]]<=sd_data;
     if(io_mode==2 && word_index==fat_word)fat_value<=exfat?sd_data:{4'd0,sd_data[27:0]};
     word_index<=word_index+1'b1;
     if(io_mode==1 && word_index[2:0]==7)begin entry_word<=word_index;state<=ENTRY_CHECK;end
     else if(word_index==127)state<=COMPLETE;
    end
    COMPLETE:if(io_complete || sd_done)begin
     if(io_bad || (sd_done && sd_error))begin
      if(io_mode==3 || (io_mode==2 && fat_purpose==1))begin file_error<=1;state<=FILE_END;end else fatal(8'h41);
     end else state<=return_state;
    end
    BOOT_CHECK:begin
     if(!signature)fatal(8'h42);
     else if(boot[0][31:24]==8'h45 && boot[1]==32'h54414658 && boot[2][23:0]==24'h202020)begin
      if(boot[27][7:0]!=9 || boot[27][15:8]>16 || boot[27][23:16]<1 || boot[27][23:16]>2 ||
       boot[19]!=0 || boot[18]==0 || boot[20]==0 || boot[21]==0 || boot[22]<=boot[20] ||
       boot[23]==0 || boot[23]>32'hfffffff5 || boot[24]<2 || boot[24]-2>=boot[23] ||
       ({1'b0,volume_start}+{1'b0,boot[18]})>33'h100000000 ||
       ({1'b0,boot[20]}+((boot[27][23:16]==2)?({1'b0,boot[21]}<<1):{1'b0,boot[21]}))>{1'b0,boot[22]} ||
       ({1'b0,boot[22]}+({1'b0,boot[23]}<<boot[27][13:8]))>{1'b0,boot[18]} ||
       {1'b0,boot[21]}<(({1'b0,boot[23]}+33'd129)>>7))fatal(8'h43);
      else begin
       exfat<=1;cluster_shift<=boot[27][13:8];cluster_count<=boot[23];root_cluster<=boot[24];
       fat_start<=volume_start+boot[20]+((boot[26][16] && boot[27][23:16]==2)?boot[21]:0);
       fat_length<=boot[21];volume_sectors<=boot[18];heap_start<=volume_start+boot[22];state<=DIR_START;
      end
     end else if(boot[2][31:24]==0 && boot[3][7:0]==2 && boot[3][15:8]!=0 &&
       (boot[3][15:8]&(boot[3][15:8]-1'b1))==0 && boot[4][23:8]==0 && boot[9]!=0)begin
      if(boot[4][7:0]<1 || boot[4][7:0]>2 || boot[11]<2 || boot[8]==0 ||
       boot[3][31:16]==0 || boot[4][31:24]!=0 || boot[5][7:0]!=0 ||
       ({1'b0,boot[3][31:16]}+({1'b0,boot[9]}<<1))>={1'b0,boot[8]} ||
       ({1'b0,volume_start}+{1'b0,boot[8]})>33'h100000000 ||
       (boot[10][7] && boot[10][3:0]>=boot[4][7:0]))fatal(8'h43);
      else begin
       exfat<=0;root_cluster<={4'd0,boot[11][27:0]};fat_length<=boot[9];volume_sectors<=boot[8];
       fat_start<=volume_start+boot[3][31:16]+((boot[10][7] && boot[10][3:0]==1)?boot[9]:0);
       heap_start<=volume_start+boot[3][31:16]+((boot[4][7:0]==2)?(boot[9]<<1):boot[9]);
       case(boot[3][15:8])
        1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;8:cluster_shift<=3;
        16:cluster_shift<=4;32:cluster_shift<=5;64:cluster_shift<=6;128:cluster_shift<=7;
       endcase
       cluster_count<=(boot[8]-boot[3][31:16]-((boot[4][7:0]==2)?(boot[9]<<1):boot[9]));
       state<=DIR_START;
      end
     end else if(!partitioned && part_valid && partition_start!=0)begin
      volume_start<=partition_start;partitioned<=1;read_sector(partition_start,0,BOOT_CHECK);
     end else fatal(8'h42);
    end
    DIR_START:begin
     if(!exfat)begin
      cluster_count<=cluster_count>>cluster_shift;
      if((cluster_count>>cluster_shift)<65525 || (cluster_count>>cluster_shift)>32'h0ffffff5 ||
       root_cluster-2>=(cluster_count>>cluster_shift) ||
       {1'b0,fat_length}<(({1'b0,(cluster_count>>cluster_shift)}+33'd129)>>7))fatal(8'h43);
     end
     dir_cluster<=root_cluster;dir_first<=root_cluster;dir_sector<=0;dir_remaining<=0;dir_contiguous<=0;dir_steps<=0;
     if(exfat || ((cluster_count>>cluster_shift)>=65525 && (cluster_count>>cluster_shift)<=32'h0ffffff5 &&
      root_cluster-2<(cluster_count>>cluster_shift) &&
      {1'b0,fat_length}>=(({1'b0,(cluster_count>>cluster_shift)}+33'd129)>>7)))state<=DIR_REQUEST;
    end
    DIR_REQUEST:begin
     if(dir_cluster<2 || dir_cluster-2>=cluster_count || dir_steps>cluster_count)fatal(8'h44);
     else read_sector(dir_lba,1,DIR_NEXT);
    end
    ENTRY_CHECK:begin
     if(io_bad || (sd_done && sd_error))fatal(8'h41);
     else if(entry[0][7:0]==0)begin
      return_state<=DIR_END;state<=(entry_word==127)?COMPLETE:RECEIVE;io_mode<=2;fat_word<=127;
     end else if(exfat && (entry[0][7:0]==8'h85 || (ex_set && secondary_left!=0)))begin
      checksum_byte<=0;checksum_first<=entry[0][7:0]==8'h85;
      if(entry[0][7:0]==8'h85)set_checksum<=0;
      state<=ENTRY_SUM;
     end else if(exfat)begin ex_set<=0;state<=DIR_ENTRY;end
     else if(entry[0][7:0]==8'he5)begin lfn_valid<=0;state<=DIR_ENTRY;end
     else if(entry[2][31:24]==8'h0f)begin
      if(entry[0][4:0]==0 || entry[0][4:0]>20 || entry[0][7] || entry[0][5] ||
       entry[3][7:0]!=0 || entry[6][31:16]!=0)begin lfn_valid<=0;state<=DIR_ENTRY;end
      else begin
       if(entry[0][6])begin lfn_valid<=1;lfn_checksum<=entry[3][15:8];end
       else if(!lfn_valid || entry[0][4:0]+1!=lfn_sequence || entry[3][15:8]!=lfn_checksum)lfn_valid<=0;
       lfn_sequence<=entry[0][4:0];entry_character<=0;state<=NAME_STEP;
      end
     end else if(entry[2][27] || entry[0][7:0]==8'd46)begin lfn_valid<=0;state<=DIR_ENTRY;end
     else begin
      pending_cluster<={entry[5][15:0],entry[6][31:16]};pending_size<={32'd0,entry[7]};
      pending_contiguous<=0;pending_directory<=entry[2][28];
      name_position<=0;short_display<={32{8'd32}};display_length<=0;suffix<=0;actual_name_length<=0;
      basename_hash<=dir_first;
      if(lfn_valid && lfn_sequence==1 && lfn_checksum==short_sum({entry[7],entry[6],entry[5],entry[4],entry[3],entry[2],entry[1],entry[0]}))begin
       name_length<=255;state<=NAME_WAIT;
      end else begin name_length<=0;entry_character<=0;state<=SHORT_NAME;end
      lfn_valid<=0;
     end
    end
    ENTRY_SUM:begin
     if(!checksum_first || (checksum_byte!=2 && checksum_byte!=3))set_checksum<={set_checksum[0],set_checksum[15:1]}+sum_byte;
     if(checksum_byte==31)state<=ENTRY_PARSE;else checksum_byte<=checksum_byte+1'b1;
    end
    ENTRY_PARSE:begin
      if(entry[0][7:0]==8'h85)begin
       ex_set<=1;ex_stream<=0;ex_names<=0;secondary_left<=entry[0][15:8];
       expected_checksum<=entry[0][31:16];
       pending_directory<=entry[1][4];name_position<=0;name_length<=0;state<=DIR_ENTRY;
      end else if(ex_set && secondary_left!=0)begin
       secondary_left<=secondary_left-1'b1;
       if(entry[0][7:0]==8'hc0 && !ex_stream)begin
        ex_stream<=1;pending_contiguous<=entry[0][9];name_length<=entry[0][31:24];
        pending_valid<={entry[3],entry[2]};pending_cluster<=entry[5];pending_size<={entry[7],entry[6]};
        state<=DIR_ENTRY;
       end else if(entry[0][7:0]==8'hc1 && ex_stream)begin
        ex_names<=1;entry_character<=0;state<=NAME_STEP;
       end else begin ex_set<=0;state<=DIR_ENTRY;end
      end else begin ex_set<=0;state<=DIR_ENTRY;end
    end
    NAME_STEP:begin
     name_we<=1;name_write_data<=current_utf;
     if(exfat)begin
      name_write_address<=name_position;name_position<=name_position+1'b1;
      if(entry_character==14 || name_position+1>=name_length)state<=DIR_ENTRY;
      else entry_character<=entry_character+1'b1;
     end else begin
      name_write_address<=(entry[0][4:0]-1)*13+entry_character;
      if((entry[0][4:0]-1)*13+entry_character>254)name_we<=0;
      if(entry_character==12)state<=DIR_ENTRY;else entry_character<=entry_character+1'b1;
     end
    end
    DIR_ENTRY:begin
     if(exfat && ex_set && secondary_left==0 && ex_stream && ex_names)begin
      ex_set<=0;
      if(set_checksum!=expected_checksum || name_length==0 || pending_valid!=pending_size)fatal(8'h45);
      else begin
       name_position<=0;short_display<={32{8'd32}};display_length<=0;suffix<=0;actual_name_length<=0;basename_hash<=dir_first;
       state<=NAME_WAIT;
      end
     end else state<=(entry_word==127)?COMPLETE:RECEIVE;
    end
    NAME_WAIT:state<=NAME_BYTE;
    NAME_BYTE:begin
     if(name_read_data==0 || name_read_data==16'hffff || actual_name_length>=name_length)state<=NAME_FINISH;
     else begin
      if(actual_name_length<32)begin
       short_display<={(name_read_data>=32 && name_read_data<=126)?name_read_data[7:0]:8'd63,short_display[255:8]};
       display_length<=display_length+1'b1;
      end
      if(actual_name_length>=4)basename_hash<=hash_char(basename_hash,suffix[63:48]);
      suffix<=next_suffix;actual_name_length<=actual_name_length+1'b1;
      if(actual_name_length+1>=name_length || actual_name_length==254)state<=NAME_FINISH;
      else begin name_position<=name_position+1'b1;state<=NAME_WAIT;end
     end
    end
    SHORT_NAME:begin
     begin
      if(short_byte!=32)begin
       name_we<=1;name_write_address<=name_length;name_write_data<={8'd0,short_byte};name_length<=name_length+1'b1;
      end
      if(entry_character==10)state<=SHORT_FINISH;
      else if(entry_character==7)begin
       if(entry[2][7:0]==32)state<=SHORT_FINISH;else state<=SHORT_DOT;
      end else if(entry_character==9)entry_character<=10;
      else entry_character<=entry_character+1'b1;
     end
    end
    SHORT_DOT:begin
     name_we<=1;name_write_address<=name_length;name_write_data<=16'd46;name_length<=name_length+1'b1;
     entry_character<=8;state<=SHORT_NAME;
    end
    SHORT_FINISH:begin name_position<=0;state<=NAME_WAIT;end
    NAME_FINISH:begin
     if(pending_size[63:41]!=0)fatal(8'h48);
     else if(pending_directory)begin
      if(!valid_cluster || queue_write==63)fatal(8'h46);
      else begin
       next_dir_cluster<=pending_cluster;next_dir_contiguous<=pending_contiguous;
       next_dir_sectors<=(pending_size+511)>>9;queue_we<=1;state<=SAVE_META;save_kind<=3;
      end
     end else if(pending_size!=0 && valid_cluster)begin
      if(suffix==64'h002e005400460056)begin save_kind<=0;save_id<={2'd0,videos[6:0]};state<=NAME_PAD;end
      else if(suffix==64'h002e0042004d0050)begin save_kind<=1;save_id<={2'd1,images[6:0]};state<=NAME_PAD;end
      else if(suffix==64'h002e005700410056)begin save_kind<=2;save_id<={2'd2,songs[6:0]};state<=NAME_PAD;end
      else if(suffix==64'h002e004c00520043)begin save_kind<=3;save_id<={2'd3,lyrics[6:0]};state<=NAME_PAD;end
      else if(suffix==64'h002e00500041004b && !pak_found)begin
       pak_found<=1;pak_cluster<=pending_cluster;pak_contiguous<=pending_contiguous;
       pak_bytes<=pending_size;pak_hash<=basename_hash;state<=(entry_word==127)?COMPLETE:RECEIVE;
      end else state<=(entry_word==127)?COMPLETE:RECEIVE;
      save_word<=0;
     end else state<=(entry_word==127)?COMPLETE:RECEIVE;
    end
    NAME_PAD:begin
     if(display_length==32)state<=SAVE_NAME;
     else begin short_display<={8'd32,short_display[255:8]};display_length<=display_length+1'b1;end
    end
    SAVE_NAME:begin
     if((save_kind==0 && videos==128)||(save_kind==1 && images==128)||
        (save_kind==2 && songs==128)||(save_kind==3 && lyrics==127))fatal(8'h47);
     else begin
      if(save_word==7)begin
       meta_address<=save_id;meta_word<=0;
       meta_write_data<={basename_hash,22'd0,pending_contiguous,pending_size[40:0],pending_cluster};
       state<=META_WRITE;
      end else save_word<=save_word+1'b1;
      short_display<={32'd0,short_display[255:32]};
     end
    end
    META_WRITE:begin
     meta_write_data<={32'd0,meta_write_data[127:32]};
     if(meta_word==3)state<=SAVE_META;else meta_word<=meta_word+1'b1;
    end
    SAVE_META:begin
     if(pending_directory)queue_write<=queue_write+1'b1;
     else case(save_kind)
      0:videos<=videos+1'b1;1:images<=images+1'b1;2:songs<=songs+1'b1;3:lyrics<=lyrics+1'b1;
     endcase
     state<=(entry_word==127)?COMPLETE:RECEIVE;
    end
    DIR_NEXT:begin
     if(dir_contiguous && dir_remaining<=1)state<=DIR_END;
     else if(dir_sector==cluster_mask)begin
      dir_sector<=0;dir_steps<=dir_steps+1'b1;
      if(dir_contiguous)begin dir_cluster<=dir_cluster+1'b1;state<=DIR_REQUEST;end
      else read_fat(dir_cluster,0);
     end else begin dir_sector<=dir_sector+1'b1;state<=DIR_REQUEST;end
     if(dir_remaining!=0)dir_remaining<=dir_remaining-1'b1;
    end
    DIR_END:begin
     if(queue_read!=queue_write)begin
      dir_cluster<=queue_data[31:0];dir_first<=queue_data[31:0];dir_remaining<=queue_data[63:32];dir_contiguous<=queue_data[64];
      dir_sector<=0;dir_steps<=0;queue_read<=queue_read+1'b1;
      ex_set<=0;lfn_valid<=0;state<=DIR_REQUEST;
     end else begin mounted<=1;state<=IDLE;end
    end
    FAT_RESULT:begin
     if(fat_value>=(exfat?32'hfffffff8:32'h0ffffff8))begin
      if(fat_purpose==0)state<=DIR_END;
      else begin file_error<=1;state<=FILE_END;end
     end else if(fat_value<2 || fat_value-2>=cluster_count || fat_value==fat_cluster)begin
      if(fat_purpose==0)fatal(8'h44);else begin file_error<=1;state<=FILE_END;end
     end else if(fat_purpose==0)begin dir_cluster<=fat_value;state<=DIR_REQUEST;end
     else begin map_cluster<=fat_value;map_index<=map_index+1'b1;map_steps<=map_steps+1'b1;state<=MAP_STEP;end
    end
    IDLE:begin
     if(stat_req || file_req)begin
      request_stat<=stat_req;request_id<=stat_req?stat_id:file_id;
      meta_query<=stat_req?stat_id:file_id;meta_word<=0;request_sector<=file_sector;request_channel<=file_channel;
      file_error<=0;state<=META_WAIT;
     end
    end
    META_WAIT:state<=META_GOT;
    META_GOT:begin
     if(!request_exists || request_id==511)begin
      map_bytes<=request_exists?pak_bytes:64'd0;map_cluster<=request_exists?pak_cluster:32'd0;
      map_contiguous<=pak_contiguous;stat_hash<=pak_hash;state<=request_stat?STAT_END:MAP_PREP;
     end else begin
      case(meta_word)
       0:map_cluster<=meta_data;
       1:map_bytes[31:0]<=meta_data;
       2:begin map_bytes[63:32]<={23'd0,meta_data[8:0]};map_contiguous<=meta_data[9];end
       3:stat_hash<=meta_data;
      endcase
      if(meta_word==3)state<=request_stat?STAT_END:MAP_PREP;
      else begin meta_word<=meta_word+1'b1;state<=META_WAIT;end
     end
    end
    STAT_END:begin stat_bytes<=map_bytes;stat_done<=1;state<=IDLE;end
    MAP_PREP:begin
     target_index<=request_sector>>cluster_shift;map_index<=0;map_steps<=0;
     if({request_sector,9'd0}>=map_bytes || map_cluster<2 || map_cluster-2>=cluster_count)begin file_error<=1;state<=FILE_END;end
     else if(map_contiguous)begin map_cluster<=map_cluster+(request_sector>>cluster_shift);state<=MAP_DATA;end
     else begin
      if(cache_valid[request_channel] && cached_id[request_channel]==request_id &&
       cached_index[request_channel]<=(request_sector>>cluster_shift))begin
       map_cluster<=cached_cluster[request_channel];map_index<=cached_index[request_channel];
      end
      state<=MAP_STEP;
     end
    end
    MAP_STEP:begin
     if(map_steps>=cluster_count)begin file_error<=1;state<=FILE_END;end
     else if(map_index==target_index)state<=MAP_DATA;
     else read_fat(map_cluster,1);
    end
    MAP_DATA:begin
     if(map_cluster<2 || map_cluster-2>=cluster_count)begin file_error<=1;state<=FILE_END;end
     else begin
      cache_valid[request_channel]<=1;cached_id[request_channel]<=request_id;
      cached_cluster[request_channel]<=map_cluster;cached_index[request_channel]<=target_index;
      read_sector(heap_start+((map_cluster-2)<<cluster_shift)+(request_sector&cluster_mask),3,FILE_END);
     end
    end
    FILE_END:begin file_done<=1;state<=IDLE;end
    FAILED:begin end
    default:fatal(8'h4e);
   endcase
  end
 end
endmodule

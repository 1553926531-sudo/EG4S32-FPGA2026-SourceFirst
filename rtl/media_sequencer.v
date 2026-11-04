`timescale 1ns/1ps
                                                                             
                                                                                 
module media_sequencer #(parameter CYCLES_PER_MS=50000)(input wire clk50,input wire reset_n,input wire system_ready,
 input wire external_fault,
 output wire rd_req,output wire [31:0] rd_lba,input wire rd_accept,
 input wire [31:0] rd_data,input wire rd_valid,output wire rd_ready,
 input wire rd_done,input wire rd_error,input wire card_fatal,
 output wire [20:0] wr_address,output wire [31:0] wr_data,
 output wire wr_valid,input wire wr_ready,
 output reg publish_toggle,output reg publish_bank,input wire commit_toggle,
 output reg audio_start_toggle,output reg audio_flush_toggle,output wire [31:0] audio_total_samples,
 input wire audio_done_toggle,input wire [12:0] audio_write_level,
 output wire [31:0] audio_data,output wire audio_valid,input wire audio_ready,
 output reg [5:0] state,output reg [7:0] error_code,
 output reg [31:0] logical_lba,output reg [31:0] frame_number,
 output reg [19:0] frame_word,
                                                                       
                                                                            
 input wire pause,input wire restart,input wire [1:0] media_select,
 input wire [9:0] media_index,
 output wire [9:0] video_count,output wire [9:0] image_count,
 output reg [1:0] actual_media,output reg [9:0] actual_index);
 localparam BOOT=0,REQUEST=1,RECEIVE=2,WAIT_SD=3,DISPATCH=4,
  PUBLISH=5,WAIT_COMMIT=6,HOLD_VIDEO=7,HOLD_IMAGE=8,
  AUDIO_LOAD=9,AUDIO_PUSH=10,AUDIO_WAIT=11,FINISHED=12,
  HEADER_LAYOUT=13,HEADER_AUDIO=14,RESTART_DRAIN=15,FAILED=31;
 localparam HEADER=0,FRAME=1,TRAILER=2,AUDIO=3;
 reg [1:0] mode;
 wire map_valid;
 wire [31:0] expected_header_crc,map_file_sectors;
 media_extent_map address_map(.logical_lba(logical_lba),.physical_lba(rd_lba),
  .valid(map_valid),.expected_header_crc(expected_header_crc),.file_sectors(map_file_sectors));
 reg [31:0] header[0:17];
 assign video_count=(header[6]==0)?10'd1:header[6][9:0];
 assign image_count=10'd1;
 reg [6:0] word_index;
 reg [12:0] frame_sector;
 reg [31:0] sector_crc,frame_crc;
 reg [31:0] trailer_magic,trailer_id,trailer_crc;
 reg block_bad,is_image;
 reg [31:0] hold_cycles,hold_count;
 reg [31:0] layout_image_lba,audio_sectors,audio_capacity;
 reg [31:0] audio_remaining,audio_pushed;
 reg [31:0] audio_stage[0:126];
 reg [6:0] emit_index;
 reg [7:0] emit_count;
 reg [31:0] emit_data;
 reg audio_started;
 reg sd_inflight,publish_pending,restart_previous;
 reg [5:0] restart_settle;
 wire pause_safe = (pause === 1'b1);
 wire restart_safe = (restart === 1'b1);
 wire restart_event = restart_safe && !restart_previous;
 wire draining = state==RESTART_DRAIN;
 wire [1:0] media_select_safe = (media_select === 2'd1) ? 2'd1 :
                                 (media_select === 2'd2) ? 2'd2 : 2'd0;
 wire media_index_known = (^media_index !== 1'bx);
 wire [9:0] media_index_safe = media_index_known ? media_index : 10'd0;
 (* async_reg="true" *) reg commit_sync1,commit_sync2,audio_done_sync1,audio_done_sync2;
 function [31:0] crc_byte;
  input [31:0] old;input [7:0] data;reg [31:0] c;integer i;
  begin c=old^{24'd0,data};for(i=0;i<8;i=i+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 function [31:0] crc_word;
  input [31:0] old;input [31:0] data;
  begin crc_word=crc_byte(crc_byte(crc_byte(crc_byte(old,data[7:0]),data[15:8]),data[23:16]),data[31:24]);end
 endfunction
 assign rd_req=state==REQUEST && map_valid && !restart_safe && !external_fault && !card_fatal;
                                                                              
                                                                           
                                                                         
 assign rd_ready=((state==RECEIVE && !restart_safe) || (draining && sd_inflight)) &&
                 (mode!=FRAME || wr_ready);
 assign wr_valid=((state==RECEIVE && !restart_safe) || (draining && sd_inflight)) &&
                 mode==FRAME && rd_valid;
 assign wr_address={publish_bank,frame_word};
 assign wr_data=rd_data;
 assign audio_total_samples=header[12];
 assign audio_data=emit_data;
                                                                              
                                                                          
                                                                           
                                                                             
                              
 assign audio_valid=(state==AUDIO_PUSH) && !restart_safe && !external_fault && !card_fatal;
 integer k;
 always @(posedge clk50) begin
  if(!reset_n)begin
   state<=BOOT;error_code<=0;logical_lba<=0;frame_number<=0;frame_word<=0;
   publish_toggle<=0;publish_bank<=0;audio_start_toggle<=0;audio_flush_toggle<=0;
   actual_media<=0;actual_index<=0;
   mode<=HEADER;word_index<=0;frame_sector<=0;sector_crc<=32'hffffffff;frame_crc<=32'hffffffff;
   trailer_magic<=0;trailer_id<=0;trailer_crc<=0;block_bad<=0;is_image<=0;
   hold_cycles<=0;hold_count<=0;audio_remaining<=0;audio_pushed<=0;
   layout_image_lba<=0;audio_sectors<=0;audio_capacity<=0;
   emit_index<=0;emit_count<=0;emit_data<=0;audio_started<=0;
   sd_inflight<=0;publish_pending<=0;restart_previous<=0;restart_settle<=0;
   commit_sync1<=0;commit_sync2<=0;audio_done_sync1<=0;audio_done_sync2<=0;
   for(k=0;k<18;k=k+1)header[k]<=0;
  end else begin
   commit_sync1<=commit_toggle;commit_sync2<=commit_sync1;
   audio_done_sync1<=audio_done_toggle;audio_done_sync2<=audio_done_sync1;
   restart_previous<=restart_safe;
   if(rd_accept)sd_inflight<=1;
   if(rd_done)sd_inflight<=0;
                                                                        
                                                                           
   if(publish_pending && commit_sync2==publish_toggle)begin
    publish_pending<=0;publish_bank<=~publish_bank;
    actual_media<=is_image?2'd1:2'd0;actual_index<=is_image?10'd0:frame_number[9:0];
   end
   if(!audio_started && state!=FAILED && !draining && !restart_safe &&
     !external_fault && !card_fatal && audio_pushed!=0 &&
     (audio_pushed>=1024 || audio_pushed>=header[12]))begin
    audio_start_toggle<=~audio_start_toggle;audio_started<=1;
   end
   if(restart_event && !draining)begin
    state<=RESTART_DRAIN;restart_settle<=6'd31;
    audio_flush_toggle<=~audio_flush_toggle;audio_started<=0;
   end else if(draining)begin
    if(rd_valid && rd_ready && mode==FRAME)frame_word<=frame_word+1'b1;
    if(restart_settle!=0)restart_settle<=restart_settle-1'b1;
                                                                      
                                                            
    if(!sd_inflight && !publish_pending && restart_settle==0)begin
     state<=BOOT;error_code<=0;logical_lba<=0;frame_number<=0;frame_word<=0;
     mode<=HEADER;word_index<=0;frame_sector<=0;sector_crc<=32'hffffffff;
     frame_crc<=32'hffffffff;block_bad<=0;is_image<=0;hold_count<=0;
     audio_remaining<=0;audio_pushed<=0;audio_started<=0;emit_index<=0;
     emit_count<=0;emit_data<=0;
    end
   end else if(external_fault || card_fatal)begin
    if(state!=FAILED)audio_flush_toggle<=~audio_flush_toggle;
    state<=FAILED;if(error_code==0)error_code<=card_fatal?8'h02:8'h07;
   end else if((state==RECEIVE || state==WAIT_SD) && rd_done && rd_error)begin
    state<=FAILED;error_code<=8'h02;
   end else case(state)
    BOOT:if(system_ready)begin mode<=HEADER;logical_lba<=0;state<=REQUEST;end
    REQUEST:begin
     word_index<=0;block_bad<=0;sector_crc<=32'hffffffff;
     if(!map_valid || logical_lba>=map_file_sectors)begin state<=FAILED;error_code<=8'h01;end
     else if(rd_accept)state<=RECEIVE;
    end
    RECEIVE:if(rd_valid && rd_ready)begin
     if(mode==FRAME)begin
      frame_crc<=crc_word(frame_crc,rd_data);frame_word<=frame_word+1'b1;
      if(rd_data[31:24]!=0)block_bad<=1;
     end else begin
      if(word_index<127)sector_crc<=crc_word(sector_crc,rd_data);
      else if(rd_data!=~sector_crc || (mode==HEADER && rd_data!=expected_header_crc))block_bad<=1;
      if(mode==HEADER && word_index<18)header[word_index]<=rd_data;
      if(mode==TRAILER)case(word_index)
       0:trailer_magic<=rd_data;1:trailer_id<=rd_data;2:trailer_crc<=rd_data;default:begin end
      endcase
      if(mode==AUDIO && word_index<127)begin
       audio_stage[word_index]<=rd_data;
       if(word_index>=audio_remaining && rd_data!=0)block_bad<=1;
      end
     end
     if(word_index==127)state<=WAIT_SD;else word_index<=word_index+1'b1;
    end
    WAIT_SD:if(rd_done)begin
     if(block_bad)begin state<=FAILED;error_code<=mode==AUDIO?8'h06:8'h03;end
     else state<=DISPATCH;
    end
    DISPATCH:case(mode)
     HEADER:begin
      if(header[0]!=32'h314d4654 || header[1]!=1 || header[2]!=1280 || header[3]!=800 ||
       header[4]!=1 || header[5]!=1024000 || header[6]==0 || header[6]>600 ||
       header[7]<1000 || header[7]>60000 || header[8]!=1 || header[9]!=8001 ||
       header[12]==0 || header[12]>172800000 || header[13]!=48000 || header[14]!=16 || header[15]!=2 ||
       header[16]<1000 || header[16]>60000 || header[17]!=map_file_sectors)begin state<=FAILED;error_code<=8'h04;end
      else begin
                                                                                 
       layout_image_lba<=1+header[6]*8001;
       audio_sectors<=header[17]-header[11];
       hold_cycles<=header[7]*CYCLES_PER_MS;state<=HEADER_LAYOUT;
      end
     end
     FRAME:begin
      logical_lba<=logical_lba+1'b1;
      if(frame_sector==7999)mode<=TRAILER;else frame_sector<=frame_sector+1'b1;
      state<=REQUEST;
     end
     TRAILER:begin
      if(frame_word!=1024000 || trailer_magic!=32'h43524346 || trailer_crc!=~frame_crc ||
       trailer_id!=(is_image?32'hffffffff:frame_number))begin state<=FAILED;error_code<=8'h05;end
      else state<=PUBLISH;
     end
     AUDIO:begin
      emit_index<=0;emit_count<=(audio_remaining>=127)?8'd127:audio_remaining[7:0];
      state<=AUDIO_LOAD;
     end
     default:begin state<=FAILED;error_code<=8'h04;end
    endcase
    HEADER_LAYOUT:begin
     audio_capacity<=(audio_sectors<<7)-audio_sectors;
     if(header[10]!=layout_image_lba || header[11]!=header[10]+8001 ||
       header[17]<=header[11] || audio_sectors>1360630)begin state<=FAILED;error_code<=8'h04;end
     else state<=HEADER_AUDIO;
    end
    HEADER_AUDIO:begin
                                                                       
     if(header[12]>audio_capacity || header[12]<=audio_capacity-127)begin state<=FAILED;error_code<=8'h04;end
     else begin
      frame_crc<=32'hffffffff;frame_sector<=0;frame_word<=0;
      audio_pushed<=0;audio_started<=0;
      if(media_select_safe==2'd2)begin
       actual_media<=2'd2;actual_index<=0;
                                                                          
       is_image<=0;logical_lba<=header[11];audio_remaining<=header[12];
       mode<=AUDIO;state<=REQUEST;
      end else if(media_select_safe==2'd1)begin
                                                                           
                                                                     
       is_image<=1;logical_lba<=header[10];mode<=FRAME;state<=REQUEST;
      end else begin
       is_image<=0;
       if (media_index_safe < header[6]) begin
        frame_number<=media_index_safe;
        logical_lba<=1 + media_index_safe*header[9];
       end else begin
        frame_number<=0;logical_lba<=1;
       end
       mode<=FRAME;state<=REQUEST;
      end
     end
    end
    PUBLISH:begin publish_toggle<=~publish_toggle;publish_pending<=1;state<=WAIT_COMMIT;end
    WAIT_COMMIT:if(commit_sync2==publish_toggle)begin
     hold_count<=0;state<=is_image?HOLD_IMAGE:HOLD_VIDEO;
    end
    HOLD_VIDEO:begin
     if(!pause_safe)begin
      if(hold_count==hold_cycles-1)begin
       frame_sector<=0;frame_word<=0;frame_crc<=32'hffffffff;
       mode<=FRAME;state<=REQUEST;
       if(frame_number+1<header[6])begin frame_number<=frame_number+1'b1;logical_lba<=logical_lba+1'b1;end
       else begin is_image<=1;logical_lba<=header[10];hold_cycles<=header[16]*CYCLES_PER_MS;end
      end else hold_count<=hold_count+1'b1;
     end
    end
    HOLD_IMAGE:begin
     if(!pause_safe)begin
      if(hold_count==hold_cycles-1)begin
       mode<=AUDIO;logical_lba<=header[11];audio_remaining<=header[12];state<=REQUEST;
      end else hold_count<=hold_count+1'b1;
     end
    end
    AUDIO_LOAD:begin emit_data<=audio_stage[emit_index];state<=AUDIO_PUSH;end
    AUDIO_PUSH:if(audio_ready)begin
     audio_pushed<=audio_pushed+1'b1;
     if(emit_index+1>=emit_count)begin
      audio_remaining<=audio_remaining-emit_count;logical_lba<=logical_lba+1'b1;
      if(audio_remaining<=emit_count)state<=AUDIO_WAIT;else state<=REQUEST;
     end else begin emit_index<=emit_index+1'b1;state<=AUDIO_LOAD;end
    end
    AUDIO_WAIT:if(audio_started && audio_done_sync2==audio_start_toggle)state<=FINISHED;
    FINISHED:begin end
    FAILED:begin end
    default:begin state<=FAILED;error_code<=8'hff;end
   endcase
  end
 end
endmodule

`timescale 1ns/1ps
module media_file_adapter(
 input wire clk,input wire reset_n,input wire prepare,input wire [8:0] select_file,
 input wire [1:0] select_kind,input wire legacy,
 output reg prepared,output reg [7:0] error,output reg raw_media,
 output reg [31:0] sectors,output reg [9:0] legacy_images,output reg [9:0] legacy_songs,
 input wire [7:0] lyric_files,
 output reg stat_req,output reg [8:0] stat_id,input wire stat_done,
 input wire [63:0] stat_bytes,input wire [31:0] stat_hash,
 output wire file_req,output wire [8:0] file_id,output wire [31:0] file_sector,
 output wire [1:0] file_channel,input wire file_accept,input wire [31:0] file_data,
 input wire file_valid,output wire file_ready,input wire file_done,input wire file_error,
 input wire rd_req,input wire [31:0] rd_lba,output wire rd_accept,
 output wire [31:0] rd_data,output wire rd_valid,input wire rd_ready,
 output reg rd_done,output reg rd_error
);
 localparam OFF=0,STAT=1,PARSE=2,GET_WORD=3,WORD_WAIT=4,BMP_CHECK=5,BMP_SPAN=6,
  WAV_CHUNK=7,WAV_STEP=8,WAV_FMT=9,WAV_CHECK=10,DIVIDE=11,READY=12,PASS=13,
  SYNTH=14,EMIT=15,NEXT=16,PIXEL_DIV=17,PIXEL_START=18,PIXEL_GOT=19,AUDIO_GOT=20,
  FINISH=21,LYRIC_STAT=22,LYRIC_MATCH=23,LRC_START=24,LRC_READ=25,LRC_BYTE=26,
  LRC_LINE=27,LRC_END=28,RAW_HEADER=29,RAW_CHECK=30,CUE_PAD=31,FAIL=63;
 localparam PIXELS=32'd8192,AUDIO=32'h00100000;
 reg [5:0] state,after_word,after_divide;
 reg [8:0] selected,word_file,lyric_file;
 reg [1:0] kind;
 reg is_legacy,servicing_read;
 reg [63:0] file_bytes,lyric_bytes;
 reg [31:0] selected_hash;
 reg [40:0] word_offset;
 reg [2:0] word_bytes;
 wire word_accept,word_done,word_error;
 wire [31:0] word_data;
 wire reader_req,reader_ready;
 wire [8:0] reader_file;
 wire [31:0] reader_sector;
 reg [31:0] fields[0:7];
 reg [7:0] field_index;
 reg [11:0] source_width,source_height;
 reg [13:0] source_stride;
 reg [31:0] source_offset,samples,audio_sectors;
 reg [31:0] chunk_offset,chunk_size,chunk_id,riff_end,data_bytes,fmt_offset;
 reg [12:0] chunk_steps;
 reg top_down,pixel32,fmt_seen,data_seen;
 reg [5:0] row_sectors;
 reg [31:0] divide_q,divide_r,divide_d;
 reg [5:0] divide_bits;
 reg [31:0] request_lba,current_x,emit_data;
 reg [11:0] source_row;
 reg [6:0] emit_index;
 reg [2:0] synth_kind;
 reg [7:0] lyric_scan;
 reg lyric_found;
 reg [12:0] cue_count,cue_target,cue_number;
 reg [31:0] lrc_position,lrc_resume,lrc_previous,lrc_resume_previous,cue_sample;
 reg [12:0] lrc_resume_index;
 reg [2:0] lrc_phase;
 reg [9:0] lrc_minutes,lrc_seconds,lrc_fraction;
 reg [2:0] fraction_digits;
 reg [6:0] cue_length;
 reg [6:0] cue_pad_length;
 reg [639:0] cue_text;
 reg count_only,lrc_digits,lrc_line_valid,lrc_last;
 wire [7:0] lrc_char=word_data[7:0];
 wire lrc_digit=lrc_char>=48 && lrc_char<=57;
 wire [9:0] fraction_ms=fraction_digits==0?10'd0:fraction_digits==1?lrc_fraction*10'd100:
  fraction_digits==2?lrc_fraction*10'd10:lrc_fraction;
 wire [11:0] line_seconds=lrc_minutes[5:0]*12'd60+lrc_seconds[5:0];
 wire [27:0] line_sample=line_seconds*28'd48000+fraction_ms*28'd48;
 wire [25:0] bmp_span=source_stride*source_height;
 wire [16:0] image_sectors=row_sectors*source_height;
 wire [25:0] bmp_row_offset=source_row*source_stride;
 wire [13:0] bmp_x_offset=pixel32?{current_x[11:0],2'b00}:
                                         ({current_x[11:0],1'b0}+current_x[11:0]);
 wire [32:0] trial={divide_r,divide_q[31]};
 wire [32:0] difference=trial-{1'b0,divide_d};
 wire [31:0] quotient_next={divide_q[30:0],!difference[32]};
 wire [31:0] remainder_next=difference[32]?trial[31:0]:difference[31:0];
 wire pass_request=state==READY && !raw_media && rd_req;
 wire pass_active=state==PASS;
 file_word_reader reader(.clk(clk),.reset_n(reset_n),.invalidate(prepare),
  .request(state==GET_WORD),.file_id(word_file),.offset(word_offset),.bytes(word_bytes),
  .accept(word_accept),.done(word_done),.error(word_error),.data(word_data),
  .file_req(reader_req),.file_select(reader_file),.file_sector(reader_sector),
  .file_accept(file_accept && !pass_request && !pass_active),.file_data(file_data),
  .file_valid(file_valid && !pass_active),.file_ready(reader_ready),
  .file_done(file_done && !pass_active),.file_error(file_error));
 assign file_req=pass_request || reader_req;
 assign file_id=(pass_request || pass_active)?selected:reader_file;
 assign file_sector=(pass_request || pass_active)?rd_lba:reader_sector;
 assign file_channel=(pass_request || pass_active)?2'd0:(word_file==lyric_file && lyric_found)?2'd3:
  (after_word==AUDIO_GOT)?2'd2:(after_word==PIXEL_GOT)?2'd1:2'd0;
 assign file_ready=pass_active?rd_ready:reader_ready;
 assign rd_accept=(state==READY && raw_media && rd_req) || (pass_request && file_accept);
 assign rd_valid=(pass_active && file_valid) || state==EMIT;
 assign rd_data=pass_active?file_data:emit_data;
 task fail;
  input [7:0] code;
  begin
   error<=code;prepared<=0;state<=FAIL;
   if(servicing_read)begin rd_done<=1;rd_error<=1;servicing_read<=0;end
  end
 endtask
 task get_word;
  input [8:0] id;input [40:0] address;input [2:0] size;input [5:0] continuation;
  begin word_file<=id;word_offset<=address;word_bytes<=size;after_word<=continuation;state<=GET_WORD;end
 endtask
 task divide;
  input [31:0] numerator;input [31:0] denominator;input [5:0] continuation;
  begin divide_q<=numerator;divide_r<=0;divide_d<=denominator;divide_bits<=32;after_divide<=continuation;state<=DIVIDE;end
 endtask
 function [31:0] bmp_field_offset;
  input [7:0] index;
  begin case(index)0:bmp_field_offset=0;1:bmp_field_offset=10;2:bmp_field_offset=14;
   3:bmp_field_offset=18;4:bmp_field_offset=22;5:bmp_field_offset=26;default:bmp_field_offset=30;endcase end
 endfunction
 function [31:0] header_word;
  input [6:0] index;
  input [31:0] pcm_samples,pcm_sectors;
  input [12:0] cues;
  begin case(index)
   0:header_word=32'h314d4654;1:header_word=3;2:header_word=1280;3:header_word=800;
   4:header_word=1;5:header_word=1024000;6:header_word=1;7:header_word=1000;
   8:header_word=1;9:header_word=1;10:header_word=2;11:header_word=AUDIO;
   12:header_word=pcm_samples;13:header_word=48000;14:header_word=16;15:header_word=2;
   16:header_word=5000;17:header_word=AUDIO+pcm_sectors;18:header_word=1;19:header_word=1;
   20:header_word=1;21:header_word=3;22:header_word=2;23:header_word=32+{19'd0,cues};
   default:header_word=0;endcase end
 endfunction
 integer i;
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=OFF;after_word<=OFF;after_divide<=OFF;prepared<=0;error<=0;raw_media<=0;servicing_read<=0;
   sectors<=0;legacy_images<=0;legacy_songs<=0;stat_req<=0;stat_id<=0;selected<=0;kind<=0;is_legacy<=0;
   file_bytes<=0;selected_hash<=0;word_file<=0;word_offset<=0;word_bytes<=4;field_index<=0;
   source_width<=0;source_height<=0;source_stride<=0;source_offset<=0;samples<=1;audio_sectors<=1;
   chunk_offset<=0;chunk_size<=0;chunk_id<=0;riff_end<=0;data_bytes<=0;fmt_offset<=0;chunk_steps<=0;
   top_down<=0;pixel32<=0;fmt_seen<=0;data_seen<=0;row_sectors<=0;
   divide_q<=0;divide_r<=0;divide_d<=1;divide_bits<=0;request_lba<=0;current_x<=0;
   source_row<=0;emit_data<=0;emit_index<=0;synth_kind<=0;rd_done<=0;rd_error<=0;
   lyric_scan<=0;lyric_file<=0;lyric_bytes<=0;lyric_found<=0;cue_count<=0;cue_target<=0;cue_number<=0;
   lrc_position<=0;lrc_resume<=0;lrc_previous<=0;lrc_resume_previous<=0;lrc_resume_index<=0;cue_sample<=0;
   lrc_phase<=0;lrc_minutes<=0;lrc_seconds<=0;lrc_fraction<=0;fraction_digits<=0;cue_length<=0;cue_pad_length<=0;
   cue_text<={80{8'd32}};count_only<=0;lrc_digits<=0;lrc_line_valid<=0;lrc_last<=0;
   for(i=0;i<8;i=i+1)fields[i]<=0;
  end else begin
   stat_req<=0;rd_done<=0;
   if(prepare && (state==OFF || state==READY || state==FAIL))begin
    selected<=select_file;kind<=select_kind;is_legacy<=legacy;raw_media<=!legacy && select_kind!=0;
    prepared<=0;error<=0;rd_error<=0;stat_id<=select_file;stat_req<=1;state<=STAT;
    fmt_seen<=0;data_seen<=0;chunk_steps<=0;cue_count<=0;lyric_found<=0;lyric_scan<=0;
    lrc_resume<=0;lrc_resume_index<=0;lrc_resume_previous<=0;
   end else case(state)
    OFF:begin end
    STAT:if(stat_done)begin
     file_bytes<=stat_bytes;selected_hash<=stat_hash;field_index<=0;
     if(stat_bytes==0 || stat_bytes[63:41]!=0)fail(8'h51);
     else if(raw_media)state<=PARSE;
     else if(stat_bytes[8:0]!=0)fail(8'h52);
     else begin sectors<=stat_bytes[40:9];get_word(selected,0,4,RAW_HEADER);end
    end
    RAW_HEADER:begin
     if(field_index<8)fields[field_index[2:0]]<=word_data;
     if(field_index==18)legacy_images<=word_data[9:0];
     if(field_index==20)legacy_songs<=word_data[9:0];
     if(field_index==23)state<=RAW_CHECK;
     else begin field_index<=field_index+1'b1;get_word(selected,{31'd0,(field_index+8'd1),2'd0},4,RAW_HEADER);end
    end
    RAW_CHECK:begin
     if(fields[0]!=32'h314d4654 || fields[1]!=3 || fields[2]!=1280 || fields[3]!=800 ||
      fields[4]!=1 || fields[5]!=1024000 || fields[6]==0 || fields[6]>1000000 ||
      legacy_images>600 || legacy_songs>600 || (!is_legacy && (legacy_images!=0 || legacy_songs!=0)))fail(8'h52);
     else begin prepared<=1;state<=READY;end
    end
    PARSE:begin
     if(kind==1)get_word(selected,{9'd0,bmp_field_offset(field_index)},4,BMP_CHECK);
     else get_word(selected,{31'd0,field_index,2'd0},4,WAV_CHECK);
    end
    GET_WORD:if(word_accept)state<=WORD_WAIT;
    WORD_WAIT:if(word_done)begin
     if(word_error)begin rd_error<=1;fail(8'h53);end else state<=after_word;
    end
    BMP_CHECK:begin
     fields[field_index[2:0]]<=word_data;
     if(field_index==6)state<=BMP_SPAN;
     else begin field_index<=field_index+1'b1;state<=PARSE;end
    end
    BMP_SPAN:begin
     if(fields[0][15:0]!=16'h4d42 || fields[2]<40 || fields[2]>124 || fields[1]<14+fields[2] ||
      fields[3]==0 || fields[3]>2048 || fields[4]==0 || fields[4]==32'h80000000 ||
      (fields[4][31]?(~fields[4]+1):fields[4])>2048 || fields[5][15:0]!=1 ||
      (fields[5][31:16]!=24 && fields[5][31:16]!=32) || fields[6]!=0)fail(8'h54);
     else begin
      source_width<=fields[3];source_height<=fields[4][31]?(~fields[4]+1):fields[4];
      source_offset<=fields[1];top_down<=fields[4][31];pixel32<=fields[5][31:16]==32;
      source_stride<=(((fields[5][31:16]==32)?{fields[3][11:0],2'b00}:
                         ({fields[3][11:0],1'b0}+fields[3][11:0]))+14'd3)&14'h3ffc;
      row_sectors<=(fields[3]+127)>>7;samples<=1;audio_sectors<=1;field_index<=0;state<=WAV_STEP;
     end
    end
    WAV_CHECK:begin
     fields[field_index[2:0]]<=word_data;
     if(field_index==2)begin
      if(fields[0]!=32'h46464952 || word_data!=32'h45564157 || fields[1]<36 || fields[1]>32'hfffffff7 ||
       {32'd0,fields[1]}+64'd8>file_bytes)fail(8'h55);
      else begin riff_end<=fields[1]+8;chunk_offset<=12;field_index<=0;state<=WAV_CHUNK;end
     end else begin field_index<=field_index+1'b1;state<=PARSE;end
    end
    WAV_CHUNK:begin
     if(chunk_steps==4096 || chunk_offset>riff_end-8)fail(8'h55);
     else get_word(selected,{9'd0,chunk_offset}+{31'd0,field_index,2'd0},4,WAV_FMT);
    end
    WAV_FMT:begin
     if(field_index==0)begin chunk_id<=word_data;field_index<=1;state<=WAV_CHUNK;end
     else if(field_index==1)begin
      chunk_size<=word_data;field_index<=0;
      if({1'b0,chunk_offset}+33'd8+{1'b0,word_data}>{1'b0,riff_end})fail(8'h55);
      else if(chunk_id==32'h20746d66)begin
       if(fmt_seen || word_data<16)fail(8'h55);
       else begin fmt_offset<=chunk_offset+8;field_index<=2;get_word(selected,{9'd0,chunk_offset}+41'd8,4,WAV_FMT);end
      end else if(chunk_id==32'h61746164)begin
       if(data_seen || word_data==0 || word_data[1:0]!=0)fail(8'h55);
       else begin data_seen<=1;source_offset<=chunk_offset+8;data_bytes<=word_data;state<=WAV_STEP;end
      end else state<=WAV_STEP;
     end else begin
      fields[field_index-2]<=word_data;
      if(field_index==5)begin fmt_seen<=1;field_index<=0;state<=WAV_STEP;end
      else begin field_index<=field_index+1'b1;get_word(selected,{9'd0,fmt_offset}+{31'd0,(field_index-8'd1),2'd0},4,WAV_FMT);end
     end
    end
    WAV_STEP:begin
     if(kind==1)begin
      if({1'b0,source_offset}+{7'd0,bmp_span}>file_bytes)fail(8'h54);
      else begin sectors<=AUDIO+1;prepared<=1;state<=READY;end
     end else if(fmt_seen && data_seen)begin
      if(fields[0]!=32'h00020001 || fields[1]!=48000 || fields[2]!=192000 || fields[3]!=32'h00100004 ||
       (data_bytes>>2)>172800000)fail(8'h56);
      else begin
       samples<=data_bytes>>2;source_width<=1;source_height<=1;source_stride<=4;row_sectors<=1;
       top_down<=1;pixel32<=1;divide((data_bytes>>2)+126,127,LYRIC_STAT);
      end
     end else begin chunk_offset<=chunk_offset+8+chunk_size+{31'd0,chunk_size[0]};chunk_steps<=chunk_steps+1'b1;state<=WAV_CHUNK;end
    end
    DIVIDE:begin
     divide_q<=quotient_next;divide_r<=remainder_next;divide_bits<=divide_bits-1'b1;
     if(divide_bits==1)state<=after_divide;
    end
    LYRIC_STAT:begin
     audio_sectors<=divide_q;sectors<=AUDIO+divide_q;
     if(lyric_scan<lyric_files)begin stat_id<={2'd3,lyric_scan[6:0]};stat_req<=1;state<=LYRIC_MATCH;end
     else if(lyric_found)begin count_only<=1;cue_target<=0;state<=LRC_START;end
     else begin prepared<=1;state<=READY;end
    end
    LYRIC_MATCH:if(stat_done)begin
     if(stat_hash==selected_hash)begin
      if(lyric_found || stat_bytes==0 || stat_bytes>1048576)fail(8'h57);
      else begin lyric_file<=stat_id;lyric_bytes<=stat_bytes;lyric_found<=1;lyric_scan<=lyric_scan+1'b1;state<=LYRIC_STAT;end
     end else begin lyric_scan<=lyric_scan+1'b1;state<=LYRIC_STAT;end
    end
    LRC_START:begin
     if(!count_only && cue_target==lrc_resume_index)begin
      lrc_position<=lrc_resume;cue_number<=lrc_resume_index;lrc_previous<=lrc_resume_previous;
     end else begin lrc_position<=0;cue_number<=0;lrc_previous<=0;end
     lrc_phase<=0;lrc_digits<=0;lrc_line_valid<=0;lrc_last<=0;cue_length<=0;cue_text<={80{8'd32}};
     lrc_minutes<=0;lrc_seconds<=0;lrc_fraction<=0;fraction_digits<=0;state<=LRC_READ;
    end
    LRC_READ:begin
     if({32'd0,lrc_position}>=lyric_bytes)begin lrc_last<=1;state<=LRC_LINE;end
     else get_word(lyric_file,{9'd0,lrc_position},1,LRC_BYTE);
    end
    LRC_BYTE:begin
     lrc_position<=lrc_position+1'b1;state<=LRC_READ;
     if(lrc_char==10)state<=LRC_LINE;
     else if(lrc_char!=13)case(lrc_phase)
      0:if(lrc_char==91)begin lrc_phase<=1;lrc_minutes<=0;lrc_seconds<=0;lrc_fraction<=0;fraction_digits<=0;lrc_digits<=0;end
      1:if(lrc_digit && lrc_minutes<60)begin lrc_minutes<=lrc_minutes*10'd10+{6'd0,lrc_char[3:0]};lrc_digits<=1;end
        else if(lrc_char==58 && lrc_digits)begin lrc_phase<=2;lrc_digits<=0;end else lrc_phase<=5;
      2:if(lrc_digit && lrc_seconds<60)begin lrc_seconds<=lrc_seconds*10'd10+{6'd0,lrc_char[3:0]};lrc_digits<=1;end
        else if(lrc_char==46 && lrc_digits)lrc_phase<=3;
        else if(lrc_char==93 && lrc_digits && lrc_seconds<60)begin lrc_phase<=4;lrc_line_valid<=1;end
        else lrc_phase<=5;
      3:if(lrc_digit)begin
         if(fraction_digits<3)begin lrc_fraction<=lrc_fraction*10'd10+{6'd0,lrc_char[3:0]};fraction_digits<=fraction_digits+1'b1;end
        end else if(lrc_char==93 && lrc_seconds<60)begin lrc_phase<=4;lrc_line_valid<=1;end else lrc_phase<=5;
      4:if(cue_length==78 || lrc_char<32 || lrc_char>126)fail(8'h58);
        else begin if(!count_only)cue_text<={lrc_char,cue_text[639:8]};cue_length<=cue_length+1'b1;end
      default:begin end
     endcase
    end
    LRC_LINE:begin
     if(lrc_line_valid)begin
      if(cue_number==4096 || lrc_minutes>=60 || lrc_seconds>=60 ||
         line_sample>=samples || (cue_number!=0 && line_sample<=lrc_previous))fail(8'h58);
      else begin
       cue_sample<=line_sample;lrc_previous<=line_sample;cue_number<=cue_number+1'b1;
       lrc_resume<=lrc_position;lrc_resume_index<=cue_number+1'b1;lrc_resume_previous<=line_sample;
       if(!count_only && cue_number==cue_target)begin
        synth_kind<=3;emit_index<=0;cue_pad_length<=cue_length;state<=CUE_PAD;
       end
       else if(lrc_last)state<=LRC_END;
       else begin lrc_phase<=0;lrc_line_valid<=0;cue_length<=0;cue_text<={80{8'd32}};state<=LRC_READ;end
      end
     end else if(lrc_last)state<=LRC_END;
     else begin lrc_phase<=0;lrc_line_valid<=0;cue_length<=0;cue_text<={80{8'd32}};state<=LRC_READ;end
    end
    LRC_END:begin
     if(count_only)begin cue_count<=cue_number;prepared<=1;state<=READY;end
     else begin rd_error<=1;state<=FINISH;end
    end
    CUE_PAD:begin
     if(cue_pad_length==80)state<=SYNTH;
     else begin cue_text<={8'd32,cue_text[639:8]};cue_pad_length<=cue_pad_length+1'b1;end
    end
    READY:begin
     if(raw_media && rd_req)begin
      request_lba<=rd_lba;emit_index<=0;rd_error<=0;servicing_read<=1;
      if(rd_lba==0)begin synth_kind<=0;state<=SYNTH;end
      else if(rd_lba==1 || rd_lba==2)begin synth_kind<=1;state<=SYNTH;end
      else if(rd_lba==3 || rd_lba==4)begin synth_kind<=2;state<=SYNTH;end
      else if(rd_lba>=32 && rd_lba<32+cue_count)begin cue_target<=rd_lba-32;count_only<=0;state<=LRC_START;end
      else if(rd_lba>=PIXELS && rd_lba<PIXELS+image_sectors)divide(rd_lba-PIXELS,{26'd0,row_sectors},PIXEL_DIV);
      else if(rd_lba>=AUDIO && rd_lba<AUDIO+audio_sectors)begin synth_kind<=5;current_x<=(rd_lba-AUDIO)*127;state<=PIXEL_START;end
      else begin rd_error<=1;state<=FINISH;end
     end else if(pass_request && file_accept)begin servicing_read<=1;rd_error<=0;state<=PASS;end
    end
    PASS:if(file_done)begin rd_done<=1;rd_error<=file_error;servicing_read<=0;state<=READY;end
    PIXEL_DIV:begin
     source_row<=top_down?divide_q[11:0]:(source_height-12'd1-divide_q[11:0]);
     current_x<=divide_r<<7;synth_kind<=4;state<=PIXEL_START;
    end
    SYNTH:begin
     emit_data<=0;
     case(synth_kind)
      0:emit_data<=header_word(emit_index,samples,audio_sectors,cue_count);
      1:case(emit_index)
       0:emit_data<=32'h32474d49;1:emit_data<=(request_lba==1)?32'd0:32'h80000000;
       2:emit_data<=source_width;3:emit_data<=source_height;4:emit_data<=PIXELS;
       5:emit_data<={26'd0,row_sectors};6:emit_data<={15'd0,image_sectors};
       default:begin end
      endcase
      2:case(emit_index)
       0:emit_data<=32'h33445541;1:emit_data<=request_lba-3;2:emit_data<=AUDIO;
       3:emit_data<=samples;4:emit_data<=audio_sectors;6:emit_data<=cue_count==0?32'd0:32'd32;
       7:emit_data<={19'd0,cue_count};default:begin end
      endcase
      3:begin
       case(emit_index)0:emit_data<=32'h33455543;1:emit_data<=cue_sample;
        2:emit_data<={19'd0,cue_target};3:emit_data<={25'd0,cue_length};
        default:if(emit_index>=4 && emit_index<24)emit_data<=cue_text[31:0];
       endcase
      end
      default:begin end
     endcase
     state<=EMIT;
    end
    PIXEL_START:begin
     if(synth_kind==5)begin
      if(emit_index==127 || current_x>=samples)begin emit_data<=0;state<=EMIT;end
      else get_word(selected,{9'd0,source_offset}+{7'd0,current_x,2'd0},4,AUDIO_GOT);
     end else if(kind==2)begin emit_data<=(current_x==0)?32'h00101820:32'd0;state<=EMIT;end
     else if(current_x>=source_width)begin emit_data<=0;state<=EMIT;end
     else get_word(selected,{9'd0,source_offset}+{15'd0,bmp_row_offset}+
      {27'd0,bmp_x_offset},pixel32?3'd4:3'd3,PIXEL_GOT);
    end
    PIXEL_GOT:begin emit_data<={8'd0,word_data[23:0]};state<=EMIT;end
    AUDIO_GOT:begin emit_data<=word_data;state<=EMIT;end
    EMIT:if(rd_ready)begin
     if(synth_kind==3 && emit_index>=4 && emit_index<24)cue_text<={32'd0,cue_text[639:32]};
     if(emit_index==127)state<=FINISH;
     else begin emit_index<=emit_index+1'b1;current_x<=current_x+1'b1;state<=NEXT;end
    end
    NEXT:state<=(synth_kind>=4)?PIXEL_START:SYNTH;
    FINISH:begin rd_done<=1;servicing_read<=0;state<=READY;end
    FAIL:begin end
    default:fail(8'h5f);
   endcase
  end
 end
endmodule

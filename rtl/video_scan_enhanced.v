`timescale 1ns/1ps
                                                               
  
                                                                            
                                                                             
                                                                          
                                                                            
                                                                              
                                                                               
                                                                             
                                                                              
                                                                  
module video_scan_enhanced #(parameter PLAYER_UI=0)(
    input  wire        pclk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire        fatal,
    input  wire [31:0] pixel_data,
    input  wire        pixel_valid,
    input  wire [13:0] pixel_level,
    output wire        pixel_ready,
    output reg         underrun,
    input  wire [7:0]  brightness,
    input  wire [7:0]  contrast,
    input  wire [1:0]  zoom_mode,
    input  wire        waveform_enable,
    input  wire        subtitle_enable,
    input  wire        overlay_enable,
    input  wire [1:0]  transition_mode,
    input  wire        paused,
    input  wire [1:0]  media_select,
    input  wire [9:0]  media_index,
    input  wire [15:0] audio_level,
    input  wire [15:0] audio_pcm,
    input  wire        audio_sample_toggle,
    input  wire        audio_flush_toggle,
    input  wire        frame_commit_toggle,
    input wire [639:0] lyric_text,input wire lyric_valid,input wire lyric_toggle,
    input wire [1:0] ui_page,input wire [10:0] browser_cursor,input wire [10:0] library_count,
    input wire [9:0] video_count,input wire [9:0] image_count,
    input wire [23:0] play_time,input wire [23:0] total_time,input wire [23:0] target_time,
    input wire [10:0] progress_mark,input wire [1:0] seek_step,
    input wire [4:0] volume,input wire muted,
    input wire library_ready,input wire has_opened,input wire [7:0] media_error,
    input wire [7:0] name_code,output wire [11:0] name_id,output wire [4:0] name_char,
    output reg [23:0]  rgb,
    output reg         de,
    output reg         hs,
    output reg         vs
);
    reg [10:0] h;
    reg [9:0]  v;
    reg        started;
    reg        zoom_active;
    reg [7:0]  transition_alpha;
    reg [10:0] wipe_limit;
    reg [10:0] slide_offset;
    reg commit_seen;
    reg [1:0] transition_previous;

                                                                           
                                                                            
                                                                           
                                                   
    localparam ZOOM_FIFO_AW = 9;
    localparam ZOOM_FIFO_DEPTH = (1 << ZOOM_FIFO_AW);
    reg [ZOOM_FIFO_AW-1:0] zoom_wr_ptr;
    reg [ZOOM_FIFO_AW-1:0] zoom_rd_ptr;
    reg [ZOOM_FIFO_AW:0] zoom_count;
    reg [ZOOM_FIFO_AW-1:0] zoom_prefetch_addr;
    reg [1:0] zoom_phase;
                                                                  
                                                                       
    wire frame_start = (h == 11'd0 && v == 10'd0);
    wire [9:0] waveform_y;
    wire waveform_valid;
    wire [10:0] waveform_x=(h-11'd218)-11'd128;
    audio_waveform waveform(.pclk(pclk),.reset_n(reset_n),.pcm(audio_pcm),
      .sample_toggle(audio_sample_toggle),.flush_toggle(audio_flush_toggle),
      .frame_tick(frame_start),.read_index(waveform_x[9:1]),
      .sample_y(waveform_y),.sample_valid(waveform_valid));
    wire zoom_request = (zoom_mode == 2'd1);
                                                                            
                                                                             
    wire zoom_frame = frame_start ? zoom_request : zoom_active;

    wire active = (h >= 11'd220 && h < 11'd1500 &&
                   v >= 10'd25 && v < 10'd825);
    wire invalid = fatal || underrun || !started;
    wire [10:0] x = h - 11'd220;
    wire [9:0]  y = v - 10'd25;
                                                                        
                                                                            
                                                                             
    wire line_prefetch = (h == 11'd219) && (v >= 10'd25 && v < 10'd825);
    wire capture_window = line_prefetch || (active && h < 11'd1499);
                                                                           
                                                                           
                                                                      
                                                                      
                                                                 
    wire [10:0] capture_x = line_prefetch ? 11'd0 : (x + 11'd1);
                                                                          
                                                                             
                                     
    wire [1:0] zoom_step = line_prefetch ? 2'd2 :
                           ((x < 11'd160 || x >= 11'd1120) ? 2'd2 :
                            (zoom_phase == 2'd0 ? 2'd0 : 2'd1));
                                                                           
                                                                            
                               
    reg [1:0] zoom_next_step;
    always @* begin
        if (line_prefetch || x < 11'd159 || x >= 11'd1119)
            zoom_next_step = 2'd2;
        else if (x == 11'd159)
            zoom_next_step = 2'd0;
        else begin
            case (zoom_phase)
                2'd0: zoom_next_step = 2'd1;
                2'd1: zoom_next_step = 2'd1;
                default: zoom_next_step = 2'd0;
            endcase
        end
    end
    wire zoom_can_pop = (zoom_count >= {{ZOOM_FIFO_AW-1{1'b0}},zoom_step});
                                                                            
                                                                              
                                                                             
                                                                       
    wire zoom_output_valid = active && started && !fatal && !underrun &&
                             (zoom_count != 0) && zoom_can_pop;
    wire zoom_capture_valid = capture_window && started && !fatal && !underrun &&
                              (zoom_count != 0) &&
                              (line_prefetch || zoom_can_pop);
                                                                             
                                                                            
                                                                          
                                            
    wire zoom_prefetch_window = (v <= 10'd824) && !frame_start;
    wire zoom_ready = zoom_frame && enable && !fatal && !underrun &&
                      zoom_prefetch_window && (zoom_count < ZOOM_FIFO_DEPTH);
    wire direct_ready = capture_window && started && !fatal && !underrun;
    assign pixel_ready = zoom_frame ? zoom_ready : direct_ready;
    wire zoom_push = zoom_frame && pixel_valid && pixel_ready;
    wire [31:0] zoom_head_data;
                                                                           
                                                                          
                                                                           
                      
    wire [ZOOM_FIFO_AW-1:0] zoom_mem_raddr =
        (h == 11'd218 && v >= 10'd25 && v <= 10'd824) ? zoom_rd_ptr :
        line_prefetch ? (zoom_rd_ptr + {{(ZOOM_FIFO_AW-2){1'b0}},2'd2}) :
        active ? (zoom_prefetch_addr + zoom_next_step) : zoom_rd_ptr;
    eg_dual_clock_mem #(.WIDTH(32),.AW(ZOOM_FIFO_AW),.IMPLEMENT("9K"))
    zoom_mem(
        .wclk(pclk),.wrst(!reset_n),.we(zoom_push),.waddr(zoom_wr_ptr),
        .wdata(pixel_data),.rclk(pclk),.rrst(!reset_n),.re(1'b1),
        .raddr(zoom_mem_raddr),.rdata(zoom_head_data));

    function [7:0] adjust_channel;
        input [7:0] value;
        input [7:0] br;
        input [7:0] ct;
        reg signed [10:0] delta;
        reg signed [10:0] scaled_delta;
        reg signed [10:0] result;
        begin
                                                                           
                                                                          
                                                                         
                                                                            
            delta = $signed({1'b0,value}) - 11'sd128;
            case (ct[7:6])
                2'b00: scaled_delta = delta >>> 2;                    
                2'b01: scaled_delta = delta >>> 1;                      
                2'b10: scaled_delta = (ct == 8'd128) ? delta :
                                      delta + (delta >>> 2);            
                default: scaled_delta = delta + (delta >>> 1);            
            endcase
            result = scaled_delta + $signed({1'b0,br});
            if (result < 0)
                adjust_channel = 8'd0;
            else if (result > 11'sd255)
                adjust_channel = 8'd255;
            else
                adjust_channel = result[7:0];
        end
    endfunction

    function [23:0] adjust_color;
        input [23:0] value;
        input [7:0] br;
        input [7:0] ct;
        begin
            adjust_color = {adjust_channel(value[23:16],br,ct),
                            adjust_channel(value[15:8],br,ct),
                            adjust_channel(value[7:0],br,ct)};
        end
    endfunction

    function [7:0] fade_channel;
        input [7:0] value;
        input [2:0] alpha;
        begin
                                                                        
                                                                           
                                                                            
                     
            case (alpha)
                3'b000: fade_channel = 8'd0;
                3'b001: fade_channel = value >> 3;
                3'b010: fade_channel = value >> 2;
                3'b011: fade_channel = (value >> 2) + (value >> 3);
                3'b100: fade_channel = value >> 1;
                3'b101: fade_channel = (value >> 1) + (value >> 3);
                3'b110: fade_channel = value - (value >> 2);
                default: fade_channel = value;
            endcase
        end
    endfunction

    function [23:0] fade_color;
        input [23:0] value;
        input [2:0] alpha;
        begin
            fade_color = {fade_channel(value[23:16],alpha),
                          fade_channel(value[15:8],alpha),
                          fade_channel(value[7:0],alpha)};
        end
    endfunction

    function [23:0] half_blend;
        input [23:0] a;
        input [23:0] b;
        begin
            half_blend = {(a[23:16] >> 1) + (b[23:16] >> 1),
                          (a[15:8]  >> 1) + (b[15:8]  >> 1),
                          (a[7:0]   >> 1) + (b[7:0]   >> 1)};
        end
    endfunction

                                                                          
                                                                          
    wire [7:0] font_code,osd_code,panel_code;
    wire [3:0] font_row,font_col,osd_row,osd_col,panel_row,panel_col;
    wire font_region,osd_region,lyric_active,panel_region;
    wire panel_backdrop,panel_highlight,panel_bar,panel_fill,panel_cursor;
    reg [1:0] render_page;
    reg render_overlay,render_subtitle,render_wave;
    reg [7:0] render_brightness,render_contrast;
    reg [1:0] render_transition,render_media;
    always @(posedge pclk)begin
        if(!reset_n)begin
            render_page<=0;render_overlay<=0;render_subtitle<=0;render_wave<=0;
            render_brightness<=128;render_contrast<=128;render_transition<=0;render_media<=0;
        end
        else if(frame_start)begin
            render_page<=ui_page;render_overlay<=overlay_enable;
            render_subtitle<=subtitle_enable;render_wave<=waveform_enable;
            render_brightness<=brightness;render_contrast<=contrast;render_transition<=transition_mode;render_media<=media_select;
        end
    end
    wire visible_overlay=PLAYER_UI?render_overlay:overlay_enable;
    wire visible_subtitle=PLAYER_UI?(render_overlay && render_page==0 && render_subtitle):subtitle_enable;
    wire visible_wave=PLAYER_UI?(render_overlay && render_page==0 && render_wave):waveform_enable;
                                                                          
                                                                        
                                                                           
                                                                             
                                                                           
                                                                           
                                                                             
    (* keep = "true" *) reg [10:0] font_lookup_x;                 
                                                                           
                                                                          
                                                                            
    (* keep = "true" *) reg [9:0] font_lookup_y;                 
    always @(posedge pclk) begin
        if(!reset_n || h==11'd1649) font_lookup_x<=11'd1830;
        else font_lookup_x<=h-11'd217;
        if(!reset_n) font_lookup_y<=10'd999;
        else if(h==11'd1649)
            font_lookup_y<=(v==10'd829)?10'd999:(v-10'd24);
    end
    ui_osd_layout #(.FRAME_CONTROLS(PLAYER_UI)) osd(.pclk(pclk),.reset_n(reset_n),.frame_tick(frame_start),
      .x(font_lookup_x),.y(font_lookup_y),.invalid(invalid),.paused(paused),
      .media_select(media_select),.media_index(media_index),.brightness(brightness),.contrast(contrast),
      .waveform_enable(waveform_enable),.subtitle_enable(subtitle_enable),.overlay_enable(overlay_enable),
      .zoom_mode(zoom_mode),.transition_mode(transition_mode),
      .volume(volume),.muted(muted),
      .lyric_text(lyric_text),.lyric_valid(lyric_valid),.lyric_toggle(lyric_toggle),
      .code(osd_code),.row(osd_row),.col(osd_col),.region(osd_region),.lyric_active(lyric_active));
    ui_player_panel panel(.pclk(pclk),.reset_n(reset_n),.frame_tick(frame_start),
      .x(font_lookup_x),.y(font_lookup_y),.visible(PLAYER_UI && overlay_enable),.page(ui_page),
      .media(media_select),.item(media_index),.cursor(browser_cursor),.video_count(video_count),
      .image_count(image_count),.library_count(library_count),.play_time(play_time),.total_time(total_time),
      .target_time(target_time),.progress(progress_mark),.seek_step(seek_step),
      .volume(volume),.muted(muted),
      .library_ready(library_ready),.has_opened(has_opened),.media_error(media_error),
      .name_code(name_code),.name_id(name_id),.name_char(name_char),
      .code(panel_code),.row(panel_row),.col(panel_col),.text_region(panel_region),
      .backdrop(panel_backdrop),.highlight(panel_highlight),.bar_background(panel_bar),
      .bar_fill(panel_fill),.bar_cursor(panel_cursor));
    wire fault_font_region=invalid && font_lookup_x>=528 && font_lookup_x<752 && font_lookup_y>=360 && font_lookup_y<392;
    wire visible_osd_region=osd_region && (!PLAYER_UI || fault_font_region ||
                            (font_lookup_y<84?visible_overlay:visible_subtitle));
    wire [9:0] display_wave_y=PLAYER_UI?(waveform_y-((render_media==2)?10'd360:10'd144)):waveform_y;
    wire [9:0] subtitle_y0=PLAYER_UI?((render_media==2)?10'd496:10'd584):10'd704;
    wire [9:0] subtitle_y1=PLAYER_UI?((render_media==2)?10'd536:10'd624):10'd744;
    wire select_panel=panel_region && !fault_font_region;
    assign font_code=select_panel?panel_code:osd_code;
    assign font_row=select_panel?panel_row:osd_row;
    assign font_col=select_panel?panel_col:osd_col;
    assign font_region=panel_region || visible_osd_region;
    reg [4:0] panel_flags_q,panel_flags_qq,pipe_panel_flags;
`ifdef __ICARUS__
                                                                              
                                                                       
    wire [15:0] font_bits;
    ui_font_zh font(.code(font_code),.row(font_row),.bits(font_bits));
    wire font_on=font_region && font_bits[15-font_col];
`endif
    reg [7:0] font_code_q;
    reg [3:0] font_row_q,font_col_q,font_col_qq;
    reg font_valid_q,font_valid_qq;
    wire [15:0] font_bits_q;
    ui_font_zh_sync font_q(.clk(pclk),.code(font_code_q),.row(font_row_q),.bits(font_bits_q));
    wire font_on_pipelined=font_valid_qq && font_bits_q[15-font_col_qq];

                                                                            
                                                                           
                                                                            
                                                         
    reg [23:0] source_stage_color;
    reg [10:0] source_stage_x;
    reg [9:0]  source_stage_y;
    reg        source_stage_active;
    reg        source_stage_valid;
    reg        source_stage_invalid;
    reg        source_stage_overlay_enable;
    reg        source_stage_subtitle_enable;
    reg        source_stage_lyric_active;
    reg        source_stage_waveform_enable;
    reg [1:0]  source_stage_zoom_mode;
    reg [1:0]  source_stage_transition_mode;
    reg [7:0]  source_stage_brightness;
    reg [7:0]  source_stage_contrast;
                                                                         
                                                                        
    reg [2:0]  source_stage_transition_alpha;
    reg [10:0] source_stage_wipe_limit;
    reg [10:0] source_stage_slide_offset;
                                                                       
    reg [10:0] source_stage_audio_level;
    reg [23:0] pipe_color;
    wire [23:0] adjusted_color;
    wire [3:0] contrast_coefficient = source_stage_contrast[7:6]==0 ? 4'd1 :
                                     source_stage_contrast[7:6]==1 ? 4'd2 :
                                     source_stage_contrast[7:6]==3 ? 4'd6 :
                                     source_stage_contrast==128 ? 4'd4 : 4'd5;
    genvar channel;
    generate for(channel=0;channel<3;channel=channel+1)begin: contrast_dsp
        wire signed [7:0] centered={~source_stage_color[channel*8+7],source_stage_color[channel*8+:7]};
        wire signed [11:0] product;
`ifdef __ICARUS__
        assign product=centered*$signed(contrast_coefficient);
`else
        EG_LOGIC_MULT #(.INPUT_WIDTH_A(8),.INPUT_WIDTH_B(4),.OUTPUT_WIDTH(12),
            .INPUTFORMAT("SIGNED"),.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
            .OUTPUTREG("DISABLE"),.IMPLEMENT("AUTO")) multiplier(
            .a(centered),.b(contrast_coefficient),.p(product),.clk(pclk),
            .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.rstan(reset_n),.rstbn(reset_n),.rstpdn(reset_n));
`endif
        wire signed [9:0] result=$signed(product[11:2])+$signed({2'b00,source_stage_brightness});
        assign adjusted_color[channel*8+:8] = result[9] ? 8'd0 :
                                                result > 10'sd255 ? 8'd255 : result[7:0];
    end endgenerate
    reg [10:0] pipe_x;
    reg [9:0]  pipe_y;
    reg        pipe_active;
    reg        pipe_invalid;
    reg        pipe_font_on;
    reg        pipe_overlay_enable;
    reg        pipe_subtitle_enable;
    reg        pipe_lyric_active;
    reg        pipe_waveform_enable;
    reg [1:0]  pipe_zoom_mode;
    reg [1:0]  pipe_transition_mode;
    reg [2:0]  pipe_transition_alpha;
    reg [10:0] pipe_wipe_limit;
    reg [10:0] pipe_slide_offset;
    reg [10:0] pipe_audio_level;
    wire pipe_wave_band = pipe_waveform_enable && pipe_active &&
                          pipe_x >= 11'd128 && pipe_x < 11'd1152 &&
                          pipe_audio_level[10] &&
                          pipe_y+1'b1 >= pipe_audio_level[9:0] &&
                          pipe_y <= pipe_audio_level[9:0]+1'b1;
    reg [23:0] color_next;
                                                                            
                                                                             
                                                                      
    wire [31:0] zoom_stage_data = zoom_head_data;
    wire zoom_stage_valid = line_prefetch ?
                             (zoom_count != 0) :
                             (zoom_count > zoom_step);
    wire [23:0] source_color = zoom_active ? zoom_stage_data[23:0] : pixel_data[23:0];
    wire source_valid = zoom_active ?
                        (zoom_capture_valid && zoom_stage_valid) : pixel_valid;
    wire source_capture_valid = capture_window && source_valid;
    always @* begin
        color_next = pipe_color;
        if (pipe_invalid) begin
            color_next = ((pipe_x[5] ^ pipe_y[5]) == 1'b0) ? 24'h570057 : 24'hff0033;
            if (pipe_font_on) color_next = 24'hffff00;
        end else begin
                                                                             
                                                                              
            if (pipe_transition_mode == 2'd1)
                color_next = fade_color(color_next,pipe_transition_alpha);
            else if (pipe_transition_mode == 2'd2 && pipe_x > pipe_wipe_limit)
                color_next = 24'h000000;
            else if (pipe_transition_mode == 2'd3 && pipe_x < pipe_slide_offset)
                color_next = 24'h000000;
                                                              
            if (pipe_overlay_enable && pipe_y < 10'd84)
                color_next = half_blend(color_next,24'h103060);
            if (pipe_wave_band)
                color_next = 24'h00ffff;
            if (pipe_subtitle_enable && ((pipe_y >= subtitle_y1 && pipe_y < subtitle_y1+32) ||
                (pipe_lyric_active && pipe_y >= subtitle_y0 && pipe_y < subtitle_y0+32)))
                color_next = half_blend(color_next,24'h602000);
            if (pipe_font_on)
                color_next = 24'hffffff;
        end
        if(PLAYER_UI)begin
            if(pipe_panel_flags[4])color_next=half_blend(color_next,24'h081828);
            if(pipe_panel_flags[3])color_next=24'h164d73;
            if(pipe_panel_flags[2])color_next=24'h384a5a;
            if(pipe_panel_flags[1])color_next=24'h29c5c9;
            if(pipe_panel_flags[0])color_next=24'hffdd66;
            if(pipe_font_on)color_next=24'hffffff;
        end
    end

                                                                           
                                                                              
                                                                             
                                               
    always @* begin
        if (de && pipe_active)
            rgb = color_next;
        else
            rgb = 24'h000000;
    end

    always @(posedge pclk) begin
            if (!reset_n) begin
            h <= 0;
            v <= 0;
            started <= 0;
            zoom_active <= 0;
            zoom_wr_ptr <= 0;
            zoom_rd_ptr <= 0;
            zoom_count <= 0;
            zoom_prefetch_addr <= 0;
            zoom_phase <= 0;
            underrun <= 0;
            transition_alpha <= 0;
            wipe_limit <= 0;
            slide_offset <= 11'd1280;
            commit_seen<=0;transition_previous<=0;
            source_stage_color <= 0;
            source_stage_x <= 0;
            source_stage_y <= 0;
            source_stage_active <= 0;
            source_stage_valid <= 0;
            source_stage_invalid <= 1;
            source_stage_overlay_enable <= 0;
            source_stage_subtitle_enable <= 0;
            source_stage_lyric_active <= 0;
            source_stage_waveform_enable <= 0;
            source_stage_zoom_mode <= 0;
            source_stage_transition_mode <= 0;
            source_stage_brightness <= 8'd128;
            source_stage_contrast <= 8'd128;
            source_stage_transition_alpha <= 0;
            source_stage_wipe_limit <= 0;
            source_stage_slide_offset <= 0;
            source_stage_audio_level <= 0;
            font_code_q <= 0;
            font_row_q <= 0;
            font_col_q <= 0;
            font_valid_q <= 0;
            font_col_qq <= 0;
            font_valid_qq <= 0;
            panel_flags_q<=0;panel_flags_qq<=0;pipe_panel_flags<=0;
            pipe_color <= 0;
            pipe_x <= 0;
            pipe_y <= 0;
            pipe_active <= 0;
            pipe_invalid <= 1;
            pipe_font_on <= 0;
            pipe_overlay_enable <= 0;
            pipe_subtitle_enable <= 0;
            pipe_lyric_active <= 0;
            pipe_waveform_enable <= 0;
            pipe_zoom_mode <= 0;
            pipe_transition_mode <= 0;
            pipe_transition_alpha <= 0;
            pipe_wipe_limit <= 0;
            pipe_slide_offset <= 0;
            pipe_audio_level <= 0;
            de <= 0;
            hs <= 0;
            vs <= 0;
        end else begin
                                                                           
                                                                       
                                                                            
                                                                             
                                                        
            h <= h;
            v <= v;
            started <= started;
            zoom_active <= zoom_active;
            zoom_wr_ptr <= zoom_wr_ptr;
            zoom_rd_ptr <= zoom_rd_ptr;
            zoom_count <= zoom_count;
            zoom_prefetch_addr <= zoom_prefetch_addr;
            zoom_phase <= zoom_phase;
            underrun <= underrun;
            transition_alpha <= transition_alpha;
            wipe_limit <= wipe_limit;
            slide_offset <= slide_offset;
            source_stage_color <= source_stage_color;
            source_stage_x <= source_stage_x;
            source_stage_y <= source_stage_y;
            source_stage_active <= source_stage_active;
            source_stage_valid <= source_stage_valid;
            source_stage_invalid <= source_stage_invalid;
            source_stage_overlay_enable <= source_stage_overlay_enable;
            source_stage_subtitle_enable <= source_stage_subtitle_enable;
            source_stage_waveform_enable <= source_stage_waveform_enable;
            source_stage_zoom_mode <= source_stage_zoom_mode;
            source_stage_transition_mode <= source_stage_transition_mode;
            source_stage_brightness <= source_stage_brightness;
            source_stage_contrast <= source_stage_contrast;
            source_stage_transition_alpha <= source_stage_transition_alpha;
            source_stage_wipe_limit <= source_stage_wipe_limit;
            source_stage_slide_offset <= source_stage_slide_offset;
            source_stage_audio_level <= source_stage_audio_level;
            font_code_q <= font_code_q;
            font_row_q <= font_row_q;
            font_col_q <= font_col_q;
            font_valid_q <= font_valid_q;
            pipe_color <= pipe_color;
            pipe_x <= pipe_x;
            pipe_y <= pipe_y;
            pipe_active <= pipe_active;
            pipe_invalid <= pipe_invalid;
            pipe_font_on <= pipe_font_on;
            pipe_overlay_enable <= pipe_overlay_enable;
            pipe_subtitle_enable <= pipe_subtitle_enable;
            pipe_waveform_enable <= pipe_waveform_enable;
            pipe_zoom_mode <= pipe_zoom_mode;
            pipe_transition_mode <= pipe_transition_mode;
            pipe_transition_alpha <= pipe_transition_alpha;
            pipe_wipe_limit <= pipe_wipe_limit;
            pipe_slide_offset <= pipe_slide_offset;
            pipe_audio_level <= pipe_audio_level;
            de <= de;
            hs <= hs;
            vs <= vs;
            if (h == 11'd1649) begin
                h <= 0;
                if (v == 10'd829) v <= 0;
                else v <= v + 1'b1;
            end else h <= h + 1'b1;

            if (frame_start) begin
                zoom_active <= zoom_request;
                                                                       
                                                                           
                                                              
                zoom_wr_ptr <= 0;
                zoom_rd_ptr <= 0;
                zoom_count <= 0;
                zoom_prefetch_addr <= 0;
                zoom_phase <= 0;
                if (enable && pixel_level >= 14'd4096 && !fatal && !underrun)
                    started <= 1;
            end
            if (!zoom_active && direct_ready && !pixel_valid)
                underrun <= 1;
                                                                         
                                                                        
                                                                        
                                                                         
            if (zoom_active && active && started &&
                !fatal && !underrun && !zoom_output_valid)
                underrun <= 1;

                                                                          
                                                                         
                                                                          
                                                                             
                                                   
            if (zoom_active || (frame_start && zoom_request)) begin
                                                                          
                                                                        
                                                                     
                if (line_prefetch) begin
                                                                             
                                                                            
                    zoom_prefetch_addr <= zoom_rd_ptr + 9'd2;
                    zoom_phase <= 0;
                end else if (active) begin
                                                                        
                                                                         
                                                                 
                    zoom_prefetch_addr <= zoom_prefetch_addr + zoom_next_step;
                    if (x >= 11'd160 && x < 11'd1120) begin
                        case (zoom_phase)
                            2'd0: zoom_phase <= 2'd1;
                            2'd1: zoom_phase <= 2'd2;
                            default: zoom_phase <= 2'd0;
                        endcase
                    end else begin
                        zoom_phase <= 0;
                    end
                end
                if (zoom_push)
                    zoom_wr_ptr <= zoom_wr_ptr + 1'b1;
                if (started && !fatal && !underrun && zoom_output_valid)
                    zoom_rd_ptr <= zoom_rd_ptr + zoom_step;
                case ({zoom_push,
                       (started && !fatal && !underrun && zoom_output_valid)})
                    2'b10: zoom_count <= zoom_count + 1'b1;
                    2'b01: zoom_count <= zoom_count - zoom_step;
                    2'b11: zoom_count <= zoom_count + 1'b1 - zoom_step;
                    default: begin end
                endcase
            end

            if (frame_start) begin
                                                                            
                                                                            
                                                                         
                                                                    
                if(commit_seen!=(frame_commit_toggle===1'b1) || transition_previous!=transition_mode)begin
                    commit_seen<=(frame_commit_toggle===1'b1);transition_previous<=transition_mode;
                    transition_alpha<=(transition_mode==1)?8'd0:8'hff;
                    wipe_limit<=(transition_mode==2)?11'd0:11'd1280;
                    slide_offset<=(transition_mode==3)?11'd1280:11'd0;
                end else if(!paused)case (transition_mode)
                    2'd0: begin
                        transition_alpha <= 8'hff;
                        wipe_limit <= 11'd1280;
                        slide_offset <= 0;
                    end
                    2'd1: begin
                        if (transition_alpha < 8'hf7) transition_alpha <= transition_alpha + 8'd8;
                        else transition_alpha <= 8'hff;
                        wipe_limit <= 11'd1280;
                        slide_offset <= 0;
                    end
                    2'd2: begin
                        transition_alpha <= 8'hff;
                        if (wipe_limit < 11'd1216) wipe_limit <= wipe_limit + 11'd64;
                        else wipe_limit <= 11'd1280;
                        slide_offset <= 0;
                    end
                    default: begin
                        transition_alpha <= 8'hff;
                        wipe_limit <= 11'd1280;
                        if (slide_offset > 11'd64) slide_offset <= slide_offset - 11'd64;
                        else slide_offset <= 0;
                    end
                endcase
            end

                                                                             
                                                                          
            source_stage_color <= source_color;
            source_stage_x <= capture_x;
            source_stage_y <= y;
            source_stage_active <= capture_window;
            source_stage_valid <= source_capture_valid;
            source_stage_invalid <= invalid || !source_capture_valid;
            source_stage_overlay_enable <= visible_overlay;
            source_stage_subtitle_enable <= visible_subtitle;
            source_stage_lyric_active <= lyric_active;
            source_stage_waveform_enable <= visible_wave;
            source_stage_zoom_mode <= zoom_mode;
            source_stage_transition_mode <= PLAYER_UI?render_transition:transition_mode;
            source_stage_brightness <= PLAYER_UI?render_brightness:brightness;
            source_stage_contrast <= PLAYER_UI?render_contrast:contrast;
            source_stage_transition_alpha <= transition_alpha[7:5];
            source_stage_wipe_limit <= wipe_limit;
            source_stage_slide_offset <= slide_offset;
            source_stage_audio_level <= {waveform_valid,display_wave_y};

            font_code_q <= font_code;
            font_row_q <= font_row;
            font_col_q <= font_col;
            font_col_qq <= font_col_q;
            font_valid_qq <= font_valid_q;
            panel_flags_q<={panel_backdrop,panel_highlight,panel_bar,panel_fill,panel_cursor};
            panel_flags_qq<=panel_flags_q;pipe_panel_flags<=panel_flags_qq;
                                                                     
                                                                          
                                                                            
            font_valid_q <= font_region;

                                                                           
                                                                             
                                
            pipe_color <= adjusted_color;
            pipe_x <= source_stage_x;
            pipe_y <= source_stage_y;
            pipe_active <= source_stage_active;
            pipe_invalid <= source_stage_invalid || !source_stage_valid;
            pipe_font_on <= font_on_pipelined;
            pipe_overlay_enable <= source_stage_overlay_enable;
            pipe_subtitle_enable <= source_stage_subtitle_enable;
            pipe_lyric_active <= source_stage_lyric_active;
            pipe_waveform_enable <= source_stage_waveform_enable;
            pipe_zoom_mode <= source_stage_zoom_mode;
            pipe_transition_mode <= source_stage_transition_mode;
            pipe_transition_alpha <= source_stage_transition_alpha;
            pipe_wipe_limit <= source_stage_wipe_limit;
            pipe_slide_offset <= source_stage_slide_offset;
            pipe_audio_level <= source_stage_audio_level;

            de <= active;
            hs <= (h >= 11'd1610);
            vs <= (v < 10'd5);
        end
    end
endmodule

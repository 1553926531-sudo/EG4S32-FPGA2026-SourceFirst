`timescale 1ns/1ps
                                                                   
module tf_native_media_reader (
    input  wire       clk50,
    output wire       uart_tx,
    input wire reset_n,
    input wire rd_req,
    input wire [31:0] rd_lba,
    output wire rd_accept,
    output wire [31:0] rd_data,
    output wire rd_valid,
    input wire rd_ready,
    output reg rd_done = 0,
    output reg rd_error = 0,
    output wire initialized,
    output wire fatal,
    output wire       sd_clk,
    inout  wire       sd_cmd,
    inout  wire [3:0] sd_dat
);

  localparam [5:0] P_POWERUP       = 6'd0;
  localparam [5:0] P_CMD0_START    = 6'd1;
  localparam [5:0] P_CMD0_WAIT     = 6'd2;
  localparam [5:0] P_CMD8_START    = 6'd3;
  localparam [5:0] P_CMD8_WAIT     = 6'd4;
  localparam [5:0] P_ACMD41_55     = 6'd5;
  localparam [5:0] P_ACMD41_55_W   = 6'd6;
  localparam [5:0] P_ACMD41_START  = 6'd7;
  localparam [5:0] P_ACMD41_WAIT   = 6'd8;
  localparam [5:0] P_CMD2_START    = 6'd9;
  localparam [5:0] P_CMD2_WAIT     = 6'd10;
  localparam [5:0] P_CMD3_START    = 6'd11;
  localparam [5:0] P_CMD3_WAIT     = 6'd12;
  localparam [5:0] P_CMD7_START    = 6'd13;
  localparam [5:0] P_CMD7_WAIT     = 6'd14;
  localparam [5:0] P_SELECT_BUSY   = 6'd15;
  localparam [5:0] P_WIDTH_55      = 6'd16;
  localparam [5:0] P_WIDTH_55_W    = 6'd17;
  localparam [5:0] P_WIDTH_START   = 6'd18;
  localparam [5:0] P_WIDTH_WAIT    = 6'd19;
  localparam [5:0] P_READ_START    = 6'd20;
  localparam [5:0] P_READ_WAIT     = 6'd21;
  localparam [5:0] P_DATA_TOKEN    = 6'd22;
  localparam [5:0] P_DATA_BITS     = 6'd23;
  localparam [5:0] P_DATA_CRC      = 6'd24;
  localparam [5:0] P_DATA_END      = 6'd25;
  localparam [5:0] P_READY         = 6'd26;
  localparam [5:0] P_FAIL          = 6'd27;
  localparam [5:0] P_HALT          = 6'd28;
  localparam [5:0] P_CMD0_GAP      = 6'd29;
  localparam [5:0] P_CMD8_GAP      = 6'd30;
  localparam [5:0] P_ACMD41_GAP    = 6'd31;
  localparam [5:0] P_ACMD41_RETRY_GAP = 6'd32;
  localparam [5:0] P_INTERCMD_GAP = 6'd33;
  localparam [5:0] P_MULTI_DRAIN = 6'd44;
  localparam [5:0] P_MULTI_STOP_START = 6'd45;
  localparam [5:0] P_MULTI_STOP_WAIT = 6'd46;
  localparam [5:0] P_MULTI_STOP_BUSY = 6'd47;
  localparam [5:0] P_IO_READ_ERROR = 6'd48;
  localparam [5:0] P_MULTI_STOP_ACK = 6'd49;
  localparam [5:0] P_STATUS_START = 6'd50;
  localparam [5:0] P_STATUS_WAIT = 6'd51;
  localparam [5:0] P_CMD9_START = 6'd52;
  localparam [5:0] P_CMD9_WAIT = 6'd53;

  localparam [5:0] P_DMA = 6'd55;
  reg [6:0] dma_word = 0;
  localparam [2:0] C_IDLE = 3'd0;
  localparam [2:0] C_PREP = 3'd1;
  localparam [2:0] C_SEND = 3'd2;
  localparam [2:0] C_WAIT = 3'd3;
  localparam [2:0] C_RECV = 3'd4;

  localparam [3:0] MSG_START        = 4'd1;
  localparam [3:0] MSG_INIT_OK      = 4'd2;
  localparam [3:0] MSG_WIDTH_OK     = 4'd3;
  localparam [3:0] MSG_CMD_TIMEOUT  = 4'd4;
  localparam [3:0] MSG_CMD_REJECT   = 4'd5;
  localparam [3:0] MSG_CRC_FAIL     = 4'd6;
  localparam [3:0] MSG_NO_EXFAT     = 4'd7;
  localparam [3:0] MSG_DATA_TIMEOUT = 4'd8;
  localparam [3:0] MSG_EXFAT_OK     = 4'd9;
  localparam [3:0] MSG_MBR_FOUND    = 4'd10;
  localparam [3:0] MSG_CMD8_OK       = 4'd11;

  reg [5:0] phase = P_POWERUP;
  reg soft_reinitialize = 1'b0;
  reg [16:0] startup_count = 17'd0;
  wire boot_ready = (startup_count == 17'd100000);
  reg [7:0] div_count = 8'd0;
  reg [7:0] half_period = 8'd249;
  reg slow_sd_clk = 1'b0;
  reg slow_rise_pulse = 1'b0;
  reg hs_active = 1'b0;
  reg hs_sample_valid = 1'b0;
  reg cmd_sample_fast = 1'b1;
  reg [3:0] dat_sample_fast = 4'hf;
                                                                              
                                                                             
                                                                            
  wire hs_run = boot_ready && !soft_reinitialize && phase != P_MULTI_DRAIN;
  assign sd_clk = hs_active ? (~clk50 && hs_run) : slow_sd_clk;
  wire sd_rise_pulse = hs_active ? hs_sample_valid : slow_rise_pulse;
  wire sd_fall_pulse = hs_active ? (boot_ready && hs_run) :
                      (boot_ready && slow_sd_clk && div_count >= half_period);

  reg cmd_drive = 1'b0;
  reg cmd_out = 1'b1;
  reg cmd_sample = 1'b1;
  wire cmd_in = hs_active ? cmd_sample_fast : cmd_sample;
  reg dat_drive = 1'b0;
  reg [3:0] dat_out = 4'hf;
  reg [3:0] dat_sample = 4'hf;
  wire [3:0] dat_in = hs_active ? dat_sample_fast : dat_sample;
  assign sd_cmd = cmd_drive ? cmd_out : 1'bz;
                                                          
  assign sd_dat = 4'bzzzz;

  reg [10:0] powerup_clocks = 11'd0;
  reg [19:0] acmd41_tries = 20'd0;
  reg [19:0] wait_counter = 20'd0;
                                                                          
                                                                       
  localparam [31:0] CARD_WAIT_SYS_CYCLES = 32'd50000000;                
  reg [31:0] card_wait_cycles = 32'd0;
  reg [31:0] last_write_busy_cycles = 32'd0;
  reg [31:0] max_write_busy_cycles = 32'd0;
  reg [31:0] count_write_busy_timeout = 32'd0;
  reg [5:0] intercmd_next_phase = P_POWERUP;
  reg [15:0] rca = 16'd0;
  reg high_capacity = 1'b0;
  reg bus_4bit = 1'b0;
  reg [31:0] read_lba = 32'd0;
  reg read_attempt = 1'b0;
  reg [31:0] partition_lba = 32'd0;
  reg [23:0] sector_pack = 0;
  wire [31:0] sector_word;
  reg [3:0] read_high_nibble = 4'd0;
  reg io_transaction = 1'b0;
  reg io_is_write = 1'b0;
  reg io_is_debug = 1'b0;
  reg io_is_multi = 1'b0;
  reg io_is_clock = 1'b0;
  reg io_is_status = 1'b0;
  reg io_is_switch = 1'b0;
  reg [127:0] card_cid = 128'd0;
  reg [127:0] card_csd = 128'd0;
  reg [9:0] io_payload_bytes = 10'd512;
  wire [5:0] expected_read_command = io_is_switch ? 6'd6 : (io_is_multi ? 6'd18 : 6'd17);
  reg [15:0] multi_remaining = 16'd0;
  reg multi_count_high = 1'b0;
  reg [31:0] count_cmd17 = 32'd0;
  reg [31:0] count_cmd24 = 32'd0;
  reg [31:0] count_cmd18 = 32'd0;
  reg [31:0] count_cmd12 = 32'd0;
  reg [31:0] count_read_ok = 32'd0;
  reg [31:0] count_write_ok = 32'd0;
  reg [31:0] count_data_crc_error = 32'd0;
  reg [47:0] last_command_response = 48'd0;
  reg [31:0] last_command_info = 32'd0;
  reg [63:0] read_wait_tail = 64'd0;
  reg [63:0] last_read_wait_tail = 64'd0;
  reg [31:0] last_read_token_wait = 32'd0;
  reg [7:0] early_token_count = 8'd0;
  reg read_response_bad = 1'b0;
  reg [3:0] last_data_end = 4'hf;
  reg [31:0] io_lba = 32'd0;
  reg [7:0] io_status = 8'd0;
  reg [31:0] io_crc32 = 32'hffffffff;
  reg [31:0] io_crc_rx = 32'd0;
  reg [31:0] io_response_crc = 32'd0;
  reg [2:0] io_rx_state = 3'd0;
  reg [2:0] io_lba_byte_count = 3'd0;
  reg [9:0] io_data_index = 10'd0;
  reg [2:0] io_crc_rx_count = 3'd0;
  reg io_tx_active = 1'b0;
  reg io_tx_is_read = 1'b0;
  reg [9:0] io_tx_index = 10'd0;
  reg [1:0] io_tx_state = 2'd0;
  reg [2:0] write_response_count = 3'd0;
  reg [4:0] write_response_shift = 5'd0;
  reg write_busy_seen = 1'b0;
  reg [10:0] data_nibble_count = 11'd0;
  reg [4:0] data_crc_count = 5'd0;
  reg [15:0] calc_crc0 = 16'd0;
  reg [15:0] calc_crc1 = 16'd0;
  reg [15:0] calc_crc2 = 16'd0;
  reg [15:0] calc_crc3 = 16'd0;
  reg [15:0] card_crc0 = 16'd0;
  reg [15:0] card_crc1 = 16'd0;
  reg [15:0] card_crc2 = 16'd0;
  reg [15:0] card_crc3 = 16'd0;
                                                                      
                                                                             
                                                                     
  reg [63:0] boot_magic_shift = 64'd0;
  reg [31:0] partition_lba_shift = 32'd0;
  reg [15:0] sector_signature_shift = 16'd0;
  reg [3:0] failure_code = MSG_CMD_REJECT;
  reg startup_reported = 1'b0;

  reg [2:0] cmd_state = C_IDLE;
  reg [5:0] cmd_index = 6'd0;
  reg [31:0] cmd_argument = 32'd0;
  reg [7:0] cmd_response_bits = 8'd0;
  reg cmd_launch = 1'b0;
  reg cmd_done = 1'b0;
  reg cmd_error = 1'b0;
  reg [47:0] cmd_frame = 48'd0;
  reg [47:0] cmd_observed_shift = 48'd0;
  reg [5:0] cmd_loopback_mismatches = 6'd0;
  reg [7:0] cmd_bit_index = 8'd0;
  reg [7:0] response_count = 8'd0;
  reg [23:0] response_timeout = 24'd0;
  reg [135:0] response_shift = 136'd0;
  wire response_frame_bad = cmd_error || response_shift[47:46] != 2'b00 ||
      response_shift[7:1] != crc7(response_shift[47:8]) || !response_shift[0];

  reg [3:0] report_request = 4'd0;
  reg [3:0] report_code = 4'd0;
  reg [7:0] report_index = 8'd0;
  reg report_active = 1'b0;
  reg [1:0] report_tx_state = 2'd0;
  reg uart_start = 1'b0;
  reg [7:0] uart_data = 8'd0;
  wire uart_busy;
  wire [7:0] uart_rx_data = 0;
  wire uart_rx_valid = 0;
  reg [7:0] io_tx_byte;
  wire [8:0] debug_byte = io_tx_index - 10'd6;
  wire [6:0] sector_read_address = io_tx_active ? debug_byte[8:2] :
      phase != P_DMA ? 7'd0 :
      (rd_ready && dma_word != 127) ? dma_word + 7'd1 : dma_word;
  wire sector_write = phase == P_DATA_BITS && sd_rise_pulse &&
                      data_nibble_count[2:0] == 3'd7;
                                                                          
                                                                           
                                                                  
  eg_dual_clock_mem #(.WIDTH(32),.AW(7),.IMPLEMENT("9K")) sector_buffer(
      .wclk(clk50),.wrst(!reset_n),.we(sector_write),
      .waddr(data_nibble_count[9:3]),.wdata({read_high_nibble,dat_in,sector_pack}),
      .rclk(clk50),.rrst(!reset_n),.re(1'b1),
      .raddr(sector_read_address),.rdata(sector_word));
  always @(posedge clk50)begin
    if(!reset_n)sector_pack<=0;
    else if(phase == P_DATA_BITS && sd_rise_pulse && data_nibble_count[0])
      sector_pack<={read_high_nibble,dat_in,sector_pack[23:8]};
  end

  always @* begin
    io_tx_byte = 8'd0;
    case (io_tx_index)
      10'd0: io_tx_byte = 8'h5a;
      10'd1: io_tx_byte = io_status;
      10'd2: io_tx_byte = io_lba[31:24];
      10'd3: io_tx_byte = io_lba[23:16];
      10'd4: io_tx_byte = io_lba[15:8];
      10'd5: io_tx_byte = io_lba[7:0];

      default: begin
        if (io_tx_is_read) begin
          if (io_tx_index < io_payload_bytes + 10'd6)
            io_tx_byte = sector_word >> {debug_byte[1:0],3'b000};
          else if (io_tx_index == io_payload_bytes + 10'd6) io_tx_byte = io_response_crc[31:24];
          else if (io_tx_index == io_payload_bytes + 10'd7) io_tx_byte = io_response_crc[23:16];
          else if (io_tx_index == io_payload_bytes + 10'd8) io_tx_byte = io_response_crc[15:8];
          else if (io_tx_index == io_payload_bytes + 10'd9) io_tx_byte = io_response_crc[7:0];
        end
      end
    endcase
  end

  function [6:0] crc7;
    input [39:0] bits_in;
    integer i;
    reg [6:0] c;
    reg feedback;
    begin
      c = 7'd0;
      for (i = 39; i >= 0; i = i - 1) begin
        feedback = c[6] ^ bits_in[i];
        c = {c[5:0], 1'b0};
        if (feedback) c = c ^ 7'h09;
      end
      crc7 = c;
    end
  endfunction

  function [15:0] crc16_step;
    input [15:0] crc_in;
    input data_bit;
    reg feedback;
    reg [15:0] c;
    begin
      feedback = crc_in[15] ^ data_bit;
      c = {crc_in[14:0], 1'b0};
      if (feedback) c = c ^ 16'h1021;
      crc16_step = c;
    end
  endfunction

                                                                           
                                                                     
                                                                            
                                                                           
                                                                            
                                                 
  wire [15:0] crc0_next;
  wire [15:0] crc1_next;
  wire [15:0] crc2_next;
  wire [15:0] crc3_next;
  crc16_next_state crc0_next_state(.crc_in(calc_crc0), .data_bit(dat_in[0]), .crc_out(crc0_next));
  crc16_next_state crc1_next_state(.crc_in(calc_crc1), .data_bit(dat_in[1]), .crc_out(crc1_next));
  crc16_next_state crc2_next_state(.crc_in(calc_crc2), .data_bit(dat_in[2]), .crc_out(crc2_next));
  crc16_next_state crc3_next_state(.crc_in(calc_crc3), .data_bit(dat_in[3]), .crc_out(crc3_next));

  function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] byte_in;
    integer i;
    reg [31:0] c;
    begin
      c = crc_in ^ {24'd0, byte_in};
      for (i = 0; i < 8; i = i + 1) begin
        if (c[0]) c = (c >> 1) ^ 32'hedb88320;
        else c = c >> 1;
      end
      crc32_byte = c;
    end
  endfunction

  function [7:0] report_char;
    input [3:0] id;
    input [7:0] index;
    reg [8*24-1:0] message;
    reg [7:0] length;
    begin
      message = 0;
      length = 0;
      case (id)
        MSG_START: begin message = "TF DIAG START\r\n"; length = 15; end
        MSG_INIT_OK: begin message = "TF SD INIT OK\r\n"; length = 15; end
        MSG_WIDTH_OK: begin message = "TF SD 4BIT OK\r\n"; length = 15; end
        MSG_CMD_TIMEOUT: begin message = "TF SD CMD TIMEOUT\r\n"; length = 19; end
        MSG_CMD_REJECT: begin message = "TF SD CMD REJECT\r\n"; length = 18; end
        MSG_CRC_FAIL: begin message = "TF SD DATA CRC FAIL\r\n"; length = 21; end
        MSG_NO_EXFAT: begin message = "TF EXFAT NOT FOUND\r\n"; length = 20; end
        MSG_DATA_TIMEOUT: begin message = "TF SD DATA TIMEOUT\r\n"; length = 20; end
        MSG_EXFAT_OK: begin message = "TF EXFAT IO READY\r\n"; length = 19; end
        MSG_MBR_FOUND: begin message = "TF MBR FOUND\r\n"; length = 14; end
        MSG_CMD8_OK: begin message = "TF CMD8 OK\r\n"; length = 12; end
        default: begin message = 0; length = 0; end
      endcase
      if (index < length)
        report_char = message[(length - 1 - index) * 8 +: 8];
      else
        report_char = 8'd0;
    end
  endfunction

                                                                        
                                                                            
                                                                          
  always @(negedge clk50) begin
    hs_sample_valid <= hs_active && hs_run;
    if (hs_active && hs_run) begin
      cmd_sample_fast <= sd_cmd;
      dat_sample_fast <= sd_dat;
    end
  end

  always @(posedge clk50) begin
    slow_rise_pulse <= 1'b0;
    if (!reset_n) begin
      startup_count <= 0; div_count <= 0; slow_sd_clk <= 0; hs_active <= 0;
    end else if (!boot_ready) begin
      if (startup_count < 17'd100000) startup_count <= startup_count + 1'b1;
      div_count <= 8'd0;
      slow_sd_clk <= 1'b0;
      hs_active <= 1'b0;
    end else if (hs_active) begin
                                                                           
                                                            
      slow_sd_clk <= 1'b0;
      div_count <= 8'd0;
      if (half_period != 8'hff) hs_active <= 1'b0;
    end else if (half_period == 8'hff && !slow_sd_clk) begin
      hs_active <= 1'b1;
      div_count <= 8'd0;
    end else if (phase == P_MULTI_DRAIN && !slow_sd_clk) begin
      div_count <= 8'd0;
    end else if (div_count >= half_period) begin
      div_count <= 8'd0;
      slow_sd_clk <= ~slow_sd_clk;
      if (!slow_sd_clk) begin
        cmd_sample <= sd_cmd;
        dat_sample <= sd_dat;
        slow_rise_pulse <= 1'b1;
      end
    end else begin
      div_count <= div_count + 1'b1;
    end
  end

  always @(posedge clk50) begin
    if (!reset_n || !boot_ready || soft_reinitialize) begin
      cmd_state <= C_IDLE;
      cmd_drive <= 1'b0;
      cmd_out <= 1'b1;
      cmd_done <= 1'b0;
      cmd_error <= 1'b0;
      response_shift <= 136'd0;
      response_count <= 8'd0;
      response_timeout <= 24'd0;
    end else begin
      cmd_done <= 1'b0;

      if (cmd_launch && cmd_state == C_IDLE) begin
        cmd_frame <= {1'b0, 1'b1, cmd_index, cmd_argument,
                      crc7({2'b01, cmd_index, cmd_argument}), 1'b1};
        cmd_observed_shift <= 48'd0;
        cmd_loopback_mismatches <= 6'd0;
        cmd_bit_index <= 8'd47;
        cmd_state <= C_PREP;
        cmd_error <= 1'b0;
        response_shift <= 136'd0;
        response_timeout <= 24'd0;
      end

      if (sd_fall_pulse) begin
        case (cmd_state)
          C_PREP: begin
            cmd_drive <= (rca != 16'd0) || ~cmd_frame[47];
            cmd_out <= (rca != 16'd0) ? cmd_frame[47] : 1'b0;
            cmd_bit_index <= 8'd47;
            cmd_state <= C_SEND;
          end
          C_SEND: begin
            if (cmd_bit_index == 0) begin
              cmd_drive <= 1'b0;
              response_count <= 8'd0;
              response_timeout <= 24'd0;
              if (cmd_response_bits == 0) begin
                cmd_state <= C_IDLE;
                cmd_done <= 1'b1;
              end else begin
                cmd_state <= C_WAIT;
              end
            end else begin
              cmd_bit_index <= cmd_bit_index - 1'b1;
              cmd_drive <= (rca != 16'd0) || ~cmd_frame[cmd_bit_index - 1'b1];
              cmd_out <= (rca != 16'd0) ? cmd_frame[cmd_bit_index - 1'b1] : 1'b0;
            end
          end
          default: begin end
        endcase
      end

      if (sd_rise_pulse) begin
        case (cmd_state)
          C_SEND: begin
            cmd_observed_shift <= {cmd_observed_shift[46:0], cmd_in};
            if (cmd_in != cmd_frame[cmd_bit_index] && cmd_loopback_mismatches != 6'd63)
              cmd_loopback_mismatches <= cmd_loopback_mismatches + 1'b1;
          end
          C_WAIT: begin
            if (!cmd_in) begin
              response_shift <= 136'd0;
              response_count <= 8'd1;
              response_timeout <= 24'd0;
              if (cmd_response_bits == 1) begin
                cmd_state <= C_IDLE;
                cmd_done <= 1'b1;
              end else begin
                cmd_state <= C_RECV;
              end
            end else if (response_timeout == 24'd10000) begin
              cmd_state <= C_IDLE;
              cmd_error <= 1'b1;
              cmd_done <= 1'b1;
            end else begin
              response_timeout <= response_timeout + 1'b1;
            end
          end
          C_RECV: begin
            response_shift <= {response_shift[134:0], cmd_in};
            if (response_count + 1'b1 >= cmd_response_bits) begin
              cmd_state <= C_IDLE;
              cmd_done <= 1'b1;
            end else begin
              response_count <= response_count + 1'b1;
            end
          end
          default: begin end
        endcase
      end
    end
  end

  always @(posedge clk50) begin
    if (!reset_n || !boot_ready || soft_reinitialize) begin
      rd_done <= 0; rd_error <= 0; dma_word <= 0;
      phase <= P_POWERUP;
      soft_reinitialize <= 1'b0;
      powerup_clocks <= 11'd0;
      acmd41_tries <= 20'd0;
      wait_counter <= 20'd0;
      card_wait_cycles <= 32'd0;
      last_write_busy_cycles <= 32'd0;
      max_write_busy_cycles <= 32'd0;
      count_write_busy_timeout <= 32'd0;
      intercmd_next_phase <= P_POWERUP;
      rca <= 16'd0;
      high_capacity <= 1'b0;
      bus_4bit <= 1'b0;
      half_period <= 8'd249;
      read_lba <= 32'd0;
      read_attempt <= 1'b0;
      partition_lba <= 32'd0;
      io_transaction <= 1'b0;
      io_is_write <= 1'b0;
      io_is_debug <= 1'b0;
      io_is_multi <= 1'b0;
      io_is_clock <= 1'b0;
      io_is_status <= 1'b0;
      io_is_switch <= 1'b0;
      card_cid <= 128'd0;
      card_csd <= 128'd0;
      io_payload_bytes <= 10'd512;
      multi_remaining <= 16'd0;
      multi_count_high <= 1'b0;
      count_cmd17 <= 32'd0;
      count_cmd24 <= 32'd0;
      count_cmd18 <= 32'd0;
      count_cmd12 <= 32'd0;
      count_read_ok <= 32'd0;
      count_write_ok <= 32'd0;
      count_data_crc_error <= 32'd0;
      last_command_response <= 48'd0;
      last_command_info <= 32'd0;
      read_wait_tail <= 64'd0;
      last_read_wait_tail <= 64'd0;
      last_read_token_wait <= 32'd0;
      early_token_count <= 8'd0;
      read_response_bad <= 1'b0;
      last_data_end <= 4'hf;
      io_lba <= 32'd0;
      io_status <= 8'd0;
      io_crc32 <= 32'hffffffff;
      io_crc_rx <= 32'd0;
      io_response_crc <= 32'd0;
      io_rx_state <= 3'd0;
      io_lba_byte_count <= 3'd0;
      io_data_index <= 10'd0;
      io_crc_rx_count <= 3'd0;
      io_tx_active <= 1'b0;
      io_tx_is_read <= 1'b0;
      io_tx_index <= 10'd0;
      io_tx_state <= 2'd0;
      read_high_nibble <= 4'd0;
      write_response_count <= 3'd0;
      write_response_shift <= 5'd0;
      write_busy_seen <= 1'b0;
      data_nibble_count <= 11'd0;
      data_crc_count <= 5'd0;
      calc_crc0 <= 16'd0;
      calc_crc1 <= 16'd0;
      calc_crc2 <= 16'd0;
      calc_crc3 <= 16'd0;
      card_crc0 <= 16'd0;
      card_crc1 <= 16'd0;
      card_crc2 <= 16'd0;
      card_crc3 <= 16'd0;
      dat_drive <= 1'b0;
      dat_out <= 4'hf;
      cmd_launch <= 1'b0;
      cmd_index <= 6'd0;
      cmd_argument <= 32'd0;
      cmd_response_bits <= 8'd0;
      failure_code <= MSG_CMD_REJECT;
      startup_reported <= 1'b0;
      report_request <= 4'd0;
      report_code <= 4'd0;
      report_index <= 8'd0;
      report_active <= 1'b0;
      report_tx_state <= 2'd0;
      uart_start <= 1'b0;
      uart_data <= 8'd0;
    end else begin
      rd_done <= 0; rd_error <= 0;
      cmd_launch <= 1'b0;
      uart_start <= 1'b0;

      if (phase == P_SELECT_BUSY || phase == P_DATA_TOKEN ||
          phase == P_MULTI_STOP_BUSY)
        card_wait_cycles <= card_wait_cycles + 1'b1;
      else card_wait_cycles <= 32'd0;

      if (cmd_done) begin
        last_command_response <= response_shift[47:0];
        last_command_info <= {13'd0, cmd_error, cmd_loopback_mismatches, 6'd0, cmd_index};
      end

      if (cmd_launch) begin
        case (cmd_index)
          6'd17: count_cmd17 <= count_cmd17 + 1'b1;
          6'd24: count_cmd24 <= count_cmd24 + 1'b1;
          6'd18: count_cmd18 <= count_cmd18 + 1'b1;
          6'd12: count_cmd12 <= count_cmd12 + 1'b1;
          default: begin end
        endcase
      end

      if (!startup_reported) begin
        report_request <= MSG_START;
        startup_reported <= 1'b1;
      end

      if (io_tx_active) begin
        case (io_tx_state)
          2'd0: begin
            if (!uart_busy) begin
              uart_data <= io_tx_byte;
              uart_start <= 1'b1;
              io_tx_state <= 2'd1;
            end
          end
          2'd1: begin
            if (uart_busy) io_tx_state <= 2'd2;
          end
          2'd2: begin
            if (!uart_busy) begin
              if (io_tx_index == (io_tx_is_read ? io_payload_bytes + 10'd9 : 10'd5)) begin
                io_tx_active <= 1'b0;
                io_tx_state <= 2'd0;
                io_rx_state <= 3'd0;
              end else begin
                io_tx_index <= io_tx_index + 1'b1;
                io_tx_state <= 2'd0;
              end
            end
          end
          default: io_tx_state <= 2'd0;
        endcase
      end else if (report_request != 0 && !report_active) begin
        report_code <= report_request;
        report_request <= 4'd0;
        report_index <= 8'd0;
        report_active <= 1'b1;
        report_tx_state <= 2'd0;
      end else if (report_active) begin
        case (report_tx_state)
          2'd0: begin
            if (!uart_busy) begin
              if (report_char(report_code, report_index) == 0) begin
                report_active <= 1'b0;
              end else begin
                uart_data <= report_char(report_code, report_index);
                uart_start <= 1'b1;
                report_tx_state <= 2'd1;
              end
            end
          end
          2'd1: begin
            if (uart_busy) report_tx_state <= 2'd2;
          end
          2'd2: begin
            if (!uart_busy) begin
              report_index <= report_index + 1'b1;
              report_tx_state <= 2'd0;
            end
          end
          default: report_tx_state <= 2'd0;
        endcase
      end

      if (phase == P_DATA_BITS && sd_rise_pulse) begin
        if (data_nibble_count[0]) begin
          if (io_transaction && !io_is_write)
            io_crc32 <= crc32_byte(io_crc32,
                {read_high_nibble, dat_in});
        end else read_high_nibble <= dat_in;
      end

      if (phase == P_READ_WAIT && sd_rise_pulse)
        read_wait_tail <= {read_wait_tail[59:0], dat_in};
                                                                             
                                                                             
      if (cmd_done && (phase == P_DATA_BITS || phase == P_DATA_CRC || phase == P_DATA_END))
        read_response_bad <= response_frame_bad || response_shift[45:40] != expected_read_command ||
                             response_shift[30] || response_shift[27];

      case (phase)
        P_POWERUP: begin
          if (sd_rise_pulse) begin
            if (powerup_clocks == 11'd1023) begin
              powerup_clocks <= 11'd0;
              phase <= P_CMD0_START;
            end else begin
              powerup_clocks <= powerup_clocks + 1'b1;
            end
          end
        end
        P_CMD0_START: begin
          cmd_index <= 6'd0;
          cmd_argument <= 32'd0;
          cmd_response_bits <= 8'd0;
          cmd_launch <= 1'b1;
          phase <= P_CMD0_WAIT;
        end
        P_CMD0_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else begin
              wait_counter <= 20'd0;
              phase <= P_CMD0_GAP;
            end
          end
        end
                                                                        
                                                                          
        P_CMD0_GAP: begin
          if (sd_rise_pulse) begin
            if (wait_counter == 20'd7) begin
              wait_counter <= 20'd0;
              phase <= P_CMD8_START;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_CMD8_START: begin
          cmd_index <= 6'd8;
          cmd_argument <= 32'h000001aa;
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_CMD8_WAIT;
        end
        P_CMD8_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd8 || response_shift[19:8] != 12'h1aa) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              acmd41_tries <= 20'd0;
              report_request <= MSG_CMD8_OK;
                                                                        
                                                          
              wait_counter <= 20'd0;
              phase <= P_CMD8_GAP;
            end
          end
        end
        P_CMD8_GAP: begin
          if (sd_rise_pulse) begin
            if (wait_counter == 20'd7) begin
              wait_counter <= 20'd0;
              phase <= P_ACMD41_55;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_ACMD41_55: begin
          cmd_index <= 6'd55;
          cmd_argument <= 32'd0;
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_ACMD41_55_W;
        end
        P_ACMD41_55_W: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd55 || response_shift[30] ||
                     response_shift[27] || !response_shift[13]) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              wait_counter <= 20'd0;
              phase <= P_ACMD41_GAP;
            end
          end
        end
        P_ACMD41_GAP: begin
          if (sd_rise_pulse) begin
            if (wait_counter == 20'd7) begin
              wait_counter <= 20'd0;
              phase <= P_ACMD41_START;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_ACMD41_START: begin
          cmd_index <= 6'd41;
                                                                      
          cmd_argument <= 32'h40ff8000;
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_ACMD41_WAIT;
        end
        P_ACMD41_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[39]) begin
              high_capacity <= response_shift[38];
              wait_counter <= 20'd0;
              intercmd_next_phase <= P_CMD2_START;
              phase <= P_INTERCMD_GAP;
            end else if (acmd41_tries == 20'd20000) begin
              failure_code <= MSG_CMD_TIMEOUT;
              phase <= P_FAIL;
            end else begin
              acmd41_tries <= acmd41_tries + 1'b1;
              wait_counter <= 20'd0;
              phase <= P_ACMD41_RETRY_GAP;
            end
          end
        end
        P_ACMD41_RETRY_GAP: begin
          if (sd_rise_pulse) begin
            if (wait_counter == 20'd7) begin
              wait_counter <= 20'd0;
              phase <= P_ACMD41_55;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_INTERCMD_GAP: begin
          if (sd_rise_pulse) begin
            if (wait_counter == 20'd7) begin
              wait_counter <= 20'd0;
              phase <= intercmd_next_phase;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_CMD2_START: begin
          cmd_index <= 6'd2;
          cmd_argument <= 32'd0;
          cmd_response_bits <= 8'd136;
          cmd_launch <= 1'b1;
          phase <= P_CMD2_WAIT;
        end
        P_CMD2_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else begin
              wait_counter <= 20'd0;
              card_cid <= response_shift[127:0];
              intercmd_next_phase <= P_CMD3_START;
              phase <= P_INTERCMD_GAP;
            end
          end
        end
        P_CMD3_START: begin
          cmd_index <= 6'd3;
          cmd_argument <= 32'd0;
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_CMD3_WAIT;
        end
        P_CMD3_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd3 || response_shift[39:24] == 0) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              rca <= response_shift[39:24];
              wait_counter <= 20'd0;
              intercmd_next_phase <= P_CMD9_START;
              phase <= P_INTERCMD_GAP;
            end
          end
        end
        P_CMD9_START: begin
          cmd_index <= 6'd9;
          cmd_argument <= {rca, 16'd0};
          cmd_response_bits <= 8'd136;
          cmd_launch <= 1'b1;
          phase <= P_CMD9_WAIT;
        end
        P_CMD9_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else begin
              card_csd <= response_shift[127:0];
              wait_counter <= 20'd0;
              intercmd_next_phase <= P_CMD7_START;
              phase <= P_INTERCMD_GAP;
            end
          end
        end
        P_CMD7_START: begin
          cmd_index <= 6'd7;
          cmd_argument <= {rca, 16'd0};
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_CMD7_WAIT;
        end
        P_CMD7_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd7 || response_shift[30] || response_shift[27]) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              wait_counter <= 20'd0;
              phase <= P_SELECT_BUSY;
            end
          end
        end
        P_SELECT_BUSY: begin
          if (sd_rise_pulse) begin
            if (dat_in[0]) begin
              wait_counter <= 20'd0;
              intercmd_next_phase <= P_WIDTH_55;
              phase <= P_INTERCMD_GAP;
            end
            else if (card_wait_cycles >= CARD_WAIT_SYS_CYCLES) begin
              failure_code <= MSG_DATA_TIMEOUT;
              phase <= P_FAIL;
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_WIDTH_55: begin
          cmd_index <= 6'd55;
          cmd_argument <= {rca, 16'd0};
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_WIDTH_55_W;
        end
        P_WIDTH_55_W: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd55 || response_shift[30] ||
                     response_shift[27] || !response_shift[13]) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              wait_counter <= 20'd0;
              intercmd_next_phase <= P_WIDTH_START;
              phase <= P_INTERCMD_GAP;
            end
          end
        end
        P_WIDTH_START: begin
          cmd_index <= 6'd6;
          cmd_argument <= 32'd2;
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_WIDTH_WAIT;
        end
        P_WIDTH_WAIT: begin
          if (cmd_done) begin
            if (cmd_error) begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            else if (response_shift[45:40] != 6'd6 || response_shift[30] || response_shift[27]) begin
              failure_code <= MSG_CMD_REJECT;
              phase <= P_FAIL;
            end else begin
              bus_4bit <= 1'b1;
                                                                        
                                                                            
              half_period <= 8'd24;
              report_request <= MSG_WIDTH_OK;
              wait_counter <= 20'd0;
              phase <= P_READY;
            end
          end
        end
        P_READ_START: begin
          read_wait_tail <= 64'hffffffffffffffff;
          read_response_bad <= 1'b0;
          cmd_index <= expected_read_command;
          cmd_argument <= io_is_switch ? io_lba : (high_capacity ? read_lba : (read_lba << 9));
          cmd_response_bits <= 8'd48;
          cmd_launch <= 1'b1;
          phase <= P_READ_WAIT;
        end
        P_READ_WAIT: begin
          if (sd_rise_pulse && dat_in == 4'b0000 &&
              (cmd_state == C_WAIT || cmd_state == C_RECV)) begin
            data_nibble_count <= 11'd0;
            calc_crc0 <= 16'd0;
            calc_crc1 <= 16'd0;
            calc_crc2 <= 16'd0;
            calc_crc3 <= 16'd0;
            card_crc0 <= 16'd0;
            card_crc1 <= 16'd0;
            card_crc2 <= 16'd0;
            card_crc3 <= 16'd0;
            if (io_transaction && !io_is_write) io_crc32 <= 32'hffffffff;
            boot_magic_shift <= 64'd0;
            partition_lba_shift <= 32'd0;
            sector_signature_shift <= 16'd0;
            last_read_wait_tail <= {read_wait_tail[59:0], dat_in};
            last_read_token_wait <= 32'hffffffff;
            early_token_count <= early_token_count + 1'b1;
            phase <= P_DATA_BITS;
          end else if (cmd_done) begin
            last_read_wait_tail <= read_wait_tail;
            if (response_frame_bad) begin
              if (io_transaction) begin
                io_status <= 8'h10;
                phase <= P_IO_READ_ERROR;
              end else begin failure_code <= MSG_CMD_TIMEOUT; phase <= P_FAIL; end
            end
            else if (response_shift[45:40] != expected_read_command ||
                     response_shift[30] || response_shift[27]) begin
              if (io_transaction) begin
                io_status <= 8'h10;
                phase <= P_IO_READ_ERROR;
              end else begin
                failure_code <= MSG_CMD_REJECT;
                phase <= P_FAIL;
              end
            end else begin
              wait_counter <= 20'd0;
              phase <= P_DATA_TOKEN;
            end
          end
        end
        P_DATA_TOKEN: begin
          if (sd_rise_pulse) begin
            if (dat_in == 4'b0000) begin
              last_read_token_wait <= {12'd0, wait_counter};
              data_nibble_count <= 11'd0;
              calc_crc0 <= 16'd0;
              calc_crc1 <= 16'd0;
              calc_crc2 <= 16'd0;
              calc_crc3 <= 16'd0;
              card_crc0 <= 16'd0;
              card_crc1 <= 16'd0;
              card_crc2 <= 16'd0;
              card_crc3 <= 16'd0;
              if (io_transaction && !io_is_write) io_crc32 <= 32'hffffffff;
              boot_magic_shift <= 64'd0;
              partition_lba_shift <= 32'd0;
              sector_signature_shift <= 16'd0;
              phase <= P_DATA_BITS;
            end else if (card_wait_cycles >= CARD_WAIT_SYS_CYCLES) begin
              if (io_transaction) begin
                io_status <= 8'h11;
                phase <= P_IO_READ_ERROR;
              end else begin
                failure_code <= MSG_DATA_TIMEOUT;
                phase <= P_FAIL;
              end
            end else wait_counter <= wait_counter + 1'b1;
          end
        end
        P_DATA_BITS: begin
          if (sd_rise_pulse) begin
            calc_crc0 <= crc0_next;
            calc_crc1 <= crc1_next;
            calc_crc2 <= crc2_next;
            calc_crc3 <= crc3_next;
            if (data_nibble_count >= 11'd6 && data_nibble_count <= 11'd21)
              boot_magic_shift <= {boot_magic_shift[59:0], dat_in};
            if (data_nibble_count >= 11'd908 && data_nibble_count <= 11'd915)
              partition_lba_shift <= {partition_lba_shift[27:0], dat_in};
            if (data_nibble_count >= 11'd1020 && data_nibble_count <= 11'd1023)
              sector_signature_shift <= {sector_signature_shift[11:0], dat_in};
            if (data_nibble_count == (io_is_switch ? 11'd127 : 11'd1023)) begin
              data_crc_count <= 5'd0;
              phase <= P_DATA_CRC;
            end else data_nibble_count <= data_nibble_count + 1'b1;
          end
        end
        P_DATA_CRC: begin
          if (sd_rise_pulse) begin
            card_crc0 <= {card_crc0[14:0], dat_in[0]};
            card_crc1 <= {card_crc1[14:0], dat_in[1]};
            card_crc2 <= {card_crc2[14:0], dat_in[2]};
            card_crc3 <= {card_crc3[14:0], dat_in[3]};
            if (data_crc_count == 5'd15) phase <= P_DATA_END;
            else data_crc_count <= data_crc_count + 1'b1;
          end
        end
        P_DATA_END: begin
          if (sd_rise_pulse) begin
            last_data_end <= dat_in;
            if (dat_in != 4'hf || card_crc0 != calc_crc0 || card_crc1 != calc_crc1 ||
                card_crc2 != calc_crc2 || card_crc3 != calc_crc3 || read_response_bad) begin
              count_data_crc_error <= count_data_crc_error + 1'b1;
              if (io_transaction) begin
                io_status <= 8'h12;
                phase <= P_IO_READ_ERROR;
              end else begin
                failure_code <= MSG_CRC_FAIL;
                phase <= P_FAIL;
              end
            end else begin
              count_read_ok <= count_read_ok + 1'b1;
              dma_word <= 0;
              phase <= P_DMA;
            end
          end
        end
        P_IO_READ_ERROR: begin
          rd_done <= 1; rd_error <= 1; io_transaction <= 0;
          phase <= P_READY;
        end
        P_READY: begin
                                                                              
          if (!slow_sd_clk && div_count == 0) half_period <= 0;
          if (rd_accept) begin
            io_transaction <= 1; io_is_write <= 0; io_is_multi <= 0;
            io_is_switch <= 0; io_payload_bytes <= 512;
            io_lba <= rd_lba; read_lba <= rd_lba; io_crc32 <= 32'hffffffff;
            wait_counter <= 0; intercmd_next_phase <= P_READ_START;
            phase <= P_INTERCMD_GAP;
          end
        end
        P_DMA: begin
          if (rd_valid && rd_ready) begin
            if (dma_word == 127) begin
              rd_done <= 1; io_transaction <= 0; phase <= P_READY;
            end else dma_word <= dma_word + 1'b1;
          end
        end
        P_FAIL: begin
          report_request <= failure_code;
          phase <= P_HALT;
        end
        P_HALT: begin end
        default: begin failure_code <= MSG_CMD_REJECT; phase <= P_FAIL; end
      endcase
    end
  end

  tf_uart_tx uart0 (
      .clk(clk50),
      .start(uart_start),
      .data(uart_data),
      .tx(uart_tx),
      .busy(uart_busy)
  );

  assign rd_accept = rd_req && phase == P_READY && half_period == 0;
  assign rd_valid = phase == P_DMA;
  assign rd_data = sector_word;
  assign initialized = bus_4bit && phase != P_HALT && phase != P_FAIL;
  assign fatal = phase == P_HALT || phase == P_FAIL;

endmodule

                                                                       
                                                                         
                                                                        
module crc16_next_state (
    input  wire [15:0] crc_in,
    input  wire        data_bit,
    output wire [15:0] crc_out
);
  wire feedback = crc_in[15] ^ data_bit;
  assign crc_out = {
      crc_in[14],
      crc_in[13],
      crc_in[12],
      crc_in[11] ^ feedback,
      crc_in[10],
      crc_in[9],
      crc_in[8],
      crc_in[7],
      crc_in[6],
      crc_in[5],
      crc_in[4] ^ feedback,
      crc_in[3],
      crc_in[2],
      crc_in[1],
      crc_in[0],
      feedback
  };
endmodule

module tf_uart_tx (
    input wire clk,
    input wire start,
    input wire [7:0] data,
    output reg tx = 1'b1,
    output reg busy = 1'b0
);
  reg [8:0] baud_count = 9'd0;
  reg [7:0] data_latch = 8'd0;
  reg [3:0] bit_index = 4'd0;
  reg active = 1'b0;

  always @(posedge clk) begin
    if (!active) begin
      tx <= 1'b1;
      busy <= 1'b0;
      baud_count <= 9'd0;
      if (start) begin
        active <= 1'b1;
        busy <= 1'b1;
        data_latch <= data;
        bit_index <= 4'd0;
        tx <= 1'b0;
      end
    end else if (baud_count == 9'd49) begin
      baud_count <= 9'd0;
      if (bit_index < 4'd8) begin
        tx <= data_latch[bit_index];
        bit_index <= bit_index + 1'b1;
      end else if (bit_index == 4'd8) begin
        tx <= 1'b1;
        bit_index <= 4'd9;
      end else begin
        active <= 1'b0;
        busy <= 1'b0;
        tx <= 1'b1;
      end
    end else baud_count <= baud_count + 1'b1;
  end
endmodule

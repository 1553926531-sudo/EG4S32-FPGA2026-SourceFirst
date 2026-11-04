`timescale 1ns/1ps
                                                                            
                                            
  
                                                                            
                                                                         
                                                                             
                                                                          
                   
module sii9134_i2c_writer (
    input  wire        rst,
    input  wire        clk,
    input  wire [15:0] clk_div_cnt,
    input  wire        i2c_addr_2byte,
    output reg  [9:0]  lut_index,
    input  wire [7:0]  lut_dev_addr,
    input  wire [15:0] lut_reg_addr,
    input  wire [7:0]  lut_reg_data,
    output reg         error,
    output reg         last_error,
    output reg  [7:0]  error_count,
                                                                   
                                                                 
    output reg  [2:0]  last_ack_bits,
    output reg  [2:0]  ack_bits0,
    output reg  [2:0]  ack_bits1,
    output reg  [2:0]  ack_bits2,
    output reg  [2:0]  ack_bits3,
    output reg [31:0]  ack_mask,
    output reg [23:0]  sent_bytes0,
    output reg [23:0]  sent_bytes1,
    output reg [23:0]  sent_bytes2,
    output reg [23:0]  sent_bytes3,
    output reg  [9:0]  first_error_index,
    output reg  [1:0]  first_error_byte_number,
    output reg  [7:0]  first_error_value,
    output reg  [4:0]  first_error_burst_data_index,
    output reg  [9:0]  last_transaction_index,
    output reg [23:0]  last_transaction_bytes,
    output wire        done,
    output wire [4:0]  debug_state,
    output wire [1:0]  debug_byte_number,
    output wire [3:0]  debug_bit_index,
    output wire [4:0]  debug_data_slot,
    inout  wire        i2c_scl,
    inout  wire        i2c_sda
);
                                                                            
                                                                          
    wire unused_clk_div_cnt = ^clk_div_cnt;
    wire unused_i2c_addr_2byte = i2c_addr_2byte;
    localparam integer I2C_TICK_CYCLES = 125;

    reg scl_drive_low = 1'b0;
    reg sda_drive_low = 1'b0;
    assign i2c_scl = scl_drive_low ? 1'b0 : 1'bz;
    assign i2c_sda = sda_drive_low ? 1'b0 : 1'bz;
    wire sda_in = i2c_sda;

    reg [9:0] tick_count = 10'd0;
    reg tick = 1'b0;
    always @(posedge clk) begin
        if (rst) begin
            tick_count <= 10'd0;
            tick <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (tick_count == I2C_TICK_CYCLES - 1) begin
                tick_count <= 10'd0;
                tick <= 1'b1;
            end else begin
                tick_count <= tick_count + 1'b1;
            end
        end
    end

    localparam ST_IDLE       = 5'd0;
    localparam ST_START_LOW  = 5'd1;
    localparam ST_START_HOLD = 5'd2;
    localparam ST_BIT_LOW    = 5'd3;
    localparam ST_BIT_HIGH   = 5'd4;
    localparam ST_BIT_FALL   = 5'd5;
    localparam ST_ACK_LOW    = 5'd6;
    localparam ST_ACK_HIGH   = 5'd7;
    localparam ST_ACK_FALL   = 5'd8;
    localparam ST_STOP_LOW   = 5'd9;
    localparam ST_STOP_HIGH  = 5'd10;
    localparam ST_STOP_SDA   = 5'd11;
    localparam ST_NEXT       = 5'd12;
    localparam ST_DONE       = 5'd13;
    localparam ST_RESTART_PREP = 5'd14;
    localparam ST_RESTART_HIGH = 5'd15;
    localparam ST_RESTART_HOLD = 5'd16;
    localparam ST_RESTART_FALL = 5'd17;
    localparam ST_GAP = 5'd18;
    localparam ST_BIT_LOW_HOLD = 5'd19;
    localparam ST_BIT_HIGH_HOLD = 5'd20;
    localparam ST_ACK_LOW_HOLD = 5'd21;
    localparam ST_ACK_RISE = 5'd22;
    localparam ST_STOP_LOW_HOLD = 5'd23;
    localparam ST_STOP_HIGH_HOLD = 5'd24;
    localparam ST_START_SETUP_HOLD = 5'd25;
    localparam integer INTER_TRANSACTION_GAP_TICKS = 40000;                         

    reg [4:0] state = ST_IDLE;
    reg [7:0] tx_byte = 8'd0;
                                                                         
    reg [7:0] active_dev_addr = 8'hff;
    reg [7:0] active_reg_addr = 8'hff;
    reg [7:0] active_reg_data = 8'hff;
    reg [1:0] byte_number = 2'd0;
    reg [3:0] bit_index = 4'd7;
    reg [15:0] gap_ticks = 16'd0;
    reg       ack_sample = 1'b1;
    reg       transaction_error = 1'b0;
    reg [2:0] ack_bits_current = 3'b000;
    reg       first_error_latched = 1'b0;

    assign done = (state == ST_DONE);
    assign debug_state = state;
    assign debug_byte_number = byte_number;
    assign debug_bit_index = bit_index;
    assign debug_data_slot = {byte_number, bit_index[2:0]};

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            lut_index <= 10'd0;
            tx_byte <= 8'd0;
            active_dev_addr <= 8'hff;
            active_reg_addr <= 8'hff;
            active_reg_data <= 8'hff;
            byte_number <= 2'd0;
            bit_index <= 4'd7;
            gap_ticks <= 16'd0;
            ack_sample <= 1'b1;
            transaction_error <= 1'b0;
            error <= 1'b0;
            last_error <= 1'b0;
            error_count <= 8'd0;
            last_ack_bits <= 3'b000;
            ack_bits0 <= 3'b000;
            ack_bits1 <= 3'b000;
            ack_bits2 <= 3'b000;
            ack_bits3 <= 3'b000;
            ack_mask <= 32'd0;
            sent_bytes0 <= 24'd0;
            sent_bytes1 <= 24'd0;
            sent_bytes2 <= 24'd0;
            sent_bytes3 <= 24'd0;
            first_error_index <= 10'd0;
            first_error_byte_number <= 2'd0;
            first_error_value <= 8'd0;
            first_error_burst_data_index <= 5'd0;
            last_transaction_index <= 10'd0;
            last_transaction_bytes <= 24'd0;
            ack_bits_current <= 3'b000;
            first_error_latched <= 1'b0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
        end else if (tick) begin
            case (state)
                ST_IDLE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    if (lut_dev_addr == 8'hff) begin
                        state <= ST_DONE;
                    end else begin
                        transaction_error <= 1'b0;
                        active_dev_addr <= lut_dev_addr;
                        active_reg_addr <= lut_reg_addr[7:0];
                        active_reg_data <= lut_reg_data;
                        ack_bits_current <= 3'b000;
                        byte_number <= 2'd0;
                        bit_index <= 4'd7;
                        tx_byte <= lut_dev_addr;
                        state <= ST_START_LOW;
                    end
                end

                                                                         
                ST_START_LOW: begin
                    sda_drive_low <= 1'b1;
                    scl_drive_low <= 1'b0;
                    state <= ST_START_SETUP_HOLD;
                end
                ST_START_SETUP_HOLD: begin
                    sda_drive_low <= 1'b1;
                    scl_drive_low <= 1'b0;
                    state <= ST_START_HOLD;
                end
                ST_START_HOLD: begin
                    scl_drive_low <= 1'b1;
                    state <= ST_BIT_LOW;
                end

                                                                           
                                                                      
                ST_BIT_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= ~tx_byte[bit_index];
                    state <= ST_BIT_HIGH;
                end
                ST_BIT_HIGH: begin
                    scl_drive_low <= 1'b0;
                    state <= ST_BIT_HIGH_HOLD;
                end
                ST_BIT_HIGH_HOLD: begin
                    scl_drive_low <= 1'b0;
                    state <= ST_BIT_FALL;
                end
                ST_BIT_FALL: begin
                    scl_drive_low <= 1'b1;
                    if (bit_index == 0) begin
                        sda_drive_low <= 1'b0;
                        state <= ST_ACK_LOW;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        state <= ST_BIT_LOW;
                    end
                end

                                                                           
                                           
                ST_ACK_LOW: begin
                    scl_drive_low <= 1'b0;
                    state <= ST_ACK_HIGH;
                end
                ST_ACK_HIGH: begin
                    ack_sample <= sda_in;
                    state <= ST_ACK_FALL;
                end
                ST_ACK_FALL: begin
                    scl_drive_low <= 1'b1;
                    if (lut_index == 10'd0) begin
                        case (byte_number)
                            2'd0: sent_bytes0[23:16] <= tx_byte;
                            2'd1: sent_bytes0[15:8]  <= tx_byte;
                            2'd2: sent_bytes0[7:0]   <= tx_byte;
                        endcase
                    end else if (lut_index == 10'd1) begin
                        case (byte_number)
                            2'd0: sent_bytes1[23:16] <= tx_byte;
                            2'd1: sent_bytes1[15:8]  <= tx_byte;
                            2'd2: sent_bytes1[7:0]   <= tx_byte;
                        endcase
                    end else if (lut_index == 10'd2) begin
                        case (byte_number)
                            2'd0: sent_bytes2[23:16] <= tx_byte;
                            2'd1: sent_bytes2[15:8]  <= tx_byte;
                            2'd2: sent_bytes2[7:0]   <= tx_byte;
                        endcase
                    end else if (lut_index == 10'd3) begin
                        case (byte_number)
                            2'd0: sent_bytes3[23:16] <= tx_byte;
                            2'd1: sent_bytes3[15:8]  <= tx_byte;
                            2'd2: sent_bytes3[7:0]   <= tx_byte;
                        endcase
                    end
                    if (!ack_sample) begin
                        case (byte_number)
                            2'd0: ack_bits_current[0] <= 1'b1;
                            2'd1: ack_bits_current[1] <= 1'b1;
                            2'd2: ack_bits_current[2] <= 1'b1;
                        endcase
                    end else begin
                        transaction_error <= 1'b1;
                        if (!first_error_latched) begin
                            first_error_latched <= 1'b1;
                            first_error_index <= lut_index;
                            first_error_byte_number <= byte_number;
                            first_error_value <= tx_byte;
                            first_error_burst_data_index <= 5'd0;
                        end
                    end
                    if (byte_number == 2) begin
                                                                      
                                                                          
                        state <= ST_STOP_LOW;
                    end else begin
                        byte_number <= byte_number + 1'b1;
                        bit_index <= 4'd7;
                        if (byte_number == 0)
                            tx_byte <= active_reg_addr;
                        else
                            tx_byte <= active_reg_data;
                        state <= ST_BIT_LOW;
                    end
                end

                                                                             
                ST_STOP_LOW: begin
                    sda_drive_low <= 1'b1;
                    scl_drive_low <= 1'b1;
                    state <= ST_STOP_HIGH;
                end
                ST_STOP_HIGH: begin
                    scl_drive_low <= 1'b0;
                    state <= ST_STOP_HIGH_HOLD;
                end
                ST_STOP_HIGH_HOLD: begin
                    scl_drive_low <= 1'b0;
                    state <= ST_STOP_SDA;
                end
                ST_STOP_SDA: begin
                    sda_drive_low <= 1'b0;
                    state <= ST_NEXT;
                end
                                                                              
                                                                            
                                                                               
                ST_RESTART_PREP: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b0;
                    state <= ST_RESTART_HIGH;
                end
                ST_RESTART_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= ST_RESTART_HOLD;
                end
                ST_RESTART_HOLD: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b1;
                    state <= ST_RESTART_FALL;
                end
                ST_RESTART_FALL: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b1;
                    active_dev_addr <= lut_dev_addr;
                    active_reg_addr <= lut_reg_addr[7:0];
                    active_reg_data <= lut_reg_data;
                    tx_byte <= lut_dev_addr;
                    byte_number <= 2'd0;
                    bit_index <= 4'd7;
                    ack_bits_current <= 3'b000;
                    transaction_error <= 1'b0;
                    state <= ST_BIT_LOW;
                end
                ST_NEXT: begin
                    last_error <= transaction_error;
                    last_ack_bits <= ack_bits_current;
                    last_transaction_index <= lut_index;
                    last_transaction_bytes <= {active_dev_addr, active_reg_addr, active_reg_data};
                    if (lut_index == 10'd0)
                        ack_bits0 <= ack_bits_current;
                    else if (lut_index == 10'd1)
                        ack_bits1 <= ack_bits_current;
                    else if (lut_index == 10'd2)
                        ack_bits2 <= ack_bits_current;
                    else if (lut_index == 10'd3)
                        ack_bits3 <= ack_bits_current;
                    if (!transaction_error)
                        ack_mask[lut_index[4:0]] <= 1'b1;
                    else
                        ack_mask[lut_index[4:0]] <= 1'b0;
                    if (transaction_error) begin
                        if (!error)
                            first_error_index <= lut_index;
                        error <= 1'b1;
                        if (error_count != 8'hff)
                            error_count <= error_count + 1'b1;
                    end
                    lut_index <= lut_index + 1'b1;
                    gap_ticks <= 16'd0;
                    state <= ST_GAP;
                end
                ST_GAP: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    if (gap_ticks == INTER_TRANSACTION_GAP_TICKS - 1) begin
                        gap_ticks <= 16'd0;
                        state <= ST_IDLE;
                    end else begin
                        gap_ticks <= gap_ticks + 1'b1;
                    end
                end
                ST_DONE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= ST_DONE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule


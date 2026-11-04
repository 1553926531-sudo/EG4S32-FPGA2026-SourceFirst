`timescale 1ns/1ps
                                      
  
                                                                          
                                                                          
                                                                            
                                                                            
                                                                            
                                                                           
                                      
module eg_dual_clock_mem #(
    parameter WIDTH = 32,
    parameter AW = 10,
    parameter IMPLEMENT = "32K"
) (
    input  wire             wclk,
    input  wire             wrst,
    input  wire             we,
    input  wire [AW-1:0]    waddr,
    input  wire [WIDTH-1:0] wdata,
    input  wire             rclk,
    input  wire             rrst,
    input  wire             re,
    input  wire [AW-1:0]    raddr,
    output wire [WIDTH-1:0] rdata
);
    wire [WIDTH-1:0] doa_unused;
    wire [WIDTH-1:0] dob;

                                                                         
                                                                             
                                                                            
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(WIDTH),
        .DATA_WIDTH_B(WIDTH),
        .ADDR_WIDTH_A(AW),
        .ADDR_WIDTH_B(AW),
        .DATA_DEPTH_A(1 << AW),
        .DATA_DEPTH_B(1 << AW),
        .BYTE_ENABLE(0),
        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("NORMAL"),
        .RESETMODE("ASYNC"),
        .IMPLEMENT(IMPLEMENT)
    ) mem (
        .dia(wdata),
        .addra(waddr),
        .cea(we),
        .ocea(1'b1),
        .clka(wclk),
        .wea(we),
        .rsta(wrst),
        .bea(1'b1),
        .dib({WIDTH{1'b0}}),
        .addrb(raddr),
        .ceb(re),
        .oceb(1'b1),
        .clkb(rclk),
        .web(1'b0),
        .rstb(rrst),
        .beb(1'b1),
        .doa(doa_unused),
        .dob(dob)
    );

    assign rdata = dob;
endmodule

                                                                          
                                                                          
                                                                        
                                                                          
                                                                           
                                                             
`ifdef __ICARUS__
module EG_LOGIC_BRAM #(
    parameter DATA_WIDTH_A = 9,
    parameter DATA_WIDTH_B = DATA_WIDTH_A,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter DATA_DEPTH_A = 2 ** ADDR_WIDTH_A,
    parameter DATA_DEPTH_B = 2 ** ADDR_WIDTH_B,
    parameter BYTE_ENABLE = 0,
    parameter BYTE_A = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_A / BYTE_ENABLE,
    parameter BYTE_B = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_B / BYTE_ENABLE,
    parameter MODE = "DP",
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "NOREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter RESETMODE = "SYNC",
    parameter DEBUGGABLE = "NO",
    parameter PACKABLE = "NO",
    parameter FORCE_KEEP = "OFF",
    parameter INIT_FILE = "NONE",
    parameter FILL_ALL = "NONE",
    parameter IMPLEMENT = "9K"
) (
    input  wire [DATA_WIDTH_A-1:0] dia,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire cea,
    input  wire ocea,
    input  wire clka,
    input  wire wea,
    input  wire rsta,
    input  wire [BYTE_A-1:0] bea,
    input  wire [DATA_WIDTH_B-1:0] dib,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire ceb,
    input  wire oceb,
    input  wire clkb,
    input  wire web,
    input  wire rstb,
    input  wire [BYTE_B-1:0] beb,
    output wire [DATA_WIDTH_A-1:0] doa,
    output wire [DATA_WIDTH_B-1:0] dob
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    reg [DATA_WIDTH_A-1:0] read_a;
    reg [DATA_WIDTH_B-1:0] read_b;
    always @(posedge clka) begin
        if (cea) begin
            if (wea) mem[addra] <= dia;
            else read_a <= mem[addra];
        end
    end
    always @(posedge clkb) begin
        if (ceb) begin
            if (web) mem[addrb] <= dib[DATA_WIDTH_A-1:0];
            else read_b <= mem[addrb];
        end
    end
    assign doa = read_a;
    assign dob = read_b;
endmodule
`endif

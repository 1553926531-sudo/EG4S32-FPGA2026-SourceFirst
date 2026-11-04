                                                              
                                          
                        
                                                              
                                                                            
                                                              
                                                                          
`timescale 1 ns / 100 fs

module pixel_pll (
    input  wire refclk,
    input  wire reset,
    output wire pixel_clk,
    output wire hdmi_clk,
    output wire locked
);
    wire clk0_buf;
    wire clk0_out;
    wire clk1_unused;
    wire clk3_unused;
    wire psdone_unused;
    wire [7:0] data_unused;

    EG_LOGIC_BUFG feedback_buf (
        .i(clk0_buf),
        .o(clk0_out)
    );

    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"),
        .DYNCFG("DISABLE"),
        .FIN("50.000"),
        .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("CLKC0_EXT"),
        .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE"),
        .SYNC_ENABLE("DISABLE"),
        .DERIVE_PLL_CLOCKS("DISABLE"),
        .GEN_BASIC_CLOCK("DISABLE"),
        .GMC_GAIN(4),
        .ICP_CURRENT(13),
        .KVCO(4),
        .LPF_CAPACITOR(1),
        .LPF_RESISTOR(4),
        .REFCLK_DIV(53),
        .FBCLK_DIV(13),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC0_DIV(67),
        .CLKC0_CPHASE(66),
        .CLKC0_FPHASE(0),
        .CLKC1_ENABLE("DISABLE"),
        .CLKC1_DIV(6),
        .CLKC1_CPHASE(6),
        .CLKC1_FPHASE(4),
        .CLKC2_ENABLE("ENABLE"),
        .CLKC2_DIV(10),
        .CLKC2_CPHASE(9),
        .CLKC2_FPHASE(0),
        .CLKC3_ENABLE("DISABLE"),
        .CLKC3_DIV(25),
        .CLKC3_CPHASE(24),
        .CLKC3_FPHASE(0),
        .CLKC4_ENABLE("ENABLE"),
        .CLKC4_DIV(10),
        .CLKC4_CPHASE(4),
        .CLKC4_FPHASE(0)
    ) pll_inst (
        .refclk(refclk),
        .reset(reset),
        .stdby(1'b0),
        .extlock(locked),
        .load_reg(1'b0),
        .psclk(1'b0),
        .psdown(1'b0),
        .psstep(1'b0),
        .psclksel(3'b000),
        .psdone(psdone_unused),
        .dclk(1'b0),
        .dcs(1'b0),
        .dwe(1'b0),
        .di(8'b00000000),
        .daddr(6'b000000),
        .\do (data_unused),
        .fbclk(clk0_out),
        .clkc({hdmi_clk, clk3_unused, pixel_clk, clk1_unused, clk0_buf})
    );
endmodule




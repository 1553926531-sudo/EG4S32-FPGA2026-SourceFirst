`timescale 1ns/1ps
                                                            
                                                                
                                                                                
module audio_pll(input wire refclk, input wire reset,
 output wire mclk, output wire locked);
 wire feedback_raw,feedback_buf;
 wire c1,c3,c4;
 EG_LOGIC_BUFG fb(.i(feedback_raw),.o(feedback_buf));
 EG_PHY_PLL #(
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000"),
 .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),.STDBY_ENABLE("DISABLE"),
 .PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),.DERIVE_PLL_CLOCKS("DISABLE"),
 .GEN_BASIC_CLOCK("DISABLE"),.GMC_GAIN(4),.ICP_CURRENT(13),.KVCO(4),
 .LPF_CAPACITOR(1),.LPF_RESISTOR(4),.REFCLK_DIV(59),.FBCLK_DIV(16),
 .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(58),.CLKC0_CPHASE(57),.CLKC0_FPHASE(0),
 .CLKC1_ENABLE("DISABLE"),.CLKC1_DIV(1),.CLKC1_CPHASE(0),.CLKC1_FPHASE(0),
 .CLKC2_ENABLE("ENABLE"),.CLKC2_DIV(64),.CLKC2_CPHASE(63),.CLKC2_FPHASE(0),
 .CLKC3_ENABLE("DISABLE"),.CLKC3_DIV(1),.CLKC3_CPHASE(0),.CLKC3_FPHASE(0),
 .CLKC4_ENABLE("DISABLE"),.CLKC4_DIV(1),.CLKC4_CPHASE(0),.CLKC4_FPHASE(0)
 ) pll_inst(.refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(locked),
 .load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'b0),
 .dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'b0),.daddr(6'b0),
 .fbclk(feedback_buf),.clkc({c4,c3,mclk,c1,feedback_raw}));
endmodule

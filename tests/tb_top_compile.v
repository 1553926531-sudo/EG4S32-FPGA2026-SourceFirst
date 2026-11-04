`timescale 1ns/1ps
                                                                             
                                                                           
                                                                    
module EG_LOGIC_BUFG(input wire i, output wire o);
 assign o=i;
endmodule

module EG_PHY_SDRAM_2M_32(
 input wire clk, input wire ras_n, input wire cas_n, input wire we_n,
 input wire [10:0] addr, input wire [1:0] ba, inout wire [31:0] dq,
 input wire cs_n, input wire dm0, input wire dm1, input wire dm2,
 input wire dm3, input wire cke
);
 assign dq=32'bz;
endmodule

module EG_PHY_PLL #(
 parameter DPHASE_SOURCE="DISABLE", DYNCFG="DISABLE", FIN="50.000",
 parameter FEEDBK_MODE="NORMAL", FEEDBK_PATH="CLKC0_EXT",
 parameter STDBY_ENABLE="DISABLE", PLLRST_ENA="ENABLE",
 parameter SYNC_ENABLE="DISABLE", DERIVE_PLL_CLOCKS="DISABLE",
 parameter GEN_BASIC_CLOCK="DISABLE", GMC_GAIN=4, ICP_CURRENT=13,
 parameter KVCO=4, LPF_CAPACITOR=1, LPF_RESISTOR=4,
 parameter REFCLK_DIV=1, FBCLK_DIV=1,
 parameter CLKC0_ENABLE="ENABLE", CLKC0_DIV=1, CLKC0_CPHASE=0, CLKC0_FPHASE=0,
 parameter CLKC1_ENABLE="DISABLE", CLKC1_DIV=1, CLKC1_CPHASE=0, CLKC1_FPHASE=0,
 parameter CLKC2_ENABLE="DISABLE", CLKC2_DIV=1, CLKC2_CPHASE=0, CLKC2_FPHASE=0,
 parameter CLKC3_ENABLE="DISABLE", CLKC3_DIV=1, CLKC3_CPHASE=0, CLKC3_FPHASE=0,
 parameter CLKC4_ENABLE="DISABLE", CLKC4_DIV=1, CLKC4_CPHASE=0, CLKC4_FPHASE=0
) (
 input wire refclk, reset, stdby, load_reg, psclk, psdown, psstep,
 input wire [2:0] psclksel, input wire dclk, dcs, dwe,
 input wire [7:0] di, input wire [5:0] daddr, input wire fbclk,
 output wire extlock, output wire psdone, output wire [7:0] \do ,
 output wire [4:0] clkc
);
 assign extlock=~reset;
 assign psdone=1'b0;
 assign \do = 8'b0;
 assign clkc={5{refclk}};
endmodule

module tb_top_compile;
 reg clk50=0;
 always #10 clk50=~clk50;
 tri1 sd_cmd;
 tri1 [3:0] sd_dat;
 tri1 hdmi_scl,hdmi_sda;
 reg hdmi_int=1'b1;
 reg [3:0] key_col_n=4'hf;
 reg [7:0] switches=0;
 wire uart_tx,sd_clk,hdmi_clk,hdmi_de,hdmi_hs,hdmi_vs,hdmi_nreset;
 wire [23:0] hdmi_d;
 wire i2s_mclk,i2s_sdata,i2s_lrclk,i2s_bclk;
 wire [3:0] key_row_n;
 wire [7:0] led,Digitron_Out;
 wire [3:0] DigitronCS_Out;
 media_player_top dut(
   .clk50(clk50),.uart_tx(uart_tx),.sd_clk(sd_clk),.sd_cmd(sd_cmd),.sd_dat(sd_dat),
   .hdmi_scl(hdmi_scl),.hdmi_sda(hdmi_sda),.hdmi_d(hdmi_d),.hdmi_clk(hdmi_clk),
   .hdmi_de(hdmi_de),.hdmi_hs(hdmi_hs),.hdmi_vs(hdmi_vs),.hdmi_nreset(hdmi_nreset),
   .hdmi_int(hdmi_int),.i2s_mclk(i2s_mclk),.i2s_sdata(i2s_sdata),
   .i2s_lrclk(i2s_lrclk),.i2s_bclk(i2s_bclk),.key_col_n(key_col_n),
   .key_row_n(key_row_n),.switches(switches),.led(led),
   .Digitron_Out(Digitron_Out),.DigitronCS_Out(DigitronCS_Out));
 initial begin
   #1;
   if(Digitron_Out!==8'h00 || DigitronCS_Out!==4'hf)begin
    $display("FAIL top_compile: numeric display enabled during startup");$finish;
   end
   repeat(100)begin
    @(negedge clk50);switches=switches+1'b1;key_col_n=key_col_n+1'b1;
    if(Digitron_Out!==8'h00 || DigitronCS_Out!==4'hf)begin
     $display("FAIL top_compile: numeric display enabled");$finish;
    end
   end
   $display("PASS top_compile: media_player_top elaborated with vendor PLL interface stubs; numeric display pins permanently disabled");
   $finish;
 end
endmodule

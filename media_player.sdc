create_clock -name clk50 -period 20.000 [get_ports {clk50}]
derive_pll_clocks


set_false_path -to [get_regs -hierarchical {*sync1*}]




set_false_path -to [get_regs -hierarchical {*_p1*}]



set_false_path -to [get_regs -hierarchical {scan/waveform/*_s1*}]
set_false_path -to [get_regs -hierarchical {visual_flush_s1*}]








set_false_path -from [get_regs -hierarchical {*lyric_text*}] -to [get_regs -hierarchical {*lyric_capture*}]

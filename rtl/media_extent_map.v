`timescale 1ns/1ps
                                                                                 
                                                                            
module media_extent_map(input wire [31:0] logical_lba, output wire [31:0] physical_lba,
 output wire valid, output wire [31:0] expected_header_crc, output wire [31:0] file_sectors);
assign physical_lba = 0;
assign valid = 0;
assign expected_header_crc = 0;
assign file_sectors = 0;
endmodule

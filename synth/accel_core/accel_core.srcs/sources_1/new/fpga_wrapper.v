`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/01/2026 09:44:18 AM
// Design Name: 
// Module Name: fpga_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module fpga_wrapper(
    input clk,
    input rst
);

cnn_accelerator dut(
    .clk(clk),
    .rst_n(~rst),

    .start_i(1'b0),
    .k_steps_i(8'd2),

    .act_buf_wr_en_i(1'b0),
    .act_buf_wr_addr_i('0),
    .act_buf_wr_data_i('0),

    .weight_buf_wr_en_i(1'b0),
    .weight_buf_wr_addr_i('0),
    .weight_buf_wr_data_i('0),

    .out_buf_rd_en_i(1'b0),
    .out_buf_rd_addr_i('0),

    .done_o()
);

endmodule
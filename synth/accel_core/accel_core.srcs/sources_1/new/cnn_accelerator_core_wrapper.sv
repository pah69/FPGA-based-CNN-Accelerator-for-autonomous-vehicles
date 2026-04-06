`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/01/2026 09:53:59 AM
// Design Name: 
// Module Name: cnn_accelerator_core_wrapper
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


`timescale 1ns / 1ps

module cnn_accelerator_fpga_wrapper #(
    parameter DATA_WIDTH     = 17,
    parameter ROWS           = 4,
    parameter COLS           = 4,
    parameter DEPTH          = 256,
    parameter ADDR_WIDTH     = 8,
    parameter ACC_WIDTH      = (2 * DATA_WIDTH) + 1,
    parameter OUT_WORD_WIDTH = ROWS * COLS * ACC_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    // simple control pins
    input  logic start_i,
    output logic busy_o,
    output logic done_o
);

    // ------------------------------------------------------------
    // Internal signals (NOT exposed as FPGA pins)
    // ------------------------------------------------------------

    logic [ADDR_WIDTH:0]        k_steps_i;

    logic                       act_buf_wr_en_i;
    logic [ADDR_WIDTH-1:0]      act_buf_wr_addr_i;
    logic [ROWS*DATA_WIDTH-1:0] act_buf_wr_data_i;

    logic                       weight_buf_wr_en_i;
    logic [ADDR_WIDTH-1:0]      weight_buf_wr_addr_i;
    logic [COLS*DATA_WIDTH-1:0] weight_buf_wr_data_i;

    logic                       out_buf_rd_en_i;
    logic [ADDR_WIDTH-1:0]      out_buf_rd_addr_i;
    logic [OUT_WORD_WIDTH-1:0]  out_buf_rd_data_o;

    // ------------------------------------------------------------
    // Tie-off logic (for synthesis resource estimation only)
    // ------------------------------------------------------------

    assign k_steps_i            = '0;

    assign act_buf_wr_en_i      = 1'b0;
    assign act_buf_wr_addr_i    = '0;
    assign act_buf_wr_data_i    = '0;

    assign weight_buf_wr_en_i   = 1'b0;
    assign weight_buf_wr_addr_i = '0;
    assign weight_buf_wr_data_i = '0;

    assign out_buf_rd_en_i      = 1'b0;
    assign out_buf_rd_addr_i    = '0;

    // ------------------------------------------------------------
    // Instantiate accelerator core
    // ------------------------------------------------------------

    cnn_accelerator_core #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ROWS           (ROWS),
        .COLS           (COLS),
        .DEPTH          (DEPTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .OUT_WORD_WIDTH (OUT_WORD_WIDTH)
    ) u_cnn_accelerator_core (

        .clk                  (clk),
        .rst_n                (rst_n),

        .start_i              (start_i),
        .k_steps_i            (k_steps_i),

        .busy_o               (busy_o),
        .done_o               (done_o),

        .act_buf_wr_en_i      (act_buf_wr_en_i),
        .act_buf_wr_addr_i    (act_buf_wr_addr_i),
        .act_buf_wr_data_i    (act_buf_wr_data_i),

        .weight_buf_wr_en_i   (weight_buf_wr_en_i),
        .weight_buf_wr_addr_i (weight_buf_wr_addr_i),
        .weight_buf_wr_data_i (weight_buf_wr_data_i),

        .out_buf_rd_en_i      (out_buf_rd_en_i),
        .out_buf_rd_addr_i    (out_buf_rd_addr_i),
        .out_buf_rd_data_o    (out_buf_rd_data_o)
    );

endmodule

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 10:47:29 PM
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


// cnn_acclerator_core_wrapper.v
// This wrapper instantiates the cnn_accelerator_core module.

module cnn_acclerator_core_wrapper #(
    parameter DATA_WIDTH     = 17,
    parameter ROWS           = 4,
    parameter COLS           = 4,
    parameter DEPTH          = 256,
    parameter ADDR_WIDTH     = 8, // $clog2(256)
    parameter ACC_WIDTH      = (2 * DATA_WIDTH) + 1,
    parameter OUT_WORD_WIDTH = ROWS * COLS * ACC_WIDTH
) (
    input                        clk,
    input                         rst_n,

    // Host / testbench control
    input                         start_i,
    input   [ADDR_WIDTH:0]        k_steps_i,
    output                        busy_o,
    output                        done_o,

    // External load path into activation_buffer
    input                         act_buf_wr_en_i,
    input   [ADDR_WIDTH-1:0]      act_buf_wr_addr_i,
    input   [ROWS*DATA_WIDTH-1:0] act_buf_wr_data_i,

    // External load path into weight_buffer
    input                         weight_buf_wr_en_i,
    input   [ADDR_WIDTH-1:0]      weight_buf_wr_addr_i,
    input   [COLS*DATA_WIDTH-1:0] weight_buf_wr_data_i,

    // External read path from output_buffer
    input                         out_buf_rd_en_i,
    input   [ADDR_WIDTH-1:0]      out_buf_rd_addr_i,
    output  [OUT_WORD_WIDTH-1:0]  out_buf_rd_data_o
);

  cnn_accelerator_core #(
      .DATA_WIDTH    (DATA_WIDTH),
      .ROWS          (ROWS),
      .COLS          (COLS),
      .DEPTH         (DEPTH),
      .ADDR_WIDTH    (ADDR_WIDTH),
      .ACC_WIDTH     (ACC_WIDTH),
      .OUT_WORD_WIDTH(OUT_WORD_WIDTH)
  ) u_cnn_accelerator_core (
      .clk                 (clk),
      .rst_n               (rst_n),
      .start_i             (start_i),
      .k_steps_i           (k_steps_i),
      .busy_o              (busy_o),
      .done_o              (done_o),
      .act_buf_wr_en_i     (act_buf_wr_en_i),
      .act_buf_wr_addr_i   (act_buf_wr_addr_i),
      .act_buf_wr_data_i   (act_buf_wr_data_i),
      .weight_buf_wr_en_i  (weight_buf_wr_en_i),
      .weight_buf_wr_addr_i(weight_buf_wr_addr_i),
      .weight_buf_wr_data_i(weight_buf_wr_data_i),
      .out_buf_rd_en_i     (out_buf_rd_en_i),
      .out_buf_rd_addr_i   (out_buf_rd_addr_i),
      .out_buf_rd_data_o   (out_buf_rd_data_o)
  );

endmodule

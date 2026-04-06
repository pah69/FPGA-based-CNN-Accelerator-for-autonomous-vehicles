`timescale 1ns / 1ps

module cnn_accelerator_core #(
    parameter DATA_WIDTH     = 17,
    parameter ROWS           = 4,
    parameter COLS           = 4,
    parameter DEPTH          = 256,
    parameter ADDR_WIDTH     = $clog2(DEPTH),
    parameter ACC_WIDTH      = (2 * DATA_WIDTH) + 1,
    parameter OUT_WORD_WIDTH = ROWS * COLS * ACC_WIDTH
) (
    input logic clk,
    input logic rst_n,

    // -------------------------------------------------------------------------
    // Host / testbench control
    // -------------------------------------------------------------------------
    input logic start_i,
    input logic [ADDR_WIDTH:0] k_steps_i,

    output logic busy_o,
    output logic done_o,

    // -------------------------------------------------------------------------
    // External load path into activation_buffer
    // One address holds one full activation vector for one reduction step k:
    // {A[ROWS-1][k], ..., A[0][k]}
    // -------------------------------------------------------------------------
    input logic                       act_buf_wr_en_i,
    input logic [     ADDR_WIDTH-1:0] act_buf_wr_addr_i,
    input logic [ROWS*DATA_WIDTH-1:0] act_buf_wr_data_i,

    // -------------------------------------------------------------------------
    // External load path into weight_buffer
    // One address holds one full weight vector for one reduction step k:
    // {B[k][COLS-1], ..., B[k][0]}
    // -------------------------------------------------------------------------
    input logic                       weight_buf_wr_en_i,
    input logic [     ADDR_WIDTH-1:0] weight_buf_wr_addr_i,
    input logic [COLS*DATA_WIDTH-1:0] weight_buf_wr_data_i,

    // -------------------------------------------------------------------------
    // External read path from output_buffer
    // -------------------------------------------------------------------------
    input  logic                      out_buf_rd_en_i,
    input  logic [    ADDR_WIDTH-1:0] out_buf_rd_addr_i,
    output logic [OUT_WORD_WIDTH-1:0] out_buf_rd_data_o
);

  // -------------------------------------------------------------------------
  // Internal wiring
  // -------------------------------------------------------------------------
  logic                       act_rd_en;
  logic [     ADDR_WIDTH-1:0] act_rd_addr;
  logic [ROWS*DATA_WIDTH-1:0] act_rd_data;

  logic                       weight_rd_en;
  logic [     ADDR_WIDTH-1:0] weight_rd_addr;
  logic [COLS*DATA_WIDTH-1:0] weight_rd_data;

  // logic act_valid_s;
  // logic act_start_s;
  // logic act_clear_s;
  // logic weight_valid_s;
  // logic capture_results_s;
  logic                       act_local_load_s;
  logic                       act_fire_s;
  logic                       act_start_fire_s;
  logic                       act_clear_fire_s;

  logic                       weight_local_load_s;
  logic                       pe_weight_load_s;


  logic [ OUT_WORD_WIDTH-1:0] comp_result_vec;
  logic                       comp_result_valid;
  logic                       array_all_valid;

  logic                       out_wr_en;
  logic [     ADDR_WIDTH-1:0] out_wr_addr;

  // -------------------------------------------------------------------------
  // activation_buffer
  // -------------------------------------------------------------------------
  activation_buffer #(
      .DATA_WIDTH(DATA_WIDTH),
      .ROWS      (ROWS),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_activation_buffer (
      .clk    (clk),
      .wr_en  (act_buf_wr_en_i),
      .wr_addr(act_buf_wr_addr_i),
      .wr_data(act_buf_wr_data_i),
      .rd_en  (act_rd_en),
      .rd_addr(act_rd_addr),
      .rd_data(act_rd_data)
  );

  // -------------------------------------------------------------------------
  // weight_buffer
  // -------------------------------------------------------------------------
  weight_buffer #(
      .DATA_WIDTH(DATA_WIDTH),
      .COLS      (COLS),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_weight_buffer (
      .clk    (clk),
      .wr_en  (weight_buf_wr_en_i),
      .wr_addr(weight_buf_wr_addr_i),
      .wr_data(weight_buf_wr_data_i),
      .rd_en  (weight_rd_en),
      .rd_addr(weight_rd_addr),
      .rd_data(weight_rd_data)
  );

  // -------------------------------------------------------------------------
  // computational_array
  // -------------------------------------------------------------------------
  computation_engine #(
    .DATA_WIDTH(DATA_WIDTH),
    .ROWS      (ROWS),
    .COLS      (COLS),
    .ACC_WIDTH (ACC_WIDTH)
) u_computation_engine (
    .clk               (clk),
    .rst_n             (rst_n),

    .act_vec_i         (act_rd_data),
    .weight_vec_i      (weight_rd_data),

    .act_local_load_i  (act_local_load_s),
    .act_fire_i        (act_fire_s),
    .act_start_fire_i  (act_start_fire_s),
    .act_clear_fire_i  (act_clear_fire_s),

    .weight_local_load_i(weight_local_load_s),
    .pe_weight_load_i  (pe_weight_load_s),

    .capture_results_i (capture_results_s),

    .result_vec_o      (comp_result_vec),
    .result_valid_o    (comp_result_valid),
    .array_all_valid_o (array_all_valid)
);


  // -------------------------------------------------------------------------
  // controller
  // -------------------------------------------------------------------------
  controller #(
    .DATA_WIDTH        (DATA_WIDTH),
    .ROWS              (ROWS),
    .COLS              (COLS),
    .DEPTH             (DEPTH),
    .ADDR_WIDTH        (ADDR_WIDTH),
    .FINAL_RESULT_DELAY(5)
) u_controller (
    .clk                (clk),
    .rst_n              (rst_n),
    .start_i            (start_i),
    .k_steps_i          (k_steps_i),
    .array_all_valid_i  (array_all_valid),
    .result_valid_i     (comp_result_valid),

    .act_rd_en_o        (act_rd_en),
    .act_rd_addr_o      (act_rd_addr),
    .weight_rd_en_o     (weight_rd_en),
    .weight_rd_addr_o   (weight_rd_addr),

    .act_local_load_o   (act_local_load_s),
    .act_fire_o         (act_fire_s),
    .act_start_fire_o   (act_start_fire_s),
    .act_clear_fire_o   (act_clear_fire_s),

    .weight_local_load_o(weight_local_load_s),
    .pe_weight_load_o   (pe_weight_load_s),

    .capture_results_o  (capture_results_s),

    .out_wr_en_o        (out_wr_en),
    .out_wr_addr_o      (out_wr_addr),

    .busy_o             (busy_o),
    .done_o             (done_o)
);

  // -------------------------------------------------------------------------
  // output_buffer
  // -------------------------------------------------------------------------
  output_buffer #(
      .WORD_WIDTH(OUT_WORD_WIDTH),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_output_buffer (
      .clk    (clk),
      .wr_en  (out_wr_en),
      .wr_addr(out_wr_addr),
      .wr_data(comp_result_vec),
      .rd_en  (out_buf_rd_en_i),
      .rd_addr(out_buf_rd_addr_i),
      .rd_data(out_buf_rd_data_o)
  );

endmodule : cnn_accelerator_core

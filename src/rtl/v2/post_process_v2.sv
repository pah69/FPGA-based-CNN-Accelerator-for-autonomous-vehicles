`timescale 1ns / 1ps

module post_process_v2 #(
    parameter int SIZE        = 2,
    parameter int ACC_WIDTH   = 32,
    parameter int ACT_WIDTH   = ACC_WIDTH,
    parameter int OUT_WIDTH   = 8,
    parameter int ACT_MODE    = 1,
    parameter int ACT_CLIP_MAX = 6,
    parameter int ACT_INPUT_SHIFT = 0,
    parameter int ACT_FRAC_BITS   = 8,
    parameter int NORM_SHIFT  = 0,
    parameter bit NORM_ROUND_ENABLE = 1'b1,
    parameter int POOL_MODE   = 0,
    parameter int POOL_WINDOW = 2
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(ACC_WIDTH*SIZE)-1:0] acc_flatten_i,
    input logic                               acc_valid_i,
    input logic                               done_i,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                               data_valid_o,
    output logic                               done_o
);

  logic signed [(ACT_WIDTH*SIZE)-1:0] act_flatten_w;
  logic                                act_valid_w;
  logic                                act_done_w;

  logic signed [(OUT_WIDTH*SIZE)-1:0] norm_flatten_w;
  logic                                norm_valid_w;
  logic                                norm_done_w;

  activation_array_v2 #(
      .SIZE    (SIZE),
      .IN_WIDTH(ACC_WIDTH),
      .OUT_WIDTH(ACT_WIDTH),
      .ACT_MODE(ACT_MODE),
      .CLIP_MAX(ACT_CLIP_MAX),
      .ACT_INPUT_SHIFT(ACT_INPUT_SHIFT),
      .ACT_FRAC_BITS(ACT_FRAC_BITS)
  ) u_activation (
      .clk           (clk),
      .rst_n         (rst_n),
      .data_flatten_i(acc_flatten_i),
      .data_valid_i  (acc_valid_i),
      .done_i        (done_i),
      .data_flatten_o(act_flatten_w),
      .data_valid_o  (act_valid_w),
      .done_o        (act_done_w)
  );

  normalizer_v2 #(
      .SIZE      (SIZE),
      .IN_WIDTH  (ACT_WIDTH),
      .OUT_WIDTH (OUT_WIDTH),
      .NORM_SHIFT(NORM_SHIFT),
      .ROUND_ENABLE(NORM_ROUND_ENABLE)
  ) u_normalizer (
      .clk           (clk),
      .rst_n         (rst_n),
      .data_flatten_i(act_flatten_w),
      .data_valid_i  (act_valid_w),
      .done_i        (act_done_w),
      .data_flatten_o(norm_flatten_w),
      .data_valid_o  (norm_valid_w),
      .done_o        (norm_done_w)
  );

  pooling_unit_v2 #(
      .SIZE       (SIZE),
      .DATA_WIDTH (OUT_WIDTH),
      .POOL_MODE  (POOL_MODE),
      .POOL_WINDOW(POOL_WINDOW)
  ) u_pooling (
      .clk           (clk),
      .rst_n         (rst_n),
      .data_flatten_i(norm_flatten_w),
      .data_valid_i  (norm_valid_w),
      .done_i        (norm_done_w),
      .data_flatten_o(data_flatten_o),
      .data_valid_o  (data_valid_o),
      .done_o        (done_o)
  );

endmodule : post_process_v2

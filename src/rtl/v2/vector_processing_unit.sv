`timescale 1ns / 1ps

module vector_processing_unit #(
    parameter int SIZE                = 2,
    parameter int ACC_WIDTH           = 32,
    parameter int ACT_WIDTH           = ACC_WIDTH,
    parameter int OUT_WIDTH           = 8,
    parameter int ACT_MODE            = 1,
    parameter int ACT_CLIP_MAX        = 6,
    parameter int ACT_INPUT_SHIFT     = 0,
    parameter int ACT_FRAC_BITS       = 8,
    parameter bit QUANT_ENABLE        = 1'b0,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int QUANT_CLAMP_MIN     = -128,
    parameter int QUANT_CLAMP_MAX     = 127,
    parameter int NORM_SHIFT          = 0,
    parameter bit NORM_ROUND_ENABLE   = 1'b1,
    parameter int POOL_MODE           = 0,
    parameter int POOL_WINDOW         = 2
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(ACC_WIDTH*SIZE)-1:0] acc_flatten_i,
    input logic                               acc_valid_i,
    input logic                               done_i,
    input logic [1:0]                         act_mode_i,

    input logic signed [         (BIAS_WIDTH*SIZE)-1:0] bias_flatten_i,
    input logic signed [ (REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_i,
    input logic        [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_i,
    input logic signed [                 ACC_WIDTH-1:0] output_zero_point_i,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                               data_valid_o,
    output logic                               done_o
);

  post_process_v2 #(
      .SIZE               (SIZE),
      .ACC_WIDTH          (ACC_WIDTH),
      .ACT_WIDTH          (ACT_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .ACT_MODE           (ACT_MODE),
      .ACT_CLIP_MAX       (ACT_CLIP_MAX),
      .ACT_INPUT_SHIFT    (ACT_INPUT_SHIFT),
      .ACT_FRAC_BITS      (ACT_FRAC_BITS),
      .QUANT_ENABLE       (QUANT_ENABLE),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .QUANT_CLAMP_MIN    (QUANT_CLAMP_MIN),
      .QUANT_CLAMP_MAX    (QUANT_CLAMP_MAX),
      .NORM_SHIFT         (NORM_SHIFT),
      .NORM_ROUND_ENABLE  (NORM_ROUND_ENABLE),
      .POOL_MODE          (POOL_MODE),
      .POOL_WINDOW        (POOL_WINDOW)
  ) u_post_process (
      .clk                         (clk),
      .rst_n                       (rst_n),
      .acc_flatten_i               (acc_flatten_i),
      .acc_valid_i                 (acc_valid_i),
      .done_i                      (done_i),
      .act_mode_i                  (act_mode_i),
      .bias_flatten_i              (bias_flatten_i),
      .requant_multiplier_flatten_i(requant_multiplier_flatten_i),
      .requant_shift_flatten_i     (requant_shift_flatten_i),
      .output_zero_point_i         (output_zero_point_i),
      .data_flatten_o              (data_flatten_o),
      .data_valid_o                (data_valid_o),
      .done_o                      (done_o)
  );

endmodule : vector_processing_unit_v2

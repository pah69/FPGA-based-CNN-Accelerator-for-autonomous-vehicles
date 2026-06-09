`timescale 1ns / 1ps

// Adds INT32 bias and applies fixed-point requantization per lane.
module bias_requantize #(
    parameter int SIZE                = 2,
    parameter int ACC_WIDTH           = 32,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int QUANT_CLAMP_MIN     = -128,
    parameter int QUANT_CLAMP_MAX     = 127
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(ACC_WIDTH*SIZE)-1:0] acc_flatten_i,
    input logic                               acc_valid_i,
    input logic                               done_i,

    input logic signed [         (BIAS_WIDTH*SIZE)-1:0] bias_flatten_i,
    input logic signed [ (REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_i,
    input logic        [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_i,
    input logic signed [                 ACC_WIDTH-1:0] output_zero_point_i,

    output logic signed [(ACC_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic                               data_valid_o,
    output logic                               done_o
);

  localparam int BIASED_WIDTH = ((ACC_WIDTH > BIAS_WIDTH) ? ACC_WIDTH : BIAS_WIDTH) + 1;
  localparam int PROD_WIDTH = BIASED_WIDTH + REQUANT_MULT_WIDTH + 1;

  localparam logic signed [ACC_WIDTH-1:0] CLAMP_MIN_VALUE = ACC_WIDTH'($signed(QUANT_CLAMP_MIN));
  localparam logic signed [ACC_WIDTH-1:0] CLAMP_MAX_VALUE = ACC_WIDTH'($signed(QUANT_CLAMP_MAX));
  localparam logic signed [PROD_WIDTH-1:0] CLAMP_MIN_EXT = PROD_WIDTH'($signed(QUANT_CLAMP_MIN));
  localparam logic signed [PROD_WIDTH-1:0] CLAMP_MAX_EXT = PROD_WIDTH'($signed(QUANT_CLAMP_MAX));

  logic signed [ACC_WIDTH-1:0] lane_requant_w[0:SIZE-1];

  function automatic logic signed [ACC_WIDTH-1:0] clamp_acc(
      input logic signed [ACC_WIDTH-1:0] value_i);
    begin
      if (value_i > CLAMP_MAX_VALUE) begin
        clamp_acc = CLAMP_MAX_VALUE;
      end else if (value_i < CLAMP_MIN_VALUE) begin
        clamp_acc = CLAMP_MIN_VALUE;
      end else begin
        clamp_acc = value_i;
      end
    end
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] requant_lane(
      input logic signed [ACC_WIDTH-1:0] acc_i, input logic signed [BIAS_WIDTH-1:0] bias_i,
      input logic signed [REQUANT_MULT_WIDTH-1:0] multiplier_i,
      input logic [REQUANT_SHIFT_WIDTH-1:0] shift_i,
      input logic signed [ACC_WIDTH-1:0] zero_point_i);
    logic signed [BIASED_WIDTH-1:0] acc_ext;
    logic signed [BIASED_WIDTH-1:0] bias_ext;
    logic signed [BIASED_WIDTH-1:0] biased_value;
    logic signed [  PROD_WIDTH-1:0] product_value;
    logic signed [  PROD_WIDTH-1:0] rounded_product;
    logic signed [  PROD_WIDTH-1:0] rounding_offset;
    logic signed [  PROD_WIDTH-1:0] shifted_value;
    logic signed [  PROD_WIDTH-1:0] zero_point_ext;
    logic signed [  PROD_WIDTH-1:0] requant_with_zero;
    begin
      acc_ext    = {{(BIASED_WIDTH - ACC_WIDTH) {acc_i[ACC_WIDTH-1]}}, acc_i};
      bias_ext   = {{(BIASED_WIDTH - BIAS_WIDTH) {bias_i[BIAS_WIDTH-1]}}, bias_i};
      biased_value = acc_ext + bias_ext;

      product_value = biased_value * multiplier_i;

      if (shift_i == '0) begin
        shifted_value = product_value;
      end else begin
        rounding_offset = PROD_WIDTH'($signed(1)) <<< (shift_i - 1'b1);
        if (product_value >= 0) begin
          rounded_product = product_value + rounding_offset;
        end else begin
          rounded_product = product_value - rounding_offset;
        end
        shifted_value = rounded_product >>> shift_i;
      end

      zero_point_ext = {{(PROD_WIDTH - ACC_WIDTH) {zero_point_i[ACC_WIDTH-1]}}, zero_point_i};
      requant_with_zero = shifted_value + zero_point_ext;

      if (requant_with_zero > CLAMP_MAX_EXT) begin
        requant_lane = CLAMP_MAX_VALUE;
      end else if (requant_with_zero < CLAMP_MIN_EXT) begin
        requant_lane = CLAMP_MIN_VALUE;
      end else begin
        requant_lane = clamp_acc(requant_with_zero[ACC_WIDTH-1:0]);
      end
    end
  endfunction

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      lane_requant_w[lane] = requant_lane(
        acc_flatten_i[(lane*ACC_WIDTH)+:ACC_WIDTH],
        bias_flatten_i[(lane*BIAS_WIDTH)+:BIAS_WIDTH],
        requant_multiplier_flatten_i[(lane*REQUANT_MULT_WIDTH)+:REQUANT_MULT_WIDTH],
        requant_shift_flatten_i[(lane*REQUANT_SHIFT_WIDTH)+:REQUANT_SHIFT_WIDTH],
        output_zero_point_i
      );
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_flatten_o <= '0;
      data_valid_o   <= 1'b0;
      done_o         <= 1'b0;
    end else begin
      if (acc_valid_i) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          data_flatten_o[(lane*ACC_WIDTH)+:ACC_WIDTH] <= lane_requant_w[lane];
        end
      end

      data_valid_o <= acc_valid_i;
      done_o       <= acc_valid_i && done_i;
    end
  end

endmodule : bias_requantize_v2

`timescale 1ns / 1ps

// Correctness-first signed INT8 Dense/FC block.
//
// Weight layout is output-major: weight[output][input].
module animals10_dense_i8 #(
    parameter int INPUT_FEATURES = 128,
    parameter int OUTPUT_FEATURES = 128,
    parameter bit RELU = 1'b1,
    parameter int INPUT_ADDR_WIDTH = 7,
    parameter int WEIGHT_ADDR_WIDTH = 14,
    parameter int PARAM_ADDR_WIDTH = 7,
    parameter int OUTPUT_ADDR_WIDTH = 7
) (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [INPUT_ADDR_WIDTH-1:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [PARAM_ADDR_WIDTH-1:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [OUTPUT_ADDR_WIDTH-1:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_cycle_count_o,
    output logic [31:0] debug_output_count_o
);

  localparam int WEIGHT_COUNT = INPUT_FEATURES * OUTPUT_FEATURES;

  logic signed [7:0] input_mem[0:INPUT_FEATURES-1];
  logic signed [7:0] weight_mem[0:WEIGHT_COUNT-1];
  logic signed [31:0] bias_mem[0:OUTPUT_FEATURES-1];
  logic signed [31:0] requant_mult_mem[0:OUTPUT_FEATURES-1];
  logic signed [7:0] requant_shift_mem[0:OUTPUT_FEATURES-1];
  int output_q;

  function automatic int weight_idx(input int output_feature, input int input_feature);
    begin
      weight_idx = (output_feature * INPUT_FEATURES) + input_feature;
    end
  endfunction

  function automatic logic signed [31:0] dense_acc(input int output_feature);
    longint signed acc;
    begin
      acc = 64'sd0;
      for (int input_feature = 0; input_feature < INPUT_FEATURES; input_feature++) begin
        acc += longint'(input_mem[input_feature])
             * longint'(weight_mem[weight_idx(output_feature, input_feature)]);
      end
      dense_acc = acc[31:0];
    end
  endfunction

  function automatic longint signed round_shift_i64(input longint signed value, input int shift);
    longint signed offset;
    begin
      if (shift == 0) begin
        round_shift_i64 = value;
      end else begin
        offset = 64'sd1 <<< (shift - 1);
        if (value >= 0) begin
          round_shift_i64 = (value + offset) >>> shift;
        end else begin
          round_shift_i64 = (value - offset) >>> shift;
        end
      end
    end
  endfunction

  function automatic int signed clamp_i8(input longint signed value);
    begin
      if (value > 127) begin
        clamp_i8 = 127;
      end else if (value < -128) begin
        clamp_i8 = -128;
      end else begin
        clamp_i8 = int'(value);
      end
    end
  endfunction

  function automatic logic signed [7:0] requant_i8(
      input int output_feature,
      input longint signed acc
  );
    longint signed biased;
    longint signed product;
    longint signed scaled;
    int signed clipped;
    begin
      biased = acc + longint'(bias_mem[output_feature]);
      product = biased * longint'(requant_mult_mem[output_feature]);
      scaled = round_shift_i64(product, int'(requant_shift_mem[output_feature]));
      clipped = clamp_i8(scaled);
      if (RELU && clipped < 0) begin
        requant_i8 = 8'sd0;
      end else begin
        requant_i8 = clipped[7:0];
      end
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    logic signed [31:0] acc_next;

    if (!rst_n) begin
      busy_o <= 1'b0;
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;
      output_index_o <= '0;
      acc_o <= '0;
      data_o <= '0;
      output_q <= 0;
      debug_cycle_count_o <= '0;
      debug_output_count_o <= '0;
    end else begin
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;

      if (input_we_i) begin
        input_mem[input_addr_i] <= input_data_i;
      end
      if (weight_we_i) begin
        weight_mem[weight_addr_i] <= weight_data_i;
      end
      if (param_we_i) begin
        bias_mem[param_addr_i] <= bias_data_i;
        requant_mult_mem[param_addr_i] <= requant_mult_data_i;
        requant_shift_mem[param_addr_i] <= requant_shift_data_i;
      end

      if (busy_o) begin
        debug_cycle_count_o <= debug_cycle_count_o + 32'd1;
      end

      if (start_i && !busy_o) begin
        busy_o <= 1'b1;
        output_q <= 0;
        debug_cycle_count_o <= '0;
        debug_output_count_o <= '0;
      end else if (busy_o) begin
        acc_next = dense_acc(output_q);
        output_valid_o <= 1'b1;
        output_index_o <= OUTPUT_ADDR_WIDTH'(output_q);
        acc_o <= acc_next;
        data_o <= requant_i8(output_q, longint'(acc_next));
        debug_output_count_o <= debug_output_count_o + 32'd1;

        if (output_q == OUTPUT_FEATURES - 1) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
          output_last_o <= 1'b1;
        end else begin
          output_q <= output_q + 1;
        end
      end
    end
  end

endmodule : animals10_dense_i8

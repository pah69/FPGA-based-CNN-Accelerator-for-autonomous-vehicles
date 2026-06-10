`timescale 1ns / 1ps

// Staged Animals-10 V1 final block:
// Conv5 -> Conv6 -> Pool3 -> GAP -> FC1 -> FC2.
//
// This wrapper validates the complete final network stage from Pool2 output to
// final logits before the full Conv1-to-logits path is connected.
module animals10_conv5_conv6_pool3_gap_fc1_fc2_i8 (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [13:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [17:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [8:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [3:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_conv5_cycle_count_o,
    output logic [31:0] debug_conv5_tile_count_o,
    output logic [31:0] debug_conv5_output_count_o,
    output logic [31:0] debug_conv6_cycle_count_o,
    output logic [31:0] debug_conv6_tile_count_o,
    output logic [31:0] debug_conv6_output_count_o,
    output logic [31:0] debug_pool3_cycle_count_o,
    output logic [31:0] debug_pool3_output_count_o,
    output logic [31:0] debug_gap_cycle_count_o,
    output logic [31:0] debug_gap_output_count_o,
    output logic [31:0] debug_fc1_cycle_count_o,
    output logic [31:0] debug_fc1_output_count_o,
    output logic [31:0] debug_fc2_cycle_count_o,
    output logic [31:0] debug_fc2_output_count_o
);

  localparam int CONV5_CONV6_WEIGHT_COUNT = (128 * 64 * 3 * 3) + (128 * 128 * 3 * 3);
  localparam int CONV5_CONV6_PARAM_COUNT = 256;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_CONV_POOL,
    S_START_CLASSIFIER,
    S_RUN_CLASSIFIER
  } state_t;

  state_t state_q;

  logic conv_pool_start_q;
  logic conv_pool_busy_w;
  logic conv_pool_done_w;
  logic conv_pool_input_we_w;
  logic conv_pool_weight_we_w;
  logic [17:0] conv_pool_weight_addr_w;
  logic conv_pool_param_we_w;
  logic [7:0] conv_pool_param_addr_w;
  logic conv_pool_output_valid_w;
  logic conv_pool_output_last_w;
  logic [12:0] conv_pool_output_index_w;
  logic signed [7:0] conv_pool_data_w;
  logic [31:0] conv_pool_total_cycle_count_w;
  logic [31:0] conv5_cycle_count_w;
  logic [31:0] conv5_tile_count_w;
  logic [31:0] conv5_output_count_w;
  logic [31:0] conv6_cycle_count_w;
  logic [31:0] conv6_tile_count_w;
  logic [31:0] conv6_output_count_w;
  logic [31:0] pool3_cycle_count_w;
  logic [31:0] pool3_output_count_w;

  logic classifier_start_q;
  logic classifier_busy_w;
  logic classifier_done_w;
  logic classifier_input_we_w;
  logic [12:0] classifier_input_addr_w;
  logic signed [7:0] classifier_input_data_w;
  logic classifier_weight_we_w;
  logic [17:0] classifier_weight_addr_full_w;
  logic [14:0] classifier_weight_addr_w;
  logic classifier_param_we_w;
  logic [8:0] classifier_param_addr_full_w;
  logic [7:0] classifier_param_addr_w;
  logic classifier_output_valid_w;
  logic classifier_output_last_w;
  logic [3:0] classifier_output_index_w;
  logic signed [31:0] classifier_acc_w;
  logic signed [7:0] classifier_data_w;
  logic [31:0] classifier_total_cycle_count_w;
  logic [31:0] gap_cycle_count_w;
  logic [31:0] gap_output_count_w;
  logic [31:0] fc1_cycle_count_w;
  logic [31:0] fc1_output_count_w;
  logic [31:0] fc2_cycle_count_w;
  logic [31:0] fc2_output_count_w;

  assign conv_pool_input_we_w = input_we_i && (state_q == S_IDLE);
  assign conv_pool_weight_we_w = weight_we_i && (weight_addr_i < 18'(CONV5_CONV6_WEIGHT_COUNT));
  assign conv_pool_weight_addr_w = weight_addr_i;
  assign conv_pool_param_we_w = param_we_i && (param_addr_i < 9'(CONV5_CONV6_PARAM_COUNT));
  assign conv_pool_param_addr_w = param_addr_i[7:0];

  assign classifier_input_we_w = conv_pool_output_valid_w;
  assign classifier_input_addr_w = conv_pool_output_index_w;
  assign classifier_input_data_w = conv_pool_data_w;
  assign classifier_weight_we_w = weight_we_i && (weight_addr_i >= 18'(CONV5_CONV6_WEIGHT_COUNT));
  assign classifier_weight_addr_full_w = weight_addr_i - 18'(CONV5_CONV6_WEIGHT_COUNT);
  assign classifier_weight_addr_w = classifier_weight_addr_full_w[14:0];
  assign classifier_param_we_w = param_we_i && (param_addr_i >= 9'(CONV5_CONV6_PARAM_COUNT));
  assign classifier_param_addr_full_w = param_addr_i - 9'(CONV5_CONV6_PARAM_COUNT);
  assign classifier_param_addr_w = classifier_param_addr_full_w[7:0];

  assign busy_o = (state_q != S_IDLE);
  assign done_o = classifier_done_w;
  assign output_valid_o = classifier_output_valid_w;
  assign output_last_o = classifier_output_last_w;
  assign output_index_o = classifier_output_index_w;
  assign acc_o = classifier_acc_w;
  assign data_o = classifier_data_w;

  assign debug_conv5_cycle_count_o = conv5_cycle_count_w;
  assign debug_conv5_tile_count_o = conv5_tile_count_w;
  assign debug_conv5_output_count_o = conv5_output_count_w;
  assign debug_conv6_cycle_count_o = conv6_cycle_count_w;
  assign debug_conv6_tile_count_o = conv6_tile_count_w;
  assign debug_conv6_output_count_o = conv6_output_count_w;
  assign debug_pool3_cycle_count_o = pool3_cycle_count_w;
  assign debug_pool3_output_count_o = pool3_output_count_w;
  assign debug_gap_cycle_count_o = gap_cycle_count_w;
  assign debug_gap_output_count_o = gap_output_count_w;
  assign debug_fc1_cycle_count_o = fc1_cycle_count_w;
  assign debug_fc1_output_count_o = fc1_output_count_w;
  assign debug_fc2_cycle_count_o = fc2_cycle_count_w;
  assign debug_fc2_output_count_o = fc2_output_count_w;

  animals10_conv5_conv6_pool3_systolic_4x4 u_conv_pool (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv_pool_start_q),
      .busy_o(conv_pool_busy_w),
      .done_o(conv_pool_done_w),
      .input_we_i(conv_pool_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(conv_pool_weight_we_w),
      .weight_addr_i(conv_pool_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv_pool_param_we_w),
      .param_addr_i(conv_pool_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv_pool_output_valid_w),
      .output_last_o(conv_pool_output_last_w),
      .output_index_o(conv_pool_output_index_w),
      .data_o(conv_pool_data_w),
      .debug_total_cycle_count_o(conv_pool_total_cycle_count_w),
      .debug_conv5_cycle_count_o(conv5_cycle_count_w),
      .debug_conv5_tile_count_o(conv5_tile_count_w),
      .debug_conv5_output_count_o(conv5_output_count_w),
      .debug_conv6_cycle_count_o(conv6_cycle_count_w),
      .debug_conv6_tile_count_o(conv6_tile_count_w),
      .debug_conv6_output_count_o(conv6_output_count_w),
      .debug_pool3_cycle_count_o(pool3_cycle_count_w),
      .debug_pool3_output_count_o(pool3_output_count_w)
  );

  animals10_gap_fc1_fc2_i8 u_classifier (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(classifier_start_q),
      .busy_o(classifier_busy_w),
      .done_o(classifier_done_w),
      .input_we_i(classifier_input_we_w),
      .input_addr_i(classifier_input_addr_w),
      .input_data_i(classifier_input_data_w),
      .weight_we_i(classifier_weight_we_w),
      .weight_addr_i(classifier_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(classifier_param_we_w),
      .param_addr_i(classifier_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(classifier_output_valid_w),
      .output_last_o(classifier_output_last_w),
      .output_index_o(classifier_output_index_w),
      .acc_o(classifier_acc_w),
      .data_o(classifier_data_w),
      .debug_total_cycle_count_o(classifier_total_cycle_count_w),
      .debug_gap_cycle_count_o(gap_cycle_count_w),
      .debug_gap_output_count_o(gap_output_count_w),
      .debug_fc1_cycle_count_o(fc1_cycle_count_w),
      .debug_fc1_output_count_o(fc1_output_count_w),
      .debug_fc2_cycle_count_o(fc2_cycle_count_w),
      .debug_fc2_output_count_o(fc2_output_count_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      conv_pool_start_q <= 1'b0;
      classifier_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
    end else begin
      conv_pool_start_q <= 1'b0;
      classifier_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            conv_pool_start_q <= 1'b1;
            state_q <= S_RUN_CONV_POOL;
          end
        end

        S_RUN_CONV_POOL: begin
          if (conv_pool_done_w) begin
            state_q <= S_START_CLASSIFIER;
          end
        end

        S_START_CLASSIFIER: begin
          classifier_start_q <= 1'b1;
          state_q <= S_RUN_CLASSIFIER;
        end

        S_RUN_CLASSIFIER: begin
          if (classifier_done_w) begin
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_conv5_conv6_pool3_gap_fc1_fc2_i8

`timescale 1ns / 1ps

// Staged Animals-10 V1 block: Conv1 -> Conv2 -> Pool1.
//
// This is an integration bring-up wrapper, not the final streaming top. It
// preserves the verified standalone Conv contracts and connects them through
// internal writeback memories so the next golden comparison is Pool1.
module animals10_conv1_conv2_pool1_systolic_4x4 (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [13:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [13:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [5:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [14:0] output_index_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_conv1_cycle_count_o,
    output logic [31:0] debug_conv1_tile_count_o,
    output logic [31:0] debug_conv1_output_count_o,
    output logic [31:0] debug_conv2_cycle_count_o,
    output logic [31:0] debug_conv2_tile_count_o,
    output logic [31:0] debug_conv2_output_count_o,
    output logic [31:0] debug_pool1_cycle_count_o,
    output logic [31:0] debug_pool1_output_count_o
);

  localparam int CONV1_WEIGHT_COUNT = 32 * 3 * 3 * 3;
  localparam int CONV2_PARAM_OFFSET = 32;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_CONV1,
    S_START_CONV2,
    S_RUN_CONV2,
    S_START_POOL1,
    S_RUN_POOL1
  } state_t;

  state_t state_q;

  logic conv1_start_q;
  logic conv1_busy_w;
  logic conv1_done_w;
  logic conv1_input_we_w;
  logic conv1_weight_we_w;
  logic [9:0] conv1_weight_addr_w;
  logic conv1_param_we_w;
  logic [4:0] conv1_param_addr_w;
  logic conv1_output_valid_w;
  logic conv1_output_last_w;
  logic [16:0] conv1_output_index_w;
  logic signed [31:0] conv1_acc_w;
  logic signed [7:0] conv1_data_w;
  logic [31:0] conv1_cycle_count_w;
  logic [31:0] conv1_tile_count_w;
  logic [31:0] conv1_output_count_w;

  logic conv2_start_q;
  logic conv2_busy_w;
  logic conv2_done_w;
  logic conv2_input_we_w;
  logic [16:0] conv2_input_addr_w;
  logic signed [7:0] conv2_input_data_w;
  logic conv2_weight_we_w;
  logic [13:0] conv2_weight_addr_w;
  logic conv2_param_we_w;
  logic [4:0] conv2_param_addr_w;
  logic conv2_output_valid_w;
  logic conv2_output_last_w;
  logic [16:0] conv2_output_index_w;
  logic signed [31:0] conv2_acc_w;
  logic signed [7:0] conv2_data_w;
  logic [31:0] conv2_cycle_count_w;
  logic [31:0] conv2_tile_count_w;
  logic [31:0] conv2_output_count_w;

  logic pool1_start_q;
  logic pool1_busy_w;
  logic pool1_done_w;
  logic pool1_input_we_w;
  logic [16:0] pool1_input_addr_w;
  logic signed [7:0] pool1_input_data_w;
  logic pool1_output_valid_w;
  logic pool1_output_last_w;
  logic [14:0] pool1_output_index_w;
  logic signed [7:0] pool1_data_w;
  logic [31:0] pool1_cycle_count_w;
  logic [31:0] pool1_output_count_w;

  assign conv1_input_we_w = input_we_i && (state_q == S_IDLE);
  assign conv1_weight_we_w = weight_we_i && (weight_addr_i < 14'(CONV1_WEIGHT_COUNT));
  assign conv1_weight_addr_w = weight_addr_i[9:0];
  assign conv1_param_we_w = param_we_i && (param_addr_i < 6'(CONV2_PARAM_OFFSET));
  assign conv1_param_addr_w = param_addr_i[4:0];

  assign conv2_input_we_w = conv1_output_valid_w;
  assign conv2_input_addr_w = conv1_output_index_w;
  assign conv2_input_data_w = conv1_data_w;
  assign conv2_weight_we_w = weight_we_i && (weight_addr_i >= 14'(CONV1_WEIGHT_COUNT));
  assign conv2_weight_addr_w = weight_addr_i - 14'(CONV1_WEIGHT_COUNT);
  assign conv2_param_we_w = param_we_i && (param_addr_i >= 6'(CONV2_PARAM_OFFSET));
  assign conv2_param_addr_w = param_addr_i[4:0];

  assign pool1_input_we_w = conv2_output_valid_w;
  assign pool1_input_addr_w = conv2_output_index_w;
  assign pool1_input_data_w = conv2_data_w;

  assign busy_o = (state_q != S_IDLE);
  assign done_o = pool1_done_w;
  assign output_valid_o = pool1_output_valid_w;
  assign output_last_o = pool1_output_last_w;
  assign output_index_o = pool1_output_index_w;
  assign data_o = pool1_data_w;

  assign debug_conv1_cycle_count_o = conv1_cycle_count_w;
  assign debug_conv1_tile_count_o = conv1_tile_count_w;
  assign debug_conv1_output_count_o = conv1_output_count_w;
  assign debug_conv2_cycle_count_o = conv2_cycle_count_w;
  assign debug_conv2_tile_count_o = conv2_tile_count_w;
  assign debug_conv2_output_count_o = conv2_output_count_w;
  assign debug_pool1_cycle_count_o = pool1_cycle_count_w;
  assign debug_pool1_output_count_o = pool1_output_count_w;

  animals10_conv1_systolic_4x4 u_conv1 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv1_start_q),
      .busy_o(conv1_busy_w),
      .done_o(conv1_done_w),
      .input_we_i(conv1_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(conv1_weight_we_w),
      .weight_addr_i(conv1_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv1_param_we_w),
      .param_addr_i(conv1_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv1_output_valid_w),
      .output_last_o(conv1_output_last_w),
      .output_index_o(conv1_output_index_w),
      .acc_o(conv1_acc_w),
      .data_o(conv1_data_w),
      .debug_cycle_count_o(conv1_cycle_count_w),
      .debug_tile_count_o(conv1_tile_count_w),
      .debug_output_count_o(conv1_output_count_w)
  );

  animals10_conv2_systolic_4x4 u_conv2 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv2_start_q),
      .busy_o(conv2_busy_w),
      .done_o(conv2_done_w),
      .input_we_i(conv2_input_we_w),
      .input_addr_i(conv2_input_addr_w),
      .input_data_i(conv2_input_data_w),
      .weight_we_i(conv2_weight_we_w),
      .weight_addr_i(conv2_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv2_param_we_w),
      .param_addr_i(conv2_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv2_output_valid_w),
      .output_last_o(conv2_output_last_w),
      .output_index_o(conv2_output_index_w),
      .acc_o(conv2_acc_w),
      .data_o(conv2_data_w),
      .debug_cycle_count_o(conv2_cycle_count_w),
      .debug_tile_count_o(conv2_tile_count_w),
      .debug_output_count_o(conv2_output_count_w)
  );

  animals10_maxpool2x2_i8 #(
      .IN_C(32),
      .IN_H(64),
      .IN_W(64),
      .POOL(2),
      .INPUT_ADDR_WIDTH(17),
      .OUTPUT_ADDR_WIDTH(15)
  ) u_pool1 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(pool1_start_q),
      .busy_o(pool1_busy_w),
      .done_o(pool1_done_w),
      .input_we_i(pool1_input_we_w),
      .input_addr_i(pool1_input_addr_w),
      .input_data_i(pool1_input_data_w),
      .output_valid_o(pool1_output_valid_w),
      .output_last_o(pool1_output_last_w),
      .output_index_o(pool1_output_index_w),
      .data_o(pool1_data_w),
      .debug_cycle_count_o(pool1_cycle_count_w),
      .debug_output_count_o(pool1_output_count_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      conv1_start_q <= 1'b0;
      conv2_start_q <= 1'b0;
      pool1_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
    end else begin
      conv1_start_q <= 1'b0;
      conv2_start_q <= 1'b0;
      pool1_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            conv1_start_q <= 1'b1;
            state_q <= S_RUN_CONV1;
          end
        end

        S_RUN_CONV1: begin
          if (conv1_done_w) begin
            state_q <= S_START_CONV2;
          end
        end

        S_START_CONV2: begin
          conv2_start_q <= 1'b1;
          state_q <= S_RUN_CONV2;
        end

        S_RUN_CONV2: begin
          if (conv2_done_w) begin
            state_q <= S_START_POOL1;
          end
        end

        S_START_POOL1: begin
          pool1_start_q <= 1'b1;
          state_q <= S_RUN_POOL1;
        end

        S_RUN_POOL1: begin
          if (pool1_done_w) begin
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_conv1_conv2_pool1_systolic_4x4

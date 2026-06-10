`timescale 1ns / 1ps

// Staged Animals-10 V1 block: Conv3 -> Conv4 -> Pool2.
//
// This integration wrapper preserves the standalone Conv3/Conv4 contracts and
// adds Pool2 as the second fused feature-map stage.
module animals10_conv3_conv4_pool2_systolic_4x4 (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [14:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [15:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [6:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [13:0] output_index_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_conv3_cycle_count_o,
    output logic [31:0] debug_conv3_tile_count_o,
    output logic [31:0] debug_conv3_output_count_o,
    output logic [31:0] debug_conv4_cycle_count_o,
    output logic [31:0] debug_conv4_tile_count_o,
    output logic [31:0] debug_conv4_output_count_o,
    output logic [31:0] debug_pool2_cycle_count_o,
    output logic [31:0] debug_pool2_output_count_o
);

  localparam int CONV3_WEIGHT_COUNT = 64 * 32 * 3 * 3;
  localparam int CONV4_PARAM_OFFSET = 64;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_CONV3,
    S_START_CONV4,
    S_RUN_CONV4,
    S_START_POOL2,
    S_RUN_POOL2
  } state_t;

  state_t state_q;

  logic conv3_start_q;
  logic conv3_busy_w;
  logic conv3_done_w;
  logic conv3_input_we_w;
  logic conv3_weight_we_w;
  logic [14:0] conv3_weight_addr_w;
  logic conv3_param_we_w;
  logic [5:0] conv3_param_addr_w;
  logic conv3_output_valid_w;
  logic conv3_output_last_w;
  logic [15:0] conv3_output_index_w;
  logic signed [31:0] conv3_acc_w;
  logic signed [7:0] conv3_data_w;
  logic [31:0] conv3_cycle_count_w;
  logic [31:0] conv3_tile_count_w;
  logic [31:0] conv3_output_count_w;

  logic conv4_start_q;
  logic conv4_busy_w;
  logic conv4_done_w;
  logic conv4_input_we_w;
  logic [15:0] conv4_input_addr_w;
  logic signed [7:0] conv4_input_data_w;
  logic conv4_weight_we_w;
  logic [15:0] conv4_weight_addr_w;
  logic conv4_param_we_w;
  logic [5:0] conv4_param_addr_w;
  logic conv4_output_valid_w;
  logic conv4_output_last_w;
  logic [15:0] conv4_output_index_w;
  logic signed [31:0] conv4_acc_w;
  logic signed [7:0] conv4_data_w;
  logic [31:0] conv4_cycle_count_w;
  logic [31:0] conv4_tile_count_w;
  logic [31:0] conv4_output_count_w;

  logic pool2_start_q;
  logic pool2_busy_w;
  logic pool2_done_w;
  logic pool2_input_we_w;
  logic [15:0] pool2_input_addr_w;
  logic signed [7:0] pool2_input_data_w;
  logic pool2_output_valid_w;
  logic pool2_output_last_w;
  logic [13:0] pool2_output_index_w;
  logic signed [7:0] pool2_data_w;
  logic [31:0] pool2_cycle_count_w;
  logic [31:0] pool2_output_count_w;

  assign conv3_input_we_w = input_we_i && (state_q == S_IDLE);
  assign conv3_weight_we_w = weight_we_i && (weight_addr_i < 16'(CONV3_WEIGHT_COUNT));
  assign conv3_weight_addr_w = weight_addr_i[14:0];
  assign conv3_param_we_w = param_we_i && (param_addr_i < 7'(CONV4_PARAM_OFFSET));
  assign conv3_param_addr_w = param_addr_i[5:0];

  assign conv4_input_we_w = conv3_output_valid_w;
  assign conv4_input_addr_w = conv3_output_index_w;
  assign conv4_input_data_w = conv3_data_w;
  assign conv4_weight_we_w = weight_we_i && (weight_addr_i >= 16'(CONV3_WEIGHT_COUNT));
  assign conv4_weight_addr_w = weight_addr_i - 16'(CONV3_WEIGHT_COUNT);
  assign conv4_param_we_w = param_we_i && (param_addr_i >= 7'(CONV4_PARAM_OFFSET));
  assign conv4_param_addr_w = param_addr_i[5:0];

  assign pool2_input_we_w = conv4_output_valid_w;
  assign pool2_input_addr_w = conv4_output_index_w;
  assign pool2_input_data_w = conv4_data_w;

  assign busy_o = (state_q != S_IDLE);
  assign done_o = pool2_done_w;
  assign output_valid_o = pool2_output_valid_w;
  assign output_last_o = pool2_output_last_w;
  assign output_index_o = pool2_output_index_w;
  assign data_o = pool2_data_w;

  assign debug_conv3_cycle_count_o = conv3_cycle_count_w;
  assign debug_conv3_tile_count_o = conv3_tile_count_w;
  assign debug_conv3_output_count_o = conv3_output_count_w;
  assign debug_conv4_cycle_count_o = conv4_cycle_count_w;
  assign debug_conv4_tile_count_o = conv4_tile_count_w;
  assign debug_conv4_output_count_o = conv4_output_count_w;
  assign debug_pool2_cycle_count_o = pool2_cycle_count_w;
  assign debug_pool2_output_count_o = pool2_output_count_w;

  animals10_conv3_systolic_4x4 u_conv3 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv3_start_q),
      .busy_o(conv3_busy_w),
      .done_o(conv3_done_w),
      .input_we_i(conv3_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(conv3_weight_we_w),
      .weight_addr_i(conv3_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv3_param_we_w),
      .param_addr_i(conv3_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv3_output_valid_w),
      .output_last_o(conv3_output_last_w),
      .output_index_o(conv3_output_index_w),
      .acc_o(conv3_acc_w),
      .data_o(conv3_data_w),
      .debug_cycle_count_o(conv3_cycle_count_w),
      .debug_tile_count_o(conv3_tile_count_w),
      .debug_output_count_o(conv3_output_count_w)
  );

  animals10_conv4_systolic_4x4 u_conv4 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv4_start_q),
      .busy_o(conv4_busy_w),
      .done_o(conv4_done_w),
      .input_we_i(conv4_input_we_w),
      .input_addr_i(conv4_input_addr_w),
      .input_data_i(conv4_input_data_w),
      .weight_we_i(conv4_weight_we_w),
      .weight_addr_i(conv4_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv4_param_we_w),
      .param_addr_i(conv4_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv4_output_valid_w),
      .output_last_o(conv4_output_last_w),
      .output_index_o(conv4_output_index_w),
      .acc_o(conv4_acc_w),
      .data_o(conv4_data_w),
      .debug_cycle_count_o(conv4_cycle_count_w),
      .debug_tile_count_o(conv4_tile_count_w),
      .debug_output_count_o(conv4_output_count_w)
  );

  animals10_maxpool2x2_i8 #(
      .IN_C(64),
      .IN_H(32),
      .IN_W(32),
      .POOL(2),
      .INPUT_ADDR_WIDTH(16),
      .OUTPUT_ADDR_WIDTH(14)
  ) u_pool2 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(pool2_start_q),
      .busy_o(pool2_busy_w),
      .done_o(pool2_done_w),
      .input_we_i(pool2_input_we_w),
      .input_addr_i(pool2_input_addr_w),
      .input_data_i(pool2_input_data_w),
      .output_valid_o(pool2_output_valid_w),
      .output_last_o(pool2_output_last_w),
      .output_index_o(pool2_output_index_w),
      .data_o(pool2_data_w),
      .debug_cycle_count_o(pool2_cycle_count_w),
      .debug_output_count_o(pool2_output_count_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      conv3_start_q <= 1'b0;
      conv4_start_q <= 1'b0;
      pool2_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
    end else begin
      conv3_start_q <= 1'b0;
      conv4_start_q <= 1'b0;
      pool2_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            conv3_start_q <= 1'b1;
            state_q <= S_RUN_CONV3;
          end
        end

        S_RUN_CONV3: begin
          if (conv3_done_w) begin
            state_q <= S_START_CONV4;
          end
        end

        S_START_CONV4: begin
          conv4_start_q <= 1'b1;
          state_q <= S_RUN_CONV4;
        end

        S_RUN_CONV4: begin
          if (conv4_done_w) begin
            state_q <= S_START_POOL2;
          end
        end

        S_START_POOL2: begin
          pool2_start_q <= 1'b1;
          state_q <= S_RUN_POOL2;
        end

        S_RUN_POOL2: begin
          if (pool2_done_w) begin
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_conv3_conv4_pool2_systolic_4x4

`timescale 1ns / 1ps

// Staged Animals-10 V1 block: Conv5 -> Conv6 -> Pool3.
//
// This integration wrapper preserves the standalone Conv5/Conv6 contracts and
// adds Pool3 as the final convolution feature-map stage.
module animals10_conv5_conv6_pool3_systolic_4x4 (
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
    input logic [7:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [12:0] output_index_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_conv5_cycle_count_o,
    output logic [31:0] debug_conv5_tile_count_o,
    output logic [31:0] debug_conv5_output_count_o,
    output logic [31:0] debug_conv6_cycle_count_o,
    output logic [31:0] debug_conv6_tile_count_o,
    output logic [31:0] debug_conv6_output_count_o,
    output logic [31:0] debug_pool3_cycle_count_o,
    output logic [31:0] debug_pool3_output_count_o
);

  localparam int CONV5_WEIGHT_COUNT = 128 * 64 * 3 * 3;
  localparam int CONV6_PARAM_OFFSET = 128;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_CONV5,
    S_START_CONV6,
    S_RUN_CONV6,
    S_START_POOL3,
    S_RUN_POOL3
  } state_t;

  state_t state_q;

  logic conv5_start_q;
  logic conv5_busy_w;
  logic conv5_done_w;
  logic conv5_input_we_w;
  logic conv5_weight_we_w;
  logic [16:0] conv5_weight_addr_w;
  logic conv5_param_we_w;
  logic [6:0] conv5_param_addr_w;
  logic conv5_output_valid_w;
  logic conv5_output_last_w;
  logic [14:0] conv5_output_index_w;
  logic signed [31:0] conv5_acc_w;
  logic signed [7:0] conv5_data_w;
  logic [31:0] conv5_cycle_count_w;
  logic [31:0] conv5_tile_count_w;
  logic [31:0] conv5_output_count_w;

  logic conv6_start_q;
  logic conv6_busy_w;
  logic conv6_done_w;
  logic conv6_input_we_w;
  logic [14:0] conv6_input_addr_w;
  logic signed [7:0] conv6_input_data_w;
  logic conv6_weight_we_w;
  logic [17:0] conv6_weight_addr_w;
  logic conv6_param_we_w;
  logic [6:0] conv6_param_addr_w;
  logic conv6_output_valid_w;
  logic conv6_output_last_w;
  logic [14:0] conv6_output_index_w;
  logic signed [31:0] conv6_acc_w;
  logic signed [7:0] conv6_data_w;
  logic [31:0] conv6_cycle_count_w;
  logic [31:0] conv6_tile_count_w;
  logic [31:0] conv6_output_count_w;

  logic pool3_start_q;
  logic pool3_busy_w;
  logic pool3_done_w;
  logic pool3_input_we_w;
  logic [14:0] pool3_input_addr_w;
  logic signed [7:0] pool3_input_data_w;
  logic pool3_output_valid_w;
  logic pool3_output_last_w;
  logic [12:0] pool3_output_index_w;
  logic signed [7:0] pool3_data_w;
  logic [31:0] pool3_cycle_count_w;
  logic [31:0] pool3_output_count_w;

  assign conv5_input_we_w = input_we_i && (state_q == S_IDLE);
  assign conv5_weight_we_w = weight_we_i && (weight_addr_i < 18'(CONV5_WEIGHT_COUNT));
  assign conv5_weight_addr_w = weight_addr_i[16:0];
  assign conv5_param_we_w = param_we_i && (param_addr_i < 8'(CONV6_PARAM_OFFSET));
  assign conv5_param_addr_w = param_addr_i[6:0];

  assign conv6_input_we_w = conv5_output_valid_w;
  assign conv6_input_addr_w = conv5_output_index_w;
  assign conv6_input_data_w = conv5_data_w;
  assign conv6_weight_we_w = weight_we_i && (weight_addr_i >= 18'(CONV5_WEIGHT_COUNT));
  assign conv6_weight_addr_w = weight_addr_i - 18'(CONV5_WEIGHT_COUNT);
  assign conv6_param_we_w = param_we_i && (param_addr_i >= 8'(CONV6_PARAM_OFFSET));
  assign conv6_param_addr_w = param_addr_i[6:0];

  assign pool3_input_we_w = conv6_output_valid_w;
  assign pool3_input_addr_w = conv6_output_index_w;
  assign pool3_input_data_w = conv6_data_w;

  assign busy_o = (state_q != S_IDLE);
  assign done_o = pool3_done_w;
  assign output_valid_o = pool3_output_valid_w;
  assign output_last_o = pool3_output_last_w;
  assign output_index_o = pool3_output_index_w;
  assign data_o = pool3_data_w;

  assign debug_conv5_cycle_count_o = conv5_cycle_count_w;
  assign debug_conv5_tile_count_o = conv5_tile_count_w;
  assign debug_conv5_output_count_o = conv5_output_count_w;
  assign debug_conv6_cycle_count_o = conv6_cycle_count_w;
  assign debug_conv6_tile_count_o = conv6_tile_count_w;
  assign debug_conv6_output_count_o = conv6_output_count_w;
  assign debug_pool3_cycle_count_o = pool3_cycle_count_w;
  assign debug_pool3_output_count_o = pool3_output_count_w;

  animals10_conv5_systolic_4x4 u_conv5 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv5_start_q),
      .busy_o(conv5_busy_w),
      .done_o(conv5_done_w),
      .input_we_i(conv5_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(conv5_weight_we_w),
      .weight_addr_i(conv5_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv5_param_we_w),
      .param_addr_i(conv5_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv5_output_valid_w),
      .output_last_o(conv5_output_last_w),
      .output_index_o(conv5_output_index_w),
      .acc_o(conv5_acc_w),
      .data_o(conv5_data_w),
      .debug_cycle_count_o(conv5_cycle_count_w),
      .debug_tile_count_o(conv5_tile_count_w),
      .debug_output_count_o(conv5_output_count_w)
  );

  animals10_conv6_systolic_4x4 u_conv6 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(conv6_start_q),
      .busy_o(conv6_busy_w),
      .done_o(conv6_done_w),
      .input_we_i(conv6_input_we_w),
      .input_addr_i(conv6_input_addr_w),
      .input_data_i(conv6_input_data_w),
      .weight_we_i(conv6_weight_we_w),
      .weight_addr_i(conv6_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(conv6_param_we_w),
      .param_addr_i(conv6_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(conv6_output_valid_w),
      .output_last_o(conv6_output_last_w),
      .output_index_o(conv6_output_index_w),
      .acc_o(conv6_acc_w),
      .data_o(conv6_data_w),
      .debug_cycle_count_o(conv6_cycle_count_w),
      .debug_tile_count_o(conv6_tile_count_w),
      .debug_output_count_o(conv6_output_count_w)
  );

  animals10_maxpool2x2_i8 #(
      .IN_C(128),
      .IN_H(16),
      .IN_W(16),
      .POOL(2),
      .INPUT_ADDR_WIDTH(15),
      .OUTPUT_ADDR_WIDTH(13)
  ) u_pool3 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(pool3_start_q),
      .busy_o(pool3_busy_w),
      .done_o(pool3_done_w),
      .input_we_i(pool3_input_we_w),
      .input_addr_i(pool3_input_addr_w),
      .input_data_i(pool3_input_data_w),
      .output_valid_o(pool3_output_valid_w),
      .output_last_o(pool3_output_last_w),
      .output_index_o(pool3_output_index_w),
      .data_o(pool3_data_w),
      .debug_cycle_count_o(pool3_cycle_count_w),
      .debug_output_count_o(pool3_output_count_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      conv5_start_q <= 1'b0;
      conv6_start_q <= 1'b0;
      pool3_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
    end else begin
      conv5_start_q <= 1'b0;
      conv6_start_q <= 1'b0;
      pool3_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            conv5_start_q <= 1'b1;
            state_q <= S_RUN_CONV5;
          end
        end

        S_RUN_CONV5: begin
          if (conv5_done_w) begin
            state_q <= S_START_CONV6;
          end
        end

        S_START_CONV6: begin
          conv6_start_q <= 1'b1;
          state_q <= S_RUN_CONV6;
        end

        S_RUN_CONV6: begin
          if (conv6_done_w) begin
            state_q <= S_START_POOL3;
          end
        end

        S_START_POOL3: begin
          pool3_start_q <= 1'b1;
          state_q <= S_RUN_POOL3;
        end

        S_RUN_POOL3: begin
          if (pool3_done_w) begin
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_conv5_conv6_pool3_systolic_4x4

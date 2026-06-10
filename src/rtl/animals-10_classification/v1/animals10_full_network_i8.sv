`timescale 1ns / 1ps

// Animals-10 V1 full case-0 network:
// Conv1 -> Conv2 -> Pool1 -> Conv3 -> Conv4 -> Pool2
// -> Conv5 -> Conv6 -> Pool3 -> GAP -> FC1 -> FC2.
//
// This is a correctness bring-up top built from already-validated staged
// blocks. The later production top can replace the staged memories with shared
// UB/weight infrastructure after the full arithmetic contract is locked.
module animals10_full_network_i8 (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [13:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [18:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [9:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [3:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_stage1_cycle_count_o,
    output logic [31:0] debug_stage2_cycle_count_o,
    output logic [31:0] debug_stage3_cycle_count_o,
    output logic [31:0] debug_conv1_cycle_count_o,
    output logic [31:0] debug_conv1_tile_count_o,
    output logic [31:0] debug_conv1_output_count_o,
    output logic [31:0] debug_conv2_cycle_count_o,
    output logic [31:0] debug_conv2_tile_count_o,
    output logic [31:0] debug_conv2_output_count_o,
    output logic [31:0] debug_pool1_cycle_count_o,
    output logic [31:0] debug_pool1_output_count_o,
    output logic [31:0] debug_conv3_cycle_count_o,
    output logic [31:0] debug_conv3_tile_count_o,
    output logic [31:0] debug_conv3_output_count_o,
    output logic [31:0] debug_conv4_cycle_count_o,
    output logic [31:0] debug_conv4_tile_count_o,
    output logic [31:0] debug_conv4_output_count_o,
    output logic [31:0] debug_pool2_cycle_count_o,
    output logic [31:0] debug_pool2_output_count_o,
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

  localparam int STAGE1_WEIGHT_COUNT = (32 * 3 * 3 * 3) + (32 * 32 * 3 * 3);
  localparam int STAGE2_WEIGHT_COUNT = (64 * 32 * 3 * 3) + (64 * 64 * 3 * 3);
  localparam int STAGE3_WEIGHT_OFFSET = STAGE1_WEIGHT_COUNT + STAGE2_WEIGHT_COUNT;
  localparam int STAGE1_PARAM_COUNT = 64;
  localparam int STAGE2_PARAM_COUNT = 128;
  localparam int STAGE3_PARAM_OFFSET = STAGE1_PARAM_COUNT + STAGE2_PARAM_COUNT;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_STAGE1,
    S_START_STAGE2,
    S_RUN_STAGE2,
    S_START_STAGE3,
    S_RUN_STAGE3
  } state_t;

  state_t state_q;

  logic stage1_start_q;
  logic stage1_busy_w;
  logic stage1_done_w;
  logic stage1_input_we_w;
  logic stage1_weight_we_w;
  logic [13:0] stage1_weight_addr_w;
  logic stage1_param_we_w;
  logic [5:0] stage1_param_addr_w;
  logic stage1_output_valid_w;
  logic stage1_output_last_w;
  logic [14:0] stage1_output_index_w;
  logic signed [7:0] stage1_data_w;
  logic [31:0] stage1_cycle_count_w;
  logic [31:0] stage1_cycle_count_latched_q;
  logic [31:0] conv1_cycle_count_w;
  logic [31:0] conv1_tile_count_w;
  logic [31:0] conv1_output_count_w;
  logic [31:0] conv2_cycle_count_w;
  logic [31:0] conv2_tile_count_w;
  logic [31:0] conv2_output_count_w;
  logic [31:0] pool1_cycle_count_w;
  logic [31:0] pool1_output_count_w;

  logic stage2_start_q;
  logic stage2_busy_w;
  logic stage2_done_w;
  logic stage2_input_we_w;
  logic [14:0] stage2_input_addr_w;
  logic signed [7:0] stage2_input_data_w;
  logic stage2_weight_we_w;
  logic [18:0] stage2_weight_addr_full_w;
  logic [15:0] stage2_weight_addr_w;
  logic stage2_param_we_w;
  logic [9:0] stage2_param_addr_full_w;
  logic [6:0] stage2_param_addr_w;
  logic stage2_output_valid_w;
  logic stage2_output_last_w;
  logic [13:0] stage2_output_index_w;
  logic signed [7:0] stage2_data_w;
  logic [31:0] stage2_cycle_count_w;
  logic [31:0] stage2_cycle_count_latched_q;
  logic [31:0] conv3_cycle_count_w;
  logic [31:0] conv3_tile_count_w;
  logic [31:0] conv3_output_count_w;
  logic [31:0] conv4_cycle_count_w;
  logic [31:0] conv4_tile_count_w;
  logic [31:0] conv4_output_count_w;
  logic [31:0] pool2_cycle_count_w;
  logic [31:0] pool2_output_count_w;

  logic stage3_start_q;
  logic stage3_busy_w;
  logic stage3_done_w;
  logic stage3_input_we_w;
  logic [13:0] stage3_input_addr_w;
  logic signed [7:0] stage3_input_data_w;
  logic stage3_weight_we_w;
  logic [18:0] stage3_weight_addr_full_w;
  logic [17:0] stage3_weight_addr_w;
  logic stage3_param_we_w;
  logic [9:0] stage3_param_addr_full_w;
  logic [8:0] stage3_param_addr_w;
  logic stage3_output_valid_w;
  logic stage3_output_last_w;
  logic [3:0] stage3_output_index_w;
  logic signed [31:0] stage3_acc_w;
  logic signed [7:0] stage3_data_w;
  logic [31:0] stage3_cycle_count_w;
  logic [31:0] stage3_cycle_count_latched_q;
  logic [31:0] conv5_cycle_count_w;
  logic [31:0] conv5_tile_count_w;
  logic [31:0] conv5_output_count_w;
  logic [31:0] conv6_cycle_count_w;
  logic [31:0] conv6_tile_count_w;
  logic [31:0] conv6_output_count_w;
  logic [31:0] pool3_cycle_count_w;
  logic [31:0] pool3_output_count_w;
  logic [31:0] gap_cycle_count_w;
  logic [31:0] gap_output_count_w;
  logic [31:0] fc1_cycle_count_w;
  logic [31:0] fc1_output_count_w;
  logic [31:0] fc2_cycle_count_w;
  logic [31:0] fc2_output_count_w;

  assign stage1_input_we_w = input_we_i && (state_q == S_IDLE);
  assign stage1_weight_we_w = weight_we_i && (weight_addr_i < 19'(STAGE1_WEIGHT_COUNT));
  assign stage1_weight_addr_w = weight_addr_i[13:0];
  assign stage1_param_we_w = param_we_i && (param_addr_i < 10'(STAGE1_PARAM_COUNT));
  assign stage1_param_addr_w = param_addr_i[5:0];

  assign stage2_input_we_w = stage1_output_valid_w;
  assign stage2_input_addr_w = stage1_output_index_w;
  assign stage2_input_data_w = stage1_data_w;
  assign stage2_weight_addr_full_w = weight_addr_i - 19'(STAGE1_WEIGHT_COUNT);
  assign stage2_weight_we_w =
      weight_we_i
      && (weight_addr_i >= 19'(STAGE1_WEIGHT_COUNT))
      && (weight_addr_i < 19'(STAGE3_WEIGHT_OFFSET));
  assign stage2_weight_addr_w = stage2_weight_addr_full_w[15:0];
  assign stage2_param_addr_full_w = param_addr_i - 10'(STAGE1_PARAM_COUNT);
  assign stage2_param_we_w =
      param_we_i
      && (param_addr_i >= 10'(STAGE1_PARAM_COUNT))
      && (param_addr_i < 10'(STAGE3_PARAM_OFFSET));
  assign stage2_param_addr_w = stage2_param_addr_full_w[6:0];

  assign stage3_input_we_w = stage2_output_valid_w;
  assign stage3_input_addr_w = stage2_output_index_w;
  assign stage3_input_data_w = stage2_data_w;
  assign stage3_weight_addr_full_w = weight_addr_i - 19'(STAGE3_WEIGHT_OFFSET);
  assign stage3_weight_we_w = weight_we_i && (weight_addr_i >= 19'(STAGE3_WEIGHT_OFFSET));
  assign stage3_weight_addr_w = stage3_weight_addr_full_w[17:0];
  assign stage3_param_addr_full_w = param_addr_i - 10'(STAGE3_PARAM_OFFSET);
  assign stage3_param_we_w = param_we_i && (param_addr_i >= 10'(STAGE3_PARAM_OFFSET));
  assign stage3_param_addr_w = stage3_param_addr_full_w[8:0];

  assign busy_o = (state_q != S_IDLE);
  assign done_o = stage3_done_w;
  assign output_valid_o = stage3_output_valid_w;
  assign output_last_o = stage3_output_last_w;
  assign output_index_o = stage3_output_index_w;
  assign acc_o = stage3_acc_w;
  assign data_o = stage3_data_w;

  assign debug_stage1_cycle_count_o = stage1_cycle_count_latched_q;
  assign debug_stage2_cycle_count_o = stage2_cycle_count_latched_q;
  assign debug_stage3_cycle_count_o = stage3_cycle_count_latched_q;
  assign debug_conv1_cycle_count_o = conv1_cycle_count_w;
  assign debug_conv1_tile_count_o = conv1_tile_count_w;
  assign debug_conv1_output_count_o = conv1_output_count_w;
  assign debug_conv2_cycle_count_o = conv2_cycle_count_w;
  assign debug_conv2_tile_count_o = conv2_tile_count_w;
  assign debug_conv2_output_count_o = conv2_output_count_w;
  assign debug_pool1_cycle_count_o = pool1_cycle_count_w;
  assign debug_pool1_output_count_o = pool1_output_count_w;
  assign debug_conv3_cycle_count_o = conv3_cycle_count_w;
  assign debug_conv3_tile_count_o = conv3_tile_count_w;
  assign debug_conv3_output_count_o = conv3_output_count_w;
  assign debug_conv4_cycle_count_o = conv4_cycle_count_w;
  assign debug_conv4_tile_count_o = conv4_tile_count_w;
  assign debug_conv4_output_count_o = conv4_output_count_w;
  assign debug_pool2_cycle_count_o = pool2_cycle_count_w;
  assign debug_pool2_output_count_o = pool2_output_count_w;
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

  animals10_conv1_conv2_pool1_systolic_4x4 u_stage1 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(stage1_start_q),
      .busy_o(stage1_busy_w),
      .done_o(stage1_done_w),
      .input_we_i(stage1_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(stage1_weight_we_w),
      .weight_addr_i(stage1_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(stage1_param_we_w),
      .param_addr_i(stage1_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(stage1_output_valid_w),
      .output_last_o(stage1_output_last_w),
      .output_index_o(stage1_output_index_w),
      .data_o(stage1_data_w),
      .debug_total_cycle_count_o(stage1_cycle_count_w),
      .debug_conv1_cycle_count_o(conv1_cycle_count_w),
      .debug_conv1_tile_count_o(conv1_tile_count_w),
      .debug_conv1_output_count_o(conv1_output_count_w),
      .debug_conv2_cycle_count_o(conv2_cycle_count_w),
      .debug_conv2_tile_count_o(conv2_tile_count_w),
      .debug_conv2_output_count_o(conv2_output_count_w),
      .debug_pool1_cycle_count_o(pool1_cycle_count_w),
      .debug_pool1_output_count_o(pool1_output_count_w)
  );

  animals10_conv3_conv4_pool2_systolic_4x4 u_stage2 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(stage2_start_q),
      .busy_o(stage2_busy_w),
      .done_o(stage2_done_w),
      .input_we_i(stage2_input_we_w),
      .input_addr_i(stage2_input_addr_w),
      .input_data_i(stage2_input_data_w),
      .weight_we_i(stage2_weight_we_w),
      .weight_addr_i(stage2_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(stage2_param_we_w),
      .param_addr_i(stage2_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(stage2_output_valid_w),
      .output_last_o(stage2_output_last_w),
      .output_index_o(stage2_output_index_w),
      .data_o(stage2_data_w),
      .debug_total_cycle_count_o(stage2_cycle_count_w),
      .debug_conv3_cycle_count_o(conv3_cycle_count_w),
      .debug_conv3_tile_count_o(conv3_tile_count_w),
      .debug_conv3_output_count_o(conv3_output_count_w),
      .debug_conv4_cycle_count_o(conv4_cycle_count_w),
      .debug_conv4_tile_count_o(conv4_tile_count_w),
      .debug_conv4_output_count_o(conv4_output_count_w),
      .debug_pool2_cycle_count_o(pool2_cycle_count_w),
      .debug_pool2_output_count_o(pool2_output_count_w)
  );

  animals10_conv5_conv6_pool3_gap_fc1_fc2_i8 u_stage3 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(stage3_start_q),
      .busy_o(stage3_busy_w),
      .done_o(stage3_done_w),
      .input_we_i(stage3_input_we_w),
      .input_addr_i(stage3_input_addr_w),
      .input_data_i(stage3_input_data_w),
      .weight_we_i(stage3_weight_we_w),
      .weight_addr_i(stage3_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(stage3_param_we_w),
      .param_addr_i(stage3_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(stage3_output_valid_w),
      .output_last_o(stage3_output_last_w),
      .output_index_o(stage3_output_index_w),
      .acc_o(stage3_acc_w),
      .data_o(stage3_data_w),
      .debug_total_cycle_count_o(stage3_cycle_count_w),
      .debug_conv5_cycle_count_o(conv5_cycle_count_w),
      .debug_conv5_tile_count_o(conv5_tile_count_w),
      .debug_conv5_output_count_o(conv5_output_count_w),
      .debug_conv6_cycle_count_o(conv6_cycle_count_w),
      .debug_conv6_tile_count_o(conv6_tile_count_w),
      .debug_conv6_output_count_o(conv6_output_count_w),
      .debug_pool3_cycle_count_o(pool3_cycle_count_w),
      .debug_pool3_output_count_o(pool3_output_count_w),
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
      stage1_start_q <= 1'b0;
      stage2_start_q <= 1'b0;
      stage3_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
      stage1_cycle_count_latched_q <= '0;
      stage2_cycle_count_latched_q <= '0;
      stage3_cycle_count_latched_q <= '0;
    end else begin
      stage1_start_q <= 1'b0;
      stage2_start_q <= 1'b0;
      stage3_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            stage1_start_q <= 1'b1;
            stage1_cycle_count_latched_q <= '0;
            stage2_cycle_count_latched_q <= '0;
            stage3_cycle_count_latched_q <= '0;
            state_q <= S_RUN_STAGE1;
          end
        end

        S_RUN_STAGE1: begin
          if (stage1_done_w) begin
            stage1_cycle_count_latched_q <= stage1_cycle_count_w;
            state_q <= S_START_STAGE2;
          end
        end

        S_START_STAGE2: begin
          stage2_start_q <= 1'b1;
          state_q <= S_RUN_STAGE2;
        end

        S_RUN_STAGE2: begin
          if (stage2_done_w) begin
            stage2_cycle_count_latched_q <= stage2_cycle_count_w;
            state_q <= S_START_STAGE3;
          end
        end

        S_START_STAGE3: begin
          stage3_start_q <= 1'b1;
          state_q <= S_RUN_STAGE3;
        end

        S_RUN_STAGE3: begin
          if (stage3_done_w) begin
            stage3_cycle_count_latched_q <= stage3_cycle_count_w;
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_full_network_i8

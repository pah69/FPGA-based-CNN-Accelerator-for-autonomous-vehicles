`timescale 1ns / 1ps

// Staged Animals-10 V1 classifier tail: GAP -> FC1 -> FC2.
//
// This wrapper preserves the standalone GAP/FC contracts while validating the
// stream handoff before the classifier tail is connected to the full network.
module animals10_gap_fc1_fc2_i8 (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [12:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [14:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [7:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [3:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_total_cycle_count_o,
    output logic [31:0] debug_gap_cycle_count_o,
    output logic [31:0] debug_gap_output_count_o,
    output logic [31:0] debug_fc1_cycle_count_o,
    output logic [31:0] debug_fc1_output_count_o,
    output logic [31:0] debug_fc2_cycle_count_o,
    output logic [31:0] debug_fc2_output_count_o
);

  localparam int FC1_WEIGHT_COUNT = 128 * 128;
  localparam int FC1_PARAM_COUNT = 128;

  typedef enum logic [2:0] {
    S_IDLE,
    S_RUN_GAP,
    S_START_FC1,
    S_RUN_FC1,
    S_START_FC2,
    S_RUN_FC2
  } state_t;

  state_t state_q;

  logic gap_start_q;
  logic gap_busy_w;
  logic gap_done_w;
  logic gap_input_we_w;
  logic gap_output_valid_w;
  logic gap_output_last_w;
  logic [6:0] gap_output_index_w;
  logic signed [7:0] gap_data_w;
  logic [31:0] gap_cycle_count_w;
  logic [31:0] gap_output_count_w;

  logic fc1_start_q;
  logic fc1_busy_w;
  logic fc1_done_w;
  logic fc1_input_we_w;
  logic [6:0] fc1_input_addr_w;
  logic signed [7:0] fc1_input_data_w;
  logic fc1_weight_we_w;
  logic [13:0] fc1_weight_addr_w;
  logic fc1_param_we_w;
  logic [6:0] fc1_param_addr_w;
  logic fc1_output_valid_w;
  logic fc1_output_last_w;
  logic [6:0] fc1_output_index_w;
  logic signed [31:0] fc1_acc_w;
  logic signed [7:0] fc1_data_w;
  logic [31:0] fc1_cycle_count_w;
  logic [31:0] fc1_output_count_w;

  logic fc2_start_q;
  logic fc2_busy_w;
  logic fc2_done_w;
  logic fc2_input_we_w;
  logic [6:0] fc2_input_addr_w;
  logic signed [7:0] fc2_input_data_w;
  logic fc2_weight_we_w;
  logic [10:0] fc2_weight_addr_w;
  logic fc2_param_we_w;
  logic [3:0] fc2_param_addr_w;
  logic fc2_output_valid_w;
  logic fc2_output_last_w;
  logic [3:0] fc2_output_index_w;
  logic signed [31:0] fc2_acc_w;
  logic signed [7:0] fc2_data_w;
  logic [31:0] fc2_cycle_count_w;
  logic [31:0] fc2_output_count_w;

  assign gap_input_we_w = input_we_i && (state_q == S_IDLE);

  assign fc1_input_we_w = gap_output_valid_w;
  assign fc1_input_addr_w = gap_output_index_w;
  assign fc1_input_data_w = gap_data_w;
  assign fc1_weight_we_w = weight_we_i && (weight_addr_i < 15'(FC1_WEIGHT_COUNT));
  assign fc1_weight_addr_w = weight_addr_i[13:0];
  assign fc1_param_we_w = param_we_i && (param_addr_i < 8'(FC1_PARAM_COUNT));
  assign fc1_param_addr_w = param_addr_i[6:0];

  assign fc2_input_we_w = fc1_output_valid_w;
  assign fc2_input_addr_w = fc1_output_index_w;
  assign fc2_input_data_w = fc1_data_w;
  assign fc2_weight_we_w = weight_we_i && (weight_addr_i >= 15'(FC1_WEIGHT_COUNT));
  assign fc2_weight_addr_w = weight_addr_i - 15'(FC1_WEIGHT_COUNT);
  assign fc2_param_we_w = param_we_i && (param_addr_i >= 8'(FC1_PARAM_COUNT));
  assign fc2_param_addr_w = param_addr_i - 8'(FC1_PARAM_COUNT);

  assign busy_o = (state_q != S_IDLE);
  assign done_o = fc2_done_w;
  assign output_valid_o = fc2_output_valid_w;
  assign output_last_o = fc2_output_last_w;
  assign output_index_o = fc2_output_index_w;
  assign acc_o = fc2_acc_w;
  assign data_o = fc2_data_w;

  assign debug_gap_cycle_count_o = gap_cycle_count_w;
  assign debug_gap_output_count_o = gap_output_count_w;
  assign debug_fc1_cycle_count_o = fc1_cycle_count_w;
  assign debug_fc1_output_count_o = fc1_output_count_w;
  assign debug_fc2_cycle_count_o = fc2_cycle_count_w;
  assign debug_fc2_output_count_o = fc2_output_count_w;

  animals10_gap_i8 u_gap (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(gap_start_q),
      .busy_o(gap_busy_w),
      .done_o(gap_done_w),
      .input_we_i(gap_input_we_w),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .output_valid_o(gap_output_valid_w),
      .output_last_o(gap_output_last_w),
      .output_index_o(gap_output_index_w),
      .data_o(gap_data_w),
      .debug_cycle_count_o(gap_cycle_count_w),
      .debug_output_count_o(gap_output_count_w)
  );

  animals10_fc1_i8 u_fc1 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(fc1_start_q),
      .busy_o(fc1_busy_w),
      .done_o(fc1_done_w),
      .input_we_i(fc1_input_we_w),
      .input_addr_i(fc1_input_addr_w),
      .input_data_i(fc1_input_data_w),
      .weight_we_i(fc1_weight_we_w),
      .weight_addr_i(fc1_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(fc1_param_we_w),
      .param_addr_i(fc1_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(fc1_output_valid_w),
      .output_last_o(fc1_output_last_w),
      .output_index_o(fc1_output_index_w),
      .acc_o(fc1_acc_w),
      .data_o(fc1_data_w),
      .debug_cycle_count_o(fc1_cycle_count_w),
      .debug_output_count_o(fc1_output_count_w)
  );

  animals10_fc2_i8 u_fc2 (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(fc2_start_q),
      .busy_o(fc2_busy_w),
      .done_o(fc2_done_w),
      .input_we_i(fc2_input_we_w),
      .input_addr_i(fc2_input_addr_w),
      .input_data_i(fc2_input_data_w),
      .weight_we_i(fc2_weight_we_w),
      .weight_addr_i(fc2_weight_addr_w),
      .weight_data_i(weight_data_i),
      .param_we_i(fc2_param_we_w),
      .param_addr_i(fc2_param_addr_w),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(fc2_output_valid_w),
      .output_last_o(fc2_output_last_w),
      .output_index_o(fc2_output_index_w),
      .acc_o(fc2_acc_w),
      .data_o(fc2_data_w),
      .debug_cycle_count_o(fc2_cycle_count_w),
      .debug_output_count_o(fc2_output_count_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      gap_start_q <= 1'b0;
      fc1_start_q <= 1'b0;
      fc2_start_q <= 1'b0;
      debug_total_cycle_count_o <= '0;
    end else begin
      gap_start_q <= 1'b0;
      fc1_start_q <= 1'b0;
      fc2_start_q <= 1'b0;

      if (state_q != S_IDLE) begin
        debug_total_cycle_count_o <= debug_total_cycle_count_o + 32'd1;
      end

      case (state_q)
        S_IDLE: begin
          debug_total_cycle_count_o <= '0;
          if (start_i) begin
            gap_start_q <= 1'b1;
            state_q <= S_RUN_GAP;
          end
        end

        S_RUN_GAP: begin
          if (gap_done_w) begin
            state_q <= S_START_FC1;
          end
        end

        S_START_FC1: begin
          fc1_start_q <= 1'b1;
          state_q <= S_RUN_FC1;
        end

        S_RUN_FC1: begin
          if (fc1_done_w) begin
            state_q <= S_START_FC2;
          end
        end

        S_START_FC2: begin
          fc2_start_q <= 1'b1;
          state_q <= S_RUN_FC2;
        end

        S_RUN_FC2: begin
          if (fc2_done_w) begin
            state_q <= S_IDLE;
          end
        end

        default: begin
          state_q <= S_IDLE;
        end
      endcase
    end
  end

endmodule : animals10_gap_fc1_fc2_i8

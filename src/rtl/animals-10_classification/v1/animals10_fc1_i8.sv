`timescale 1ns / 1ps

module animals10_fc1_i8 (
    input logic clk,
    input logic rst_n,
    input logic start_i,
    output logic busy_o,
    output logic done_o,
    input logic input_we_i,
    input logic [6:0] input_addr_i,
    input logic signed [7:0] input_data_i,
    input logic weight_we_i,
    input logic [13:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,
    input logic param_we_i,
    input logic [6:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,
    output logic output_valid_o,
    output logic output_last_o,
    output logic [6:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,
    output logic [31:0] debug_cycle_count_o,
    output logic [31:0] debug_output_count_o
);

  animals10_dense_i8 #(
      .INPUT_FEATURES(128),
      .OUTPUT_FEATURES(128),
      .RELU(1'b1),
      .INPUT_ADDR_WIDTH(7),
      .WEIGHT_ADDR_WIDTH(14),
      .PARAM_ADDR_WIDTH(7),
      .OUTPUT_ADDR_WIDTH(7)
  ) u_dense (
      .clk(clk),
      .rst_n(rst_n),
      .start_i(start_i),
      .busy_o(busy_o),
      .done_o(done_o),
      .input_we_i(input_we_i),
      .input_addr_i(input_addr_i),
      .input_data_i(input_data_i),
      .weight_we_i(weight_we_i),
      .weight_addr_i(weight_addr_i),
      .weight_data_i(weight_data_i),
      .param_we_i(param_we_i),
      .param_addr_i(param_addr_i),
      .bias_data_i(bias_data_i),
      .requant_mult_data_i(requant_mult_data_i),
      .requant_shift_data_i(requant_shift_data_i),
      .output_valid_o(output_valid_o),
      .output_last_o(output_last_o),
      .output_index_o(output_index_o),
      .acc_o(acc_o),
      .data_o(data_o),
      .debug_cycle_count_o(debug_cycle_count_o),
      .debug_output_count_o(debug_output_count_o)
  );

endmodule : animals10_fc1_i8

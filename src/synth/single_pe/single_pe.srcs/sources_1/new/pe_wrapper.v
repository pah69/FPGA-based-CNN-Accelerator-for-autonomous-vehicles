`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/20/2026 05:11:19 PM
// Design Name: 
// Module Name: pe_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module pe_wrapper #(
    parameter DATA_WIDTH = 17,
    parameter ADDR_WIDTH = 16,
    parameter MAC_PIPELINE_DEPTH = 4
) (
    // clock
    input clk,
    input rst_n,

    // dataflow (Activation)
    input  signed [DATA_WIDTH-1:0] activation_i,
    output signed [DATA_WIDTH-1:0] activation_o,

    // ram ctrl (Weight)
    input                          weight_we,
    input         [ADDR_WIDTH-1:0] weight_addr,
    input  signed [DATA_WIDTH-1:0] weight_i,

    // MAC control (Lifecycle)
    input  valid_i,
    input  start,
    input  acc_clear,

    // MAC output
    output valid_o,
    output signed [2*DATA_WIDTH:0] result_o
);
    
    pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
  ) pe_inst (
      .clk(clk),
      .rst_n(rst_n),
      .activation_i(activation_i),
      .activation_o(activation_o),
      .weight_we(weight_we),
      .weight_addr(weight_addr),
      .weight_i(weight_i),
      .valid_i(valid_i),
      .start(start),
      .acc_clear(acc_clear),
      .valid_o(valid_o),
      .result_o(result_o)
  );
endmodule

////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: mac_unit
// Target Device: ZCU104
// Tool versions: Vivado 2025.2
// Description:
//    <Description here>
// Dependencies:
//    <Dependencies here>
// Revision:
//    <Code_revision_information>
// Additional Comments:
//    <Additional_comments>
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module mac_unit #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    // Data inputs
    input logic signed [DATA_WIDTH-1:0] mac_a_i,
    input logic signed [DATA_WIDTH-1:0] mac_b_i,

    // Control inputs
    input logic mac_valid_i,
    input logic mac_start,
    input logic mac_acc_clear,

    // Outputs
    output logic mac_valid_o,
    output logic signed [DATA_WIDTH*2:0] result
);

  // --- Internal Signals ---
  logic signed [(DATA_WIDTH*2)-1:0] product_o;

  // Control signal pipeline registers (3 stages to match multiplier)
  logic [2:0] valid_pipe;
  logic [2:0] start_pipe;
  logic [2:0] clear_pipe;

  // --- Control Signal Synchronization ---
  // Delay the control signals by 3 clock cycles to align with the multiplier's output
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      start_pipe <= '0;
      clear_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[1:0], mac_valid_i};
      start_pipe <= {start_pipe[1:0], mac_start};
      clear_pipe <= {clear_pipe[1:0], mac_acc_clear};
    end
  end

  // Signals extracted from the end of the pipeline to feed the accumulator
  logic acc_valid_in;
  logic acc_start;
  logic acc_clear;

  assign acc_valid_in = valid_pipe[2];
  assign acc_start    = start_pipe[2];
  assign acc_clear    = clear_pipe[2];


  // --- Instantiations ---

  // 1. Pipelined Multiplier (Latency: 3 cycles)
  multiplier #(
      .DATA_WIDTH(DATA_WIDTH)
  ) mul (
      .clk(clk),
      .rst_n(rst_n),
      .a_i(mac_a_i),
      .b_i(mac_b_i),
      .product(product_o)
  );

  // 2. Accumulator (Latency: 1 cycle)
  accumulator #(
      .DATA_WIDTH(DATA_WIDTH)
  ) acc (
      .clk(clk),
      .rst_n(rst_n),
      .clear(acc_clear),
      .start(acc_start),
      .valid_i(acc_valid_in),
      // Sign-extend the 34-bit product to 35 bits for the accumulator
      .accum_i({product_o[(DATA_WIDTH*2)-1], product_o}),
      .valid_o(mac_valid_o),
      .accum_o(result)
  );

endmodule


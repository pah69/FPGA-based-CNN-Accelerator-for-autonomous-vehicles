////////////////////////////////////////////////////////////////////////////////
// Company: <Company Name>
// Engineer: Anh Ho Pham
//
// Create Date: 03/03/2026
// Design Name: MAC_unit
// Module Name: accumulator
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

module accumulator #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,
    input logic acc_clear,  // Synchronously clears the accumulator
    input logic start,  // Starts a new accumulation (ignores previous sum)
    input logic valid_in,  // High when accum_in is valid
    input logic signed [DATA_WIDTH*2:0] accum_in,

    output logic valid_out,  // High when accum_out is valid
    output logic signed [DATA_WIDTH*2:0] accum_out
);

  logic signed [DATA_WIDTH*2:0] current_sum_o;
  logic signed [DATA_WIDTH*2:0] next_sum_o;
  logic signed [DATA_WIDTH*2:0] adder_b_in;

  // Mux: If 'start' is high, ignore the accumulated sum and add 0 to accum_in
  assign adder_b_in = start ? '0 : current_sum_o;

  // Instantiate adder module
  adder #(
      .DATA_WIDTH(DATA_WIDTH)
  ) add (
      .a_in(accum_in),
      .b_in(adder_b_in),
      .sum (next_sum_o)
  );

  // Register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_sum_o <= '0;
      valid_out     <= 1'b0;
    end else begin
      if (acc_clear) begin
        // Fully clear the accumulator back to zero
        current_sum_o <= '0;
        valid_out     <= 1'b0;
      end else if (valid_in) begin
        // Only accumulate when input data is valid
        current_sum_o <= next_sum_o;
        valid_out     <= 1'b1;
      end else begin
        // Hold the sum, but signal that no new valid computation occurred this cycle
        valid_out <= 1'b0;
      end
    end
  end

  // assign out
  assign accum_out = current_sum_o;

endmodule


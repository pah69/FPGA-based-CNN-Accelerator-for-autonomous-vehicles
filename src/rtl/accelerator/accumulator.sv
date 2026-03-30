`timescale 1ns / 1ps

module accumulator #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,
    input logic clear,
    input logic start,
    input logic valid_i,
    input logic signed [DATA_WIDTH*2:0] accum_i,

    output logic valid_o,
    output logic signed [DATA_WIDTH*2:0] accum_o
);

  logic signed [DATA_WIDTH*2:0] current_sum_o;
  logic signed [DATA_WIDTH*2:0] next_sum_o;
  logic signed [DATA_WIDTH*2:0] adder_b_i;

  logic start_d;
  logic start_seq;
  logic start_pending;

  assign start_seq = start & ~start_d;

  // Use zero only at the beginning of a new accumulation
  assign adder_b_i   = (start_seq || start_pending) ? '0 : current_sum_o;

  adder #(
      .DATA_WIDTH(DATA_WIDTH)
  ) add (
      .a_i(accum_i),
      .b_i(adder_b_i),
      .sum(next_sum_o)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_sum_o <= '0;
      valid_o       <= 1'b0;
      start_d       <= 1'b0;
      start_pending <= 1'b0;
    end else begin
      start_d <= start;
      if (clear) begin
        current_sum_o <= '0;
        valid_o       <= 1'b0;
        start_pending <= 1'b0;
      end else if (start_seq && !valid_i) begin
        current_sum_o <= '0;
        valid_o       <= 1'b0;
        start_pending <= 1'b1;
      end else if (valid_i) begin
        current_sum_o <= next_sum_o;
        valid_o       <= 1'b1;
        start_pending <= 1'b0;
      end
    end
  end

  assign accum_o = current_sum_o;

endmodule

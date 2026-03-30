`timescale 1ns / 1ps

module multiplier #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,
    input logic signed [DATA_WIDTH-1:0] a_i,
    input logic signed [DATA_WIDTH-1:0] b_i,
    output logic signed [(2*DATA_WIDTH)-1:0] product
);

  // Input pipeline registers
  logic signed [    DATA_WIDTH-1:0] a_reg;
  logic signed [    DATA_WIDTH-1:0] b_reg;
  logic signed [    DATA_WIDTH-1:0] c_reg;
  logic signed [    DATA_WIDTH-1:0] d_reg;

  // Multiplication result register
  logic signed [(2*DATA_WIDTH)-1:0] mult_reg;

  // Pipeline
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_reg    <= '0;
      b_reg    <= '0;
      c_reg    <= '0;
      d_reg    <= '0;
      mult_reg <= '0;
    end else begin
      a_reg    <= a_i;
      b_reg    <= b_i;
      c_reg    <= a_reg;
      d_reg    <= b_reg;
      mult_reg <= $signed(c_reg) * $signed(d_reg);
    end
  end

  // Assign 
  assign product = mult_reg;

endmodule

















`timescale 1ns / 1ps

/**
 * Pipelined Signed Multiplier
 * 
 * This module implements a 3-stage pipeline for signed multiplication:
 *   Stage 1: Input registration
 *   Stage 2: Multiplication
 *   Stage 3: Output registration
 * 
 * Total latency: 3 clock cycles
 * Throughput: 1 multiplication per clock cycle (after initial fill)
 */
module multiplier #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    // Input interface
    input logic signed [DATA_WIDTH-1:0] a_i,
    input logic signed [DATA_WIDTH-1:0] b_i,
    input logic valid_i,

    // Output interface
    output logic signed [(2*DATA_WIDTH)-1:0] product_o,
    output logic valid_o
);

  // ========================================
  // Stage 1: Input Registration
  // ========================================
  logic signed [DATA_WIDTH-1:0] a_s1, b_s1;
  logic valid_s1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_s1 <= '0;
      b_s1 <= '0;
      valid_s1 <= '0;
    end else begin
      a_s1 <= a_i;
      b_s1 <= b_i;
      valid_s1 <= valid_i;
    end
  end

  // ========================================
  // Stage 2: Multiplication
  // ========================================
  logic signed [(2*DATA_WIDTH)-1:0] product_s2;
  logic valid_s2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_s2 <= '0;
      valid_s2   <= '0;
    end else begin
      product_s2 <= a_s1 * b_s1;
      valid_s2   <= valid_s1;
    end
  end

  // ========================================
  // Stage 3: Output Registration
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_o <= '0;
      valid_o   <= '0;
    end else begin
      product_o <= product_s2;
      valid_o   <= valid_s2;
    end
  end

endmodule



`timescale 1ns / 1ps

/**
 * Systolic Array Processing Element (PE) - No For Loops Version
 * 
 * Architecture:
 *   - Multiply-Accumulate (MAC) operation: psum_out = psum_in + (activation × weight)
 *   - Stationary weight (stored in PE)
 *   - Pipelined multiplier: 3-cycle latency
 *   - Delay lines align activation and partial sum streams to multiplier output
 *   - All validity signals propagate through pipeline
 * 
 * Data Flow:
 *   Activation stream:    left → multiply → delay 4 cycles → right
 *   Weight (stationary):  loaded via weight_load_i
 *   Partial sum stream:   top → delay 3 cycles → adder → register → bottom
 * 
 * Latency:
 *   - Multiplier: 3 cycles (a_i → product_o)
 *   - Activation forwarding: 4 cycles (to align with psum output)
 *   - Partial sum path: 3 cycles + 1 output register = 4 total
 *   - PE output valid when both psum and activation are valid
 */
module pe #(
    parameter int DATA_WIDTH = 17,
    parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Activation stream (left → right)
    // ========================================
    input  logic signed [DATA_WIDTH-1:0] act_i,
    input  logic                         act_valid_i,
    output logic signed [DATA_WIDTH-1:0] act_o,
    output logic                         act_valid_o,

    // ========================================
    // Partial sum stream (top → bottom)
    // ========================================
    input  logic signed [PSUM_WIDTH-1:0] psum_i,
    input  logic                         psum_valid_i,
    output logic signed [PSUM_WIDTH-1:0] psum_o,
    output logic                         psum_valid_o,

    // ========================================
    // Stationary weight (PE-local storage)
    // ========================================
    input  logic signed [DATA_WIDTH-1:0] weight_i,
    input  logic                         weight_load_i,
    output logic signed [DATA_WIDTH-1:0] weight_o
);

  // ========================================
  // Local Parameters & Constants
  // ========================================
  localparam int PROD_WIDTH = 2 * DATA_WIDTH;

  // ========================================
  // Signal Declarations
  // ========================================

  // Weight storage
  logic signed [DATA_WIDTH-1:0] weight_reg;

  // Multiplier interface
  logic signed [PROD_WIDTH-1:0] mult_product;
  logic mult_valid;

  // Activation delay line (4 stages)
  logic signed [DATA_WIDTH-1:0] act_d1, act_d2, act_d3, act_d4;
  logic act_valid_d1, act_valid_d2, act_valid_d3, act_valid_d4;

  // Partial sum delay line (3 stages)
  logic signed [PSUM_WIDTH-1:0] psum_d1, psum_d2, psum_d3;
  logic psum_valid_d1, psum_valid_d2, psum_valid_d3;

  // MAC operation signals
  logic signed [PSUM_WIDTH-1:0] mult_product_ext;  // Extended to PSUM_WIDTH
  logic signed [PSUM_WIDTH-1:0] sum_result;  // Adder output
  logic                         sum_valid;  // Valid signal for sum

  // ========================================
  // 1. Weight Register (Stationary)
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_reg <= '0;
    end else if (weight_load_i) begin
      weight_reg <= weight_i;
    end
  end

  assign weight_o = weight_reg;

  // ========================================
  // 2. Pipelined Multiplier Instantiation
  // ========================================
  multiplier #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_multiplier (
      .clk(clk),
      .rst_n(rst_n),
      .a_i(act_i),
      .b_i(weight_reg),
      .valid_i(act_valid_i),
      .product_o(mult_product),
      .valid_o(mult_valid)
  );

  // ========================================
  // 3. Activation Stream Delay Line (4 stages)
  // ========================================
  // Stage 1 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d1 <= '0;
      act_valid_d1 <= '0;
    end else begin
      act_d1 <= act_i;
      act_valid_d1 <= act_valid_i;
    end
  end

  // Stage 2 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d2 <= '0;
      act_valid_d2 <= '0;
    end else begin
      act_d2 <= act_d1;
      act_valid_d2 <= act_valid_d1;
    end
  end

  // Stage 3 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d3 <= '0;
      act_valid_d3 <= '0;
    end else begin
      act_d3 <= act_d2;
      act_valid_d3 <= act_valid_d2;
    end
  end

  // Stage 4 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d4 <= '0;
      act_valid_d4 <= '0;
    end else begin
      act_d4 <= act_d3;
      act_valid_d4 <= act_valid_d3;
    end
  end

  assign act_o = act_d4;
  assign act_valid_o = act_valid_d4;

  // ========================================
  // 4. Partial Sum Stream Delay Line (3 stages)
  // ========================================
  // Stage 1 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_d1 <= '0;
      psum_valid_d1 <= '0;
    end else begin
      psum_d1 <= psum_i;
      psum_valid_d1 <= psum_valid_i;
    end
  end

  // Stage 2 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_d2 <= '0;
      psum_valid_d2 <= '0;
    end else begin
      psum_d2 <= psum_d1;
      psum_valid_d2 <= psum_valid_d1;
    end
  end

  // Stage 3 of delay
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_d3 <= '0;
      psum_valid_d3 <= '0;
    end else begin
      psum_d3 <= psum_d2;
      psum_valid_d3 <= psum_valid_d2;
    end
  end

  // ========================================
  // 5. MAC Operation: Multiply & Accumulate
  // ========================================

  // Sign-extend multiplier product to PSUM_WIDTH
  assign mult_product_ext = {
    {(PSUM_WIDTH - PROD_WIDTH) {mult_product[PROD_WIDTH-1]}}, mult_product
  };

  // Add delayed psum with extended product
  assign sum_result = psum_d3 + mult_product_ext;

  // Valid only when both streams have valid data
  assign sum_valid = mult_valid && psum_valid_d3;

  // ========================================
  // 6. Output Registration
  // ========================================
  // Register the MAC result and validity signal
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_o <= '0;
      psum_valid_o <= '0;
    end else begin
      psum_o <= sum_result;
      psum_valid_o <= sum_valid;
    end
  end

endmodule : pe

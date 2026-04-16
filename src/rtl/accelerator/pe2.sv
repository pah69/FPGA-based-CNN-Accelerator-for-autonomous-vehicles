`timescale 1ns / 1ps

/**
 * Systolic Array Processing Element (PE)
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
  localparam int MULT_LATENCY = 3;
  localparam int ACT_DELAY_STAGES = 4;  // Align with psum_o output timing
  localparam int PSUM_DELAY_STAGES = 3;  // Align with multiplier output

  // ========================================
  // Signal Declarations
  // ========================================

  // Weight storage
  logic signed [DATA_WIDTH-1:0] weight_reg;

  // Multiplier interface
  logic signed [PROD_WIDTH-1:0] mult_product;
  logic                         mult_valid;

  // Delay lines for activation stream
  logic signed [DATA_WIDTH-1:0] act_delay_q                                 [ ACT_DELAY_STAGES];
  logic                         act_valid_delay_q                           [ ACT_DELAY_STAGES];

  // Delay lines for partial sum stream
  logic signed [PSUM_WIDTH-1:0] psum_delay_q                                [PSUM_DELAY_STAGES];
  logic                         psum_valid_delay_q                          [PSUM_DELAY_STAGES];

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
  // 3. Activation Stream Delay Line
  // ========================================
  // Delays activation by 4 cycles to align with final psum output
  // Psum output path: 3-cycle delay + 1 register = 4 cycles total
  // Activation must also have 4 cycles to stay aligned
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < ACT_DELAY_STAGES; i++) begin
        act_delay_q[i] <= '0;
        act_valid_delay_q[i] <= '0;
      end
    end else begin
      // Shift through delay line
      act_delay_q[0] <= act_i;
      act_valid_delay_q[0] <= act_valid_i;

      for (int i = 1; i < ACT_DELAY_STAGES; i++) begin
        act_delay_q[i] <= act_delay_q[i-1];
        act_valid_delay_q[i] <= act_valid_delay_q[i-1];
      end
    end
  end

  assign act_o = act_delay_q[ACT_DELAY_STAGES-1];
  assign act_valid_o = act_valid_delay_q[ACT_DELAY_STAGES-1];

  // ========================================
  // 4. Partial Sum Stream Delay Line
  // ========================================
  // Delays psum input by 3 cycles to align with multiplier product output
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < PSUM_DELAY_STAGES; i++) begin
        psum_delay_q[i] <= '0;
        psum_valid_delay_q[i] <= '0;
      end
    end else begin
      // Shift through delay line
      psum_delay_q[0] <= psum_i;
      psum_valid_delay_q[0] <= psum_valid_i;

      for (int i = 1; i < PSUM_DELAY_STAGES; i++) begin
        psum_delay_q[i] <= psum_delay_q[i-1];
        psum_valid_delay_q[i] <= psum_valid_delay_q[i-1];
      end
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
  assign sum_result = psum_delay_q[PSUM_DELAY_STAGES-1] + mult_product_ext;

  // Valid only when both streams have valid data
  assign sum_valid = mult_valid && psum_valid_delay_q[PSUM_DELAY_STAGES-1];

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

endmodule : pe  // `timescale 1ns / 1ps
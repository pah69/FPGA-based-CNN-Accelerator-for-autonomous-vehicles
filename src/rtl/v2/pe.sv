`timescale 1ns / 1ps

module pe #(
    parameter int DATA_WIDTH       = 8,
    parameter int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + 2
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Activation stream: left -> right
    // ========================================
    input  logic signed [DATA_WIDTH-1:0] act_i,
    input  logic                         act_valid_i,
    output logic signed [DATA_WIDTH-1:0] act_o,
    output logic                         act_valid_o,

    // ========================================
    // Partial sum stream: top -> bottom
    // ========================================
    input  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_i,
    input  logic                               psum_valid_i,
    output logic signed [LOCAL_PSUM_WIDTH-1:0] psum_o,
    output logic                               psum_valid_o,

    // ========================================
    // Weight stream / stationary weight control
    // ========================================
    input logic signed [DATA_WIDTH-1:0] weight_i,
    input logic                         weight_load_i,
    input logic                         weight_switch_i,

    output logic signed [DATA_WIDTH-1:0] weight_o,
    output logic                         weight_valid_o,

    // ========================================
    // Debug / status
    // ========================================
    input  logic overflow_clr_i,
    output logic overflow_o
);

  // ========================================
  // Local parameters
  // ========================================
  localparam int MULT_WIDTH = 2 * DATA_WIDTH;

  // Requirement:
  // LOCAL_PSUM_WIDTH must be >= MULT_WIDTH.
  // Example:
  // DATA_WIDTH = 8
  // MULT_WIDTH = 16
  // LOCAL_PSUM_WIDTH should be at least 16, usually larger.

  // ========================================
  // Weight storage
  // ========================================
  logic signed [      DATA_WIDTH-1:0] weight_active;
  logic signed [      DATA_WIDTH-1:0] weight_shadow;

  // ========================================
  // Multiplier interface
  // ========================================
  logic signed [      MULT_WIDTH-1:0] mult_product;
  logic                               mult_valid;

  // ========================================
  // Activation delay line
  // Multiplier latency = 3 cycles
  // PE output register adds 1 more cycle
  // So activation forwarding is delayed 4 cycles.
  // ========================================
  logic signed [      DATA_WIDTH-1:0] act_d1;
  logic signed [      DATA_WIDTH-1:0] act_d2;
  logic signed [      DATA_WIDTH-1:0] act_d3;
  logic signed [      DATA_WIDTH-1:0] act_d4;

  logic                               act_valid_d1;
  logic                               act_valid_d2;
  logic                               act_valid_d3;
  logic                               act_valid_d4;

  // ========================================
  // Partial sum delay line
  // Psum must align with multiplier output.
  // Multiplier output appears after 3 cycles.
  // ========================================
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_d1;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_d2;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_d3;

  logic                               psum_valid_d1;
  logic                               psum_valid_d2;
  logic                               psum_valid_d3;

  // ========================================
  // MAC signals
  // ========================================
  logic signed [LOCAL_PSUM_WIDTH-1:0] mult_product_ext;
  logic signed [  LOCAL_PSUM_WIDTH:0] add_full;
  logic signed [LOCAL_PSUM_WIDTH-1:0] sum_result;

  logic                               sum_valid;
  logic                               add_overflow;

  // ========================================
  // 1. Double-buffered stationary weight
  // ========================================
  //
  // weight_shadow:
  //   Loaded with the next weight.
  //
  // weight_active:
  //   Used by the multiplier.
  //
  // weight_switch_i:
  //   Copies shadow weight into active weight.
  //
  // Timing note:
  //   Assert weight_switch_i at least 1 cycle before the first act_valid_i
  //   that should use the new active weight.
  //
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_active <= '0;
      weight_shadow <= '0;
    end else begin
      if (weight_load_i) begin
        weight_shadow <= weight_i;
      end

      if (weight_switch_i) begin
        weight_active <= weight_shadow;
      end
    end
  end

  // ========================================
  // 2. Weight forwarding
  // ========================================
  //
  // This lets you daisy-chain weight loading through PEs.
  // The next PE can use weight_o only when weight_valid_o is high.
  //
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_o       <= '0;
      weight_valid_o <= 1'b0;
    end else begin
      weight_o       <= weight_i;
      weight_valid_o <= weight_load_i;
    end
  end

  // ========================================
  // 3. Pipelined multiplier
  // ========================================
  //
  // Uses the active stationary weight.
  //
  multiplier #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_multiplier (
      .clk      (clk),
      .rst_n    (rst_n),
      .a_i      (act_i),
      .b_i      (weight_active),
      .valid_i  (act_valid_i),
      .product_o(mult_product),
      .valid_o  (mult_valid)
  );

  // ========================================
  // 4. Activation delay line
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d1       <= '0;
      act_d2       <= '0;
      act_d3       <= '0;
      act_d4       <= '0;

      act_valid_d1 <= 1'b0;
      act_valid_d2 <= 1'b0;
      act_valid_d3 <= 1'b0;
      act_valid_d4 <= 1'b0;
    end else begin
      act_d1 <= act_valid_i ? act_i : '0;
      act_d2 <= act_valid_d1 ? act_d1 : '0;
      act_d3 <= act_valid_d2 ? act_d2 : '0;
      act_d4 <= act_valid_d3 ? act_d3 : '0;

      act_valid_d1 <= act_valid_i;
      act_valid_d2 <= act_valid_d1;
      act_valid_d3 <= act_valid_d2;
      act_valid_d4 <= act_valid_d3;
    end
  end

  assign act_o       = act_d4;
  assign act_valid_o = act_valid_d4;

  // ========================================
  // 5. Partial sum delay line
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_d1       <= '0;
      psum_d2       <= '0;
      psum_d3       <= '0;

      psum_valid_d1 <= 1'b0;
      psum_valid_d2 <= 1'b0;
      psum_valid_d3 <= 1'b0;
    end else begin
      psum_d1 <= psum_valid_i ? psum_i : '0;
      psum_d2 <= psum_valid_d1 ? psum_d1 : '0;
      psum_d3 <= psum_valid_d2 ? psum_d2 : '0;

      psum_valid_d1 <= psum_valid_i;
      psum_valid_d2 <= psum_valid_d1;
      psum_valid_d3 <= psum_valid_d2;
    end
  end

  // ========================================
  // 6. Product sign extension
  // ========================================
  //
  // mult_product is DATA_WIDTH * DATA_WIDTH.
  // It must be sign-extended before adding to psum.
  //
  assign mult_product_ext = {
    {(LOCAL_PSUM_WIDTH - MULT_WIDTH) {mult_product[MULT_WIDTH-1]}}, mult_product
  };

  // ========================================
  // 7. MAC operation with overflow detection
  // ========================================
  //
  // Add one extra sign bit to detect signed overflow.
  //
  assign add_full = {
      psum_d3[LOCAL_PSUM_WIDTH-1],
      psum_d3
  } + {
      mult_product_ext[LOCAL_PSUM_WIDTH-1],
      mult_product_ext
  };

  assign sum_result = add_full[LOCAL_PSUM_WIDTH-1:0];

  // Signed overflow happens when the top two bits disagree.
  assign add_overflow = add_full[LOCAL_PSUM_WIDTH] ^ add_full[LOCAL_PSUM_WIDTH-1];

  assign sum_valid = mult_valid && psum_valid_d3;

  // ========================================
  // 8. Output register
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_o       <= '0;
      psum_valid_o <= 1'b0;
    end else begin
      if (sum_valid) begin
        psum_o <= sum_result;
      end else begin
        psum_o <= '0;
      end

      psum_valid_o <= sum_valid;
    end
  end

  // ========================================
  // 9. Sticky overflow flag
  // ========================================
  //
  // Once overflow_o becomes 1, it stays 1 until overflow_clr_i or reset.
  //
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_o <= 1'b0;
    end else if (overflow_clr_i) begin
      overflow_o <= 1'b0;
    end else if (sum_valid && add_overflow) begin
      overflow_o <= 1'b1;
    end
  end

endmodule : pe

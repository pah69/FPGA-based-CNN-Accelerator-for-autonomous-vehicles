`timescale 1ns / 1ps

module pe #(
    parameter int DATA_WIDTH = 17,
    parameter int PSUM_WIDTH = (2*DATA_WIDTH) + 8
) (
    input  logic clk,
    input  logic rst_n,

    // Activation stream: left -> right
    input  logic signed [DATA_WIDTH-1:0] act_i,
    input  logic                         act_valid_i,

    // Partial sum stream: top -> bottom
    input  logic signed [PSUM_WIDTH-1:0] psum_i,
    input  logic                         psum_valid_i,

    // Stationary weight load
    input  logic signed [DATA_WIDTH-1:0] weight_i,
    input  logic                         weight_load_i, // control signal

    // Forwarded activation stream
    output logic signed [DATA_WIDTH-1:0] act_o,
    output logic                         act_valid_o,

    // Forwarded partial sum stream
    output logic signed [PSUM_WIDTH-1:0] psum_o,
    output logic                         psum_valid_o,

    // Debug
    output logic signed [DATA_WIDTH-1:0] weight_o
);

  localparam int PROD_WIDTH = 2 * DATA_WIDTH;

  logic signed [DATA_WIDTH-1:0] weight_reg;
  logic signed [PROD_WIDTH-1:0] product_w;
  logic signed [PSUM_WIDTH-1:0] product_ext;
  logic signed [PSUM_WIDTH-1:0] sum_w;

  // Delay lines to align with multiplier latency
  logic signed [DATA_WIDTH-1:0] act_d0, act_d1, act_d2, act_d3;
  logic                         val_d0, val_d1, val_d2, val_d3;

  logic signed [PSUM_WIDTH-1:0] psum_d0, psum_d1, psum_d2;
  logic                         psum_val_d0, psum_val_d1, psum_val_d2;

  // --------------------------------------------------------------------------
  // Stationary weight register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      weight_reg <= '0;
    else if (weight_load_i)
      weight_reg <= weight_i;
  end

  assign weight_o = weight_reg;

  // --------------------------------------------------------------------------
  // Pipelined multiplier
  // --------------------------------------------------------------------------
  multiplier #(
      .DATA_WIDTH(DATA_WIDTH)
  ) u_multiplier (
      .clk    (clk),
      .rst_n  (rst_n),
      .a_i    (act_i),
      .b_i    (weight_reg),
      .product(product_w)
  );

  // --------------------------------------------------------------------------
  // Delay activation by 4 cycles so it aligns with registered psum_o timing
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_d0 <= '0;
      act_d1 <= '0;
      act_d2 <= '0;
      act_d3 <= '0;

      val_d0 <= 1'b0;
      val_d1 <= 1'b0;
      val_d2 <= 1'b0;
      val_d3 <= 1'b0;
    end else begin
      act_d0 <= act_i;
      act_d1 <= act_d0;
      act_d2 <= act_d1;
      act_d3 <= act_d2;

      val_d0 <= act_valid_i;
      val_d1 <= val_d0;
      val_d2 <= val_d1;
      val_d3 <= val_d2;
    end
  end

  assign act_o       = act_d3;
  assign act_valid_o = val_d3;

  // --------------------------------------------------------------------------
  // Delay psum input by 3 cycles to align with multiplier product output
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_d0     <= '0;
      psum_d1     <= '0;
      psum_d2     <= '0;

      psum_val_d0 <= 1'b0;
      psum_val_d1 <= 1'b0;
      psum_val_d2 <= 1'b0;
    end else begin
      psum_d0     <= psum_i;
      psum_d1     <= psum_d0;
      psum_d2     <= psum_d1;

      psum_val_d0 <= psum_valid_i;
      psum_val_d1 <= psum_val_d0;
      psum_val_d2 <= psum_val_d1;
    end
  end

  // --------------------------------------------------------------------------
  // Extend product and add
  // --------------------------------------------------------------------------
  assign product_ext = {{(PSUM_WIDTH-PROD_WIDTH){product_w[PROD_WIDTH-1]}}, product_w};
  assign sum_w       = psum_d2 + product_ext;

  // --------------------------------------------------------------------------
  // Registered downward psum output
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psum_o       <= '0;
      psum_valid_o <= 1'b0;
    end else begin
      if (val_d3 && psum_val_d2) begin
        psum_o       <= sum_w;
        psum_valid_o <= 1'b1;
      end else begin
        psum_o       <= '0;
        psum_valid_o <= 1'b0;
      end
    end
  end

endmodule : pe
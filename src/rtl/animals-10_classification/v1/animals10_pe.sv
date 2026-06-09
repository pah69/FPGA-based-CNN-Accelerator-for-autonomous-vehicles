`timescale 1ns / 1ps

// Animals-10 weight-stationary processing element.
//
// V1 policy:
//   - signed INT8 activation and weight
//   - signed INT32 partial sum
//   - DSP-backed multiplier when synthesis honors use_dsp
//   - one registered MAC stage, with activation/weight forwarding
module animals10_pe #(
    parameter int DATA_WIDTH = 8,
    parameter int PSUM_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    input logic signed [DATA_WIDTH-1:0] act_i,
    input logic act_valid_i,
    output logic signed [DATA_WIDTH-1:0] act_o,
    output logic act_valid_o,

    input logic signed [PSUM_WIDTH-1:0] psum_i,
    input logic psum_valid_i,
    output logic signed [PSUM_WIDTH-1:0] psum_o,
    output logic psum_valid_o,

    input logic signed [DATA_WIDTH-1:0] weight_i,
    input logic weight_load_i,
    output logic signed [DATA_WIDTH-1:0] weight_o,
    output logic weight_valid_o
);

  localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;

  logic signed [DATA_WIDTH-1:0] weight_q;
  (* use_dsp = "yes" *) logic signed [PRODUCT_WIDTH-1:0] product_w;
  logic signed [PSUM_WIDTH-1:0] product_ext_w;
  logic mac_valid_w;

  assign product_w = act_i * weight_q;
  assign product_ext_w = {
    {(PSUM_WIDTH - PRODUCT_WIDTH) {product_w[PRODUCT_WIDTH-1]}}, product_w
  };
  assign mac_valid_w = act_valid_i && psum_valid_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_q <= '0;
      weight_o <= '0;
      weight_valid_o <= 1'b0;
      act_o <= '0;
      act_valid_o <= 1'b0;
      psum_o <= '0;
      psum_valid_o <= 1'b0;
    end else begin
      if (weight_load_i) begin
        weight_q <= weight_i;
      end

      weight_o <= weight_i;
      weight_valid_o <= weight_load_i;

      act_o <= act_valid_i ? act_i : '0;
      act_valid_o <= act_valid_i;

      psum_o <= mac_valid_w ? (psum_i + product_ext_w) : '0;
      psum_valid_o <= mac_valid_w;
    end
  end

endmodule : animals10_pe


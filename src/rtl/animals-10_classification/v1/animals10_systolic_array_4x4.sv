`timescale 1ns / 1ps

// Explicit SIZE=4 Animals-10 systolic array.
//
// This module intentionally instantiates each PE by name instead of using
// generate loops. It is the V1 bring-up array for waveform debug and
// per-PE instrumentation. Keep the parameterized array for future SIZE
// experiments, but route V1 Conv kernels through this explicit 4x4 module.
module animals10_systolic_array_4x4 #(
    parameter int DATA_WIDTH = 8,
    parameter int PSUM_WIDTH = 32,
    parameter int MAC_COUNT_WIDTH = 5
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(DATA_WIDTH*4)-1:0] weight_flatten_i,
    input logic [3:0] weight_load_i,
    input logic weight_stream_enable_i,
    input logic signed [(DATA_WIDTH*16)-1:0] weight_matrix_flatten_i,
    input logic weight_matrix_load_i,
    input logic weight_switch_i,

    input logic signed [(DATA_WIDTH*4)-1:0] act_flatten_i,
    input logic [3:0] act_valid_i,

    output logic signed [(PSUM_WIDTH*4)-1:0] psum_flatten_o,
    output logic [3:0] psum_valid_o,
    output logic [MAC_COUNT_WIDTH-1:0] valid_mac_count_o,
    output logic [3:0] weight_load_done_o
);

  localparam int SIZE = 4;

  logic signed [DATA_WIDTH-1:0] act_row_w[0:3];
  logic signed [DATA_WIDTH-1:0] weight_col_w[0:3];
  logic signed [DATA_WIDTH-1:0] matrix_weight_w[0:3][0:3];

  logic signed [DATA_WIDTH-1:0] act_fwd_w[0:3][0:3];
  logic act_valid_fwd_w[0:3][0:3];
  logic signed [DATA_WIDTH-1:0] weight_fwd_w[0:3][0:3];
  logic weight_valid_fwd_w[0:3][0:3];
  logic signed [PSUM_WIDTH-1:0] psum_fwd_w[0:3][0:3];
  logic psum_valid_fwd_w[0:3][0:3];

  logic signed [DATA_WIDTH-1:0] pe_weight_i_w[0:3][0:3];
  logic pe_weight_load_i_w[0:3][0:3];

  assign act_row_w[0] = act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row_w[1] = act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row_w[2] = act_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign act_row_w[3] = act_flatten_i[(3*DATA_WIDTH)+:DATA_WIDTH];

  assign weight_col_w[0] = weight_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  assign weight_col_w[1] = weight_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  assign weight_col_w[2] = weight_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];
  assign weight_col_w[3] = weight_flatten_i[(3*DATA_WIDTH)+:DATA_WIDTH];

  assign matrix_weight_w[0][0] = weight_matrix_flatten_i[((0*SIZE+0)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[0][1] = weight_matrix_flatten_i[((0*SIZE+1)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[0][2] = weight_matrix_flatten_i[((0*SIZE+2)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[0][3] = weight_matrix_flatten_i[((0*SIZE+3)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[1][0] = weight_matrix_flatten_i[((1*SIZE+0)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[1][1] = weight_matrix_flatten_i[((1*SIZE+1)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[1][2] = weight_matrix_flatten_i[((1*SIZE+2)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[1][3] = weight_matrix_flatten_i[((1*SIZE+3)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[2][0] = weight_matrix_flatten_i[((2*SIZE+0)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[2][1] = weight_matrix_flatten_i[((2*SIZE+1)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[2][2] = weight_matrix_flatten_i[((2*SIZE+2)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[2][3] = weight_matrix_flatten_i[((2*SIZE+3)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[3][0] = weight_matrix_flatten_i[((3*SIZE+0)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[3][1] = weight_matrix_flatten_i[((3*SIZE+1)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[3][2] = weight_matrix_flatten_i[((3*SIZE+2)*DATA_WIDTH)+:DATA_WIDTH];
  assign matrix_weight_w[3][3] = weight_matrix_flatten_i[((3*SIZE+3)*DATA_WIDTH)+:DATA_WIDTH];

  assign pe_weight_i_w[0][0] = weight_matrix_load_i ? matrix_weight_w[0][0] : weight_col_w[0];
  assign pe_weight_i_w[0][1] = weight_matrix_load_i ? matrix_weight_w[0][1] : weight_col_w[1];
  assign pe_weight_i_w[0][2] = weight_matrix_load_i ? matrix_weight_w[0][2] : weight_col_w[2];
  assign pe_weight_i_w[0][3] = weight_matrix_load_i ? matrix_weight_w[0][3] : weight_col_w[3];
  assign pe_weight_i_w[1][0] = weight_matrix_load_i ? matrix_weight_w[1][0] : weight_fwd_w[0][0];
  assign pe_weight_i_w[1][1] = weight_matrix_load_i ? matrix_weight_w[1][1] : weight_fwd_w[0][1];
  assign pe_weight_i_w[1][2] = weight_matrix_load_i ? matrix_weight_w[1][2] : weight_fwd_w[0][2];
  assign pe_weight_i_w[1][3] = weight_matrix_load_i ? matrix_weight_w[1][3] : weight_fwd_w[0][3];
  assign pe_weight_i_w[2][0] = weight_matrix_load_i ? matrix_weight_w[2][0] : weight_fwd_w[1][0];
  assign pe_weight_i_w[2][1] = weight_matrix_load_i ? matrix_weight_w[2][1] : weight_fwd_w[1][1];
  assign pe_weight_i_w[2][2] = weight_matrix_load_i ? matrix_weight_w[2][2] : weight_fwd_w[1][2];
  assign pe_weight_i_w[2][3] = weight_matrix_load_i ? matrix_weight_w[2][3] : weight_fwd_w[1][3];
  assign pe_weight_i_w[3][0] = weight_matrix_load_i ? matrix_weight_w[3][0] : weight_fwd_w[2][0];
  assign pe_weight_i_w[3][1] = weight_matrix_load_i ? matrix_weight_w[3][1] : weight_fwd_w[2][1];
  assign pe_weight_i_w[3][2] = weight_matrix_load_i ? matrix_weight_w[3][2] : weight_fwd_w[2][2];
  assign pe_weight_i_w[3][3] = weight_matrix_load_i ? matrix_weight_w[3][3] : weight_fwd_w[2][3];

  assign pe_weight_load_i_w[0][0] = weight_matrix_load_i || (weight_stream_enable_i && weight_load_i[0]);
  assign pe_weight_load_i_w[0][1] = weight_matrix_load_i || (weight_stream_enable_i && weight_load_i[1]);
  assign pe_weight_load_i_w[0][2] = weight_matrix_load_i || (weight_stream_enable_i && weight_load_i[2]);
  assign pe_weight_load_i_w[0][3] = weight_matrix_load_i || (weight_stream_enable_i && weight_load_i[3]);
  assign pe_weight_load_i_w[1][0] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[0][0]);
  assign pe_weight_load_i_w[1][1] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[0][1]);
  assign pe_weight_load_i_w[1][2] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[0][2]);
  assign pe_weight_load_i_w[1][3] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[0][3]);
  assign pe_weight_load_i_w[2][0] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[1][0]);
  assign pe_weight_load_i_w[2][1] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[1][1]);
  assign pe_weight_load_i_w[2][2] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[1][2]);
  assign pe_weight_load_i_w[2][3] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[1][3]);
  assign pe_weight_load_i_w[3][0] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[2][0]);
  assign pe_weight_load_i_w[3][1] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[2][1]);
  assign pe_weight_load_i_w[3][2] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[2][2]);
  assign pe_weight_load_i_w[3][3] = weight_matrix_load_i || (weight_stream_enable_i && weight_valid_fwd_w[2][3]);

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe00 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_row_w[0]), .act_valid_i(act_valid_i[0]),
      .act_o(act_fwd_w[0][0]), .act_valid_o(act_valid_fwd_w[0][0]),
      .psum_i('0), .psum_valid_i(act_valid_i[0]),
      .psum_o(psum_fwd_w[0][0]), .psum_valid_o(psum_valid_fwd_w[0][0]),
      .weight_i(pe_weight_i_w[0][0]), .weight_load_i(pe_weight_load_i_w[0][0]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[0][0]), .weight_valid_o(weight_valid_fwd_w[0][0])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe01 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[0][0]), .act_valid_i(act_valid_fwd_w[0][0]),
      .act_o(act_fwd_w[0][1]), .act_valid_o(act_valid_fwd_w[0][1]),
      .psum_i('0), .psum_valid_i(act_valid_fwd_w[0][0]),
      .psum_o(psum_fwd_w[0][1]), .psum_valid_o(psum_valid_fwd_w[0][1]),
      .weight_i(pe_weight_i_w[0][1]), .weight_load_i(pe_weight_load_i_w[0][1]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[0][1]), .weight_valid_o(weight_valid_fwd_w[0][1])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe02 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[0][1]), .act_valid_i(act_valid_fwd_w[0][1]),
      .act_o(act_fwd_w[0][2]), .act_valid_o(act_valid_fwd_w[0][2]),
      .psum_i('0), .psum_valid_i(act_valid_fwd_w[0][1]),
      .psum_o(psum_fwd_w[0][2]), .psum_valid_o(psum_valid_fwd_w[0][2]),
      .weight_i(pe_weight_i_w[0][2]), .weight_load_i(pe_weight_load_i_w[0][2]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[0][2]), .weight_valid_o(weight_valid_fwd_w[0][2])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe03 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[0][2]), .act_valid_i(act_valid_fwd_w[0][2]),
      .act_o(act_fwd_w[0][3]), .act_valid_o(act_valid_fwd_w[0][3]),
      .psum_i('0), .psum_valid_i(act_valid_fwd_w[0][2]),
      .psum_o(psum_fwd_w[0][3]), .psum_valid_o(psum_valid_fwd_w[0][3]),
      .weight_i(pe_weight_i_w[0][3]), .weight_load_i(pe_weight_load_i_w[0][3]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[0][3]), .weight_valid_o(weight_valid_fwd_w[0][3])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe10 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_row_w[1]), .act_valid_i(act_valid_i[1]),
      .act_o(act_fwd_w[1][0]), .act_valid_o(act_valid_fwd_w[1][0]),
      .psum_i(psum_fwd_w[0][0]), .psum_valid_i(psum_valid_fwd_w[0][0]),
      .psum_o(psum_fwd_w[1][0]), .psum_valid_o(psum_valid_fwd_w[1][0]),
      .weight_i(pe_weight_i_w[1][0]), .weight_load_i(pe_weight_load_i_w[1][0]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[1][0]), .weight_valid_o(weight_valid_fwd_w[1][0])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe11 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[1][0]), .act_valid_i(act_valid_fwd_w[1][0]),
      .act_o(act_fwd_w[1][1]), .act_valid_o(act_valid_fwd_w[1][1]),
      .psum_i(psum_fwd_w[0][1]), .psum_valid_i(psum_valid_fwd_w[0][1]),
      .psum_o(psum_fwd_w[1][1]), .psum_valid_o(psum_valid_fwd_w[1][1]),
      .weight_i(pe_weight_i_w[1][1]), .weight_load_i(pe_weight_load_i_w[1][1]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[1][1]), .weight_valid_o(weight_valid_fwd_w[1][1])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe12 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[1][1]), .act_valid_i(act_valid_fwd_w[1][1]),
      .act_o(act_fwd_w[1][2]), .act_valid_o(act_valid_fwd_w[1][2]),
      .psum_i(psum_fwd_w[0][2]), .psum_valid_i(psum_valid_fwd_w[0][2]),
      .psum_o(psum_fwd_w[1][2]), .psum_valid_o(psum_valid_fwd_w[1][2]),
      .weight_i(pe_weight_i_w[1][2]), .weight_load_i(pe_weight_load_i_w[1][2]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[1][2]), .weight_valid_o(weight_valid_fwd_w[1][2])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe13 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[1][2]), .act_valid_i(act_valid_fwd_w[1][2]),
      .act_o(act_fwd_w[1][3]), .act_valid_o(act_valid_fwd_w[1][3]),
      .psum_i(psum_fwd_w[0][3]), .psum_valid_i(psum_valid_fwd_w[0][3]),
      .psum_o(psum_fwd_w[1][3]), .psum_valid_o(psum_valid_fwd_w[1][3]),
      .weight_i(pe_weight_i_w[1][3]), .weight_load_i(pe_weight_load_i_w[1][3]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[1][3]), .weight_valid_o(weight_valid_fwd_w[1][3])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe20 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_row_w[2]), .act_valid_i(act_valid_i[2]),
      .act_o(act_fwd_w[2][0]), .act_valid_o(act_valid_fwd_w[2][0]),
      .psum_i(psum_fwd_w[1][0]), .psum_valid_i(psum_valid_fwd_w[1][0]),
      .psum_o(psum_fwd_w[2][0]), .psum_valid_o(psum_valid_fwd_w[2][0]),
      .weight_i(pe_weight_i_w[2][0]), .weight_load_i(pe_weight_load_i_w[2][0]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[2][0]), .weight_valid_o(weight_valid_fwd_w[2][0])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe21 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[2][0]), .act_valid_i(act_valid_fwd_w[2][0]),
      .act_o(act_fwd_w[2][1]), .act_valid_o(act_valid_fwd_w[2][1]),
      .psum_i(psum_fwd_w[1][1]), .psum_valid_i(psum_valid_fwd_w[1][1]),
      .psum_o(psum_fwd_w[2][1]), .psum_valid_o(psum_valid_fwd_w[2][1]),
      .weight_i(pe_weight_i_w[2][1]), .weight_load_i(pe_weight_load_i_w[2][1]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[2][1]), .weight_valid_o(weight_valid_fwd_w[2][1])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe22 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[2][1]), .act_valid_i(act_valid_fwd_w[2][1]),
      .act_o(act_fwd_w[2][2]), .act_valid_o(act_valid_fwd_w[2][2]),
      .psum_i(psum_fwd_w[1][2]), .psum_valid_i(psum_valid_fwd_w[1][2]),
      .psum_o(psum_fwd_w[2][2]), .psum_valid_o(psum_valid_fwd_w[2][2]),
      .weight_i(pe_weight_i_w[2][2]), .weight_load_i(pe_weight_load_i_w[2][2]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[2][2]), .weight_valid_o(weight_valid_fwd_w[2][2])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe23 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[2][2]), .act_valid_i(act_valid_fwd_w[2][2]),
      .act_o(act_fwd_w[2][3]), .act_valid_o(act_valid_fwd_w[2][3]),
      .psum_i(psum_fwd_w[1][3]), .psum_valid_i(psum_valid_fwd_w[1][3]),
      .psum_o(psum_fwd_w[2][3]), .psum_valid_o(psum_valid_fwd_w[2][3]),
      .weight_i(pe_weight_i_w[2][3]), .weight_load_i(pe_weight_load_i_w[2][3]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[2][3]), .weight_valid_o(weight_valid_fwd_w[2][3])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe30 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_row_w[3]), .act_valid_i(act_valid_i[3]),
      .act_o(act_fwd_w[3][0]), .act_valid_o(act_valid_fwd_w[3][0]),
      .psum_i(psum_fwd_w[2][0]), .psum_valid_i(psum_valid_fwd_w[2][0]),
      .psum_o(psum_fwd_w[3][0]), .psum_valid_o(psum_valid_fwd_w[3][0]),
      .weight_i(pe_weight_i_w[3][0]), .weight_load_i(pe_weight_load_i_w[3][0]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[3][0]), .weight_valid_o(weight_valid_fwd_w[3][0])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe31 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[3][0]), .act_valid_i(act_valid_fwd_w[3][0]),
      .act_o(act_fwd_w[3][1]), .act_valid_o(act_valid_fwd_w[3][1]),
      .psum_i(psum_fwd_w[2][1]), .psum_valid_i(psum_valid_fwd_w[2][1]),
      .psum_o(psum_fwd_w[3][1]), .psum_valid_o(psum_valid_fwd_w[3][1]),
      .weight_i(pe_weight_i_w[3][1]), .weight_load_i(pe_weight_load_i_w[3][1]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[3][1]), .weight_valid_o(weight_valid_fwd_w[3][1])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe32 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[3][1]), .act_valid_i(act_valid_fwd_w[3][1]),
      .act_o(act_fwd_w[3][2]), .act_valid_o(act_valid_fwd_w[3][2]),
      .psum_i(psum_fwd_w[2][2]), .psum_valid_i(psum_valid_fwd_w[2][2]),
      .psum_o(psum_fwd_w[3][2]), .psum_valid_o(psum_valid_fwd_w[3][2]),
      .weight_i(pe_weight_i_w[3][2]), .weight_load_i(pe_weight_load_i_w[3][2]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[3][2]), .weight_valid_o(weight_valid_fwd_w[3][2])
  );

  animals10_pe #(.DATA_WIDTH(DATA_WIDTH), .PSUM_WIDTH(PSUM_WIDTH)) u_pe33 (
      .clk(clk), .rst_n(rst_n),
      .act_i(act_fwd_w[3][2]), .act_valid_i(act_valid_fwd_w[3][2]),
      .act_o(act_fwd_w[3][3]), .act_valid_o(act_valid_fwd_w[3][3]),
      .psum_i(psum_fwd_w[2][3]), .psum_valid_i(psum_valid_fwd_w[2][3]),
      .psum_o(psum_fwd_w[3][3]), .psum_valid_o(psum_valid_fwd_w[3][3]),
      .weight_i(pe_weight_i_w[3][3]), .weight_load_i(pe_weight_load_i_w[3][3]),
      .weight_switch_i(weight_switch_i),
      .weight_o(weight_fwd_w[3][3]), .weight_valid_o(weight_valid_fwd_w[3][3])
  );

  assign psum_flatten_o[(0*PSUM_WIDTH)+:PSUM_WIDTH] = psum_fwd_w[3][0];
  assign psum_flatten_o[(1*PSUM_WIDTH)+:PSUM_WIDTH] = psum_fwd_w[3][1];
  assign psum_flatten_o[(2*PSUM_WIDTH)+:PSUM_WIDTH] = psum_fwd_w[3][2];
  assign psum_flatten_o[(3*PSUM_WIDTH)+:PSUM_WIDTH] = psum_fwd_w[3][3];

  assign psum_valid_o[0] = psum_valid_fwd_w[3][0];
  assign psum_valid_o[1] = psum_valid_fwd_w[3][1];
  assign psum_valid_o[2] = psum_valid_fwd_w[3][2];
  assign psum_valid_o[3] = psum_valid_fwd_w[3][3];

  assign weight_load_done_o[0] = weight_valid_fwd_w[3][0];
  assign weight_load_done_o[1] = weight_valid_fwd_w[3][1];
  assign weight_load_done_o[2] = weight_valid_fwd_w[3][2];
  assign weight_load_done_o[3] = weight_valid_fwd_w[3][3];

  assign valid_mac_count_o =
      MAC_COUNT_WIDTH'(act_valid_i[0]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[0][0]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[0][1]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[0][2]) +
      MAC_COUNT_WIDTH'(act_valid_i[1]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[1][0]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[1][1]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[1][2]) +
      MAC_COUNT_WIDTH'(act_valid_i[2]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[2][0]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[2][1]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[2][2]) +
      MAC_COUNT_WIDTH'(act_valid_i[3]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[3][0]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[3][1]) +
      MAC_COUNT_WIDTH'(act_valid_fwd_w[3][2]);

endmodule : animals10_systolic_array_4x4

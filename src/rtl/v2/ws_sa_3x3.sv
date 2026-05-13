// ============================================================
// Auto-generated 3x3 Weight-Stationary Systolic Array
// Explicit PE instantiation. No SystemVerilog generate loops.
// ============================================================
`timescale 1ns / 1ps 
//`default_nettype wire
////`default_nettype wire
module ws_sa_3x3 #(
    parameter int SIZE             = 3,
    parameter int DATA_WIDTH       = 8,
    parameter int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE)
) (
    input logic clk,
    input logic rst_n,

    // Weight input: one weight enters from the top of each column.
    input logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i,
    input logic        [             SIZE-1:0] wgt_load_i,
    input logic                                weight_switch_i,

    // Activation input: one activation enters from the left of each row.
    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i,
    input logic        [             SIZE-1:0] act_valid_i,

    // Final partial sums from the bottom row.
    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,
    output logic        [                   SIZE-1:0] psum_valid_o,

    // High after the weight stream reaches the bottom PE of each column.
    output logic [SIZE-1:0] wgt_load_done_o,

    // Sticky overflow flags from every PE: bit index = row*SIZE + column.
    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o
);

  // NOTE:
  //   SIZE is used for port widths, but this file contains exactly
  //   3x3 PE instances. Do not override SIZE to another value.

  // ========================================================
  // Input unpacking
  // ========================================================
  logic signed [DATA_WIDTH-1:0] act_row0_i;
  assign act_row0_i = act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] act_row1_i;
  assign act_row1_i = act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] act_row2_i;
  assign act_row2_i = act_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];

  logic signed [DATA_WIDTH-1:0] wgt_col0_i;
  assign wgt_col0_i = wgt_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] wgt_col1_i;
  assign wgt_col1_i = wgt_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] wgt_col2_i;
  assign wgt_col2_i = wgt_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH];

  // ========================================================
  // Internal routing wires
  // ========================================================
  logic signed [      DATA_WIDTH-1:0] act_0_0_to_0_1;
  logic                               act_v_0_0_to_0_1;
  logic signed [      DATA_WIDTH-1:0] wgt_0_0_to_1_0;
  logic                               wgt_v_0_0_to_1_0;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_0_0_to_1_0;
  logic                               psum_v_0_0_to_1_0;
  logic signed [      DATA_WIDTH-1:0] act_0_1_to_0_2;
  logic                               act_v_0_1_to_0_2;
  logic signed [      DATA_WIDTH-1:0] wgt_0_1_to_1_1;
  logic                               wgt_v_0_1_to_1_1;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_0_1_to_1_1;
  logic                               psum_v_0_1_to_1_1;
  logic signed [      DATA_WIDTH-1:0] wgt_0_2_to_1_2;
  logic                               wgt_v_0_2_to_1_2;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_0_2_to_1_2;
  logic                               psum_v_0_2_to_1_2;
  logic signed [      DATA_WIDTH-1:0] act_1_0_to_1_1;
  logic                               act_v_1_0_to_1_1;
  logic signed [      DATA_WIDTH-1:0] wgt_1_0_to_2_0;
  logic                               wgt_v_1_0_to_2_0;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_1_0_to_2_0;
  logic                               psum_v_1_0_to_2_0;
  logic signed [      DATA_WIDTH-1:0] act_1_1_to_1_2;
  logic                               act_v_1_1_to_1_2;
  logic signed [      DATA_WIDTH-1:0] wgt_1_1_to_2_1;
  logic                               wgt_v_1_1_to_2_1;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_1_1_to_2_1;
  logic                               psum_v_1_1_to_2_1;
  logic signed [      DATA_WIDTH-1:0] wgt_1_2_to_2_2;
  logic                               wgt_v_1_2_to_2_2;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_1_2_to_2_2;
  logic                               psum_v_1_2_to_2_2;
  logic signed [      DATA_WIDTH-1:0] act_2_0_to_2_1;
  logic                               act_v_2_0_to_2_1;
  logic                               wgt_v_2_0_done;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_2_0_out;
  logic                               psum_v_2_0_out;
  logic signed [      DATA_WIDTH-1:0] act_2_1_to_2_2;
  logic                               act_v_2_1_to_2_2;
  logic                               wgt_v_2_1_done;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_2_1_out;
  logic                               psum_v_2_1_out;
  logic                               wgt_v_2_2_done;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_2_2_out;
  logic                               psum_v_2_2_out;

  // ========================================================
  // Output packing
  // ========================================================
  assign psum_flatten_o[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = psum_2_0_out;
  assign psum_valid_o[0] = psum_v_2_0_out;
  assign wgt_load_done_o[0] = wgt_v_2_0_done;
  assign psum_flatten_o[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = psum_2_1_out;
  assign psum_valid_o[1] = psum_v_2_1_out;
  assign wgt_load_done_o[1] = wgt_v_2_1_done;
  assign psum_flatten_o[(2*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = psum_2_2_out;
  assign psum_valid_o[2] = psum_v_2_2_out;
  assign wgt_load_done_o[2] = wgt_v_2_2_done;

  // ========================================================
  // PE array instantiation
  // ========================================================

  // ---------------- ROW 0 ----------------
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_0_0 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_row0_i),
      .act_valid_i(act_valid_i[0]),
      .act_o      (act_0_0_to_0_1),
      .act_valid_o(act_v_0_0_to_0_1),

      .psum_i      ({LOCAL_PSUM_WIDTH{1'b0}}),
      .psum_valid_i(act_valid_i[0]),
      .psum_o      (psum_0_0_to_1_0),
      .psum_valid_o(psum_v_0_0_to_1_0),

      .weight_i       (wgt_col0_i),
      .weight_load_i  (wgt_load_i[0]),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_0_0_to_1_0),
      .weight_valid_o (wgt_v_0_0_to_1_0),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(0*SIZE)+0])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_0_1 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_0_0_to_0_1),
      .act_valid_i(act_v_0_0_to_0_1),
      .act_o      (act_0_1_to_0_2),
      .act_valid_o(act_v_0_1_to_0_2),

      .psum_i      ({LOCAL_PSUM_WIDTH{1'b0}}),
      .psum_valid_i(act_v_0_0_to_0_1),
      .psum_o      (psum_0_1_to_1_1),
      .psum_valid_o(psum_v_0_1_to_1_1),

      .weight_i       (wgt_col1_i),
      .weight_load_i  (wgt_load_i[1]),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_0_1_to_1_1),
      .weight_valid_o (wgt_v_0_1_to_1_1),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(0*SIZE)+1])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_0_2 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_0_1_to_0_2),
      .act_valid_i(act_v_0_1_to_0_2),
      .act_o      (),
      .act_valid_o(),

      .psum_i      ({LOCAL_PSUM_WIDTH{1'b0}}),
      .psum_valid_i(act_v_0_1_to_0_2),
      .psum_o      (psum_0_2_to_1_2),
      .psum_valid_o(psum_v_0_2_to_1_2),

      .weight_i       (wgt_col2_i),
      .weight_load_i  (wgt_load_i[2]),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_0_2_to_1_2),
      .weight_valid_o (wgt_v_0_2_to_1_2),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(0*SIZE)+2])
  );


  // ---------------- ROW 1 ----------------
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_1_0 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_row1_i),
      .act_valid_i(act_valid_i[1]),
      .act_o      (act_1_0_to_1_1),
      .act_valid_o(act_v_1_0_to_1_1),

      .psum_i      (psum_0_0_to_1_0),
      .psum_valid_i(psum_v_0_0_to_1_0),
      .psum_o      (psum_1_0_to_2_0),
      .psum_valid_o(psum_v_1_0_to_2_0),

      .weight_i       (wgt_0_0_to_1_0),
      .weight_load_i  (wgt_v_0_0_to_1_0),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_1_0_to_2_0),
      .weight_valid_o (wgt_v_1_0_to_2_0),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(1*SIZE)+0])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_1_1 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_1_0_to_1_1),
      .act_valid_i(act_v_1_0_to_1_1),
      .act_o      (act_1_1_to_1_2),
      .act_valid_o(act_v_1_1_to_1_2),

      .psum_i      (psum_0_1_to_1_1),
      .psum_valid_i(psum_v_0_1_to_1_1),
      .psum_o      (psum_1_1_to_2_1),
      .psum_valid_o(psum_v_1_1_to_2_1),

      .weight_i       (wgt_0_1_to_1_1),
      .weight_load_i  (wgt_v_0_1_to_1_1),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_1_1_to_2_1),
      .weight_valid_o (wgt_v_1_1_to_2_1),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(1*SIZE)+1])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_1_2 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_1_1_to_1_2),
      .act_valid_i(act_v_1_1_to_1_2),
      .act_o      (),
      .act_valid_o(),

      .psum_i      (psum_0_2_to_1_2),
      .psum_valid_i(psum_v_0_2_to_1_2),
      .psum_o      (psum_1_2_to_2_2),
      .psum_valid_o(psum_v_1_2_to_2_2),

      .weight_i       (wgt_0_2_to_1_2),
      .weight_load_i  (wgt_v_0_2_to_1_2),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_1_2_to_2_2),
      .weight_valid_o (wgt_v_1_2_to_2_2),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(1*SIZE)+2])
  );


  // ---------------- ROW 2 ----------------
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_2_0 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_row2_i),
      .act_valid_i(act_valid_i[2]),
      .act_o      (act_2_0_to_2_1),
      .act_valid_o(act_v_2_0_to_2_1),

      .psum_i      (psum_1_0_to_2_0),
      .psum_valid_i(psum_v_1_0_to_2_0),
      .psum_o      (psum_2_0_out),
      .psum_valid_o(psum_v_2_0_out),

      .weight_i       (wgt_1_0_to_2_0),
      .weight_load_i  (wgt_v_1_0_to_2_0),
      .weight_switch_i(weight_switch_i),
      .weight_o       (),
      .weight_valid_o (wgt_v_2_0_done),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(2*SIZE)+0])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_2_1 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_2_0_to_2_1),
      .act_valid_i(act_v_2_0_to_2_1),
      .act_o      (act_2_1_to_2_2),
      .act_valid_o(act_v_2_1_to_2_2),

      .psum_i      (psum_1_1_to_2_1),
      .psum_valid_i(psum_v_1_1_to_2_1),
      .psum_o      (psum_2_1_out),
      .psum_valid_o(psum_v_2_1_out),

      .weight_i       (wgt_1_1_to_2_1),
      .weight_load_i  (wgt_v_1_1_to_2_1),
      .weight_switch_i(weight_switch_i),
      .weight_o       (),
      .weight_valid_o (wgt_v_2_1_done),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(2*SIZE)+1])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_2_2 (
      .clk  (clk),
      .rst_n(rst_n),

      .act_i      (act_2_1_to_2_2),
      .act_valid_i(act_v_2_1_to_2_2),
      .act_o      (),
      .act_valid_o(),

      .psum_i      (psum_1_2_to_2_2),
      .psum_valid_i(psum_v_1_2_to_2_2),
      .psum_o      (psum_2_2_out),
      .psum_valid_o(psum_v_2_2_out),

      .weight_i       (wgt_1_2_to_2_2),
      .weight_load_i  (wgt_v_1_2_to_2_2),
      .weight_switch_i(weight_switch_i),
      .weight_o       (),
      .weight_valid_o (wgt_v_2_2_done),

      .overflow_clr_i(overflow_clr_i),
      .overflow_o    (overflow_flatten_o[(2*SIZE)+2])
  );

endmodule : ws_sa_3x3

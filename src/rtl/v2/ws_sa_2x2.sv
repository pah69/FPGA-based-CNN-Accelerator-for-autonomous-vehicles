`timescale 1ns / 1ps

module ws_sa_2x2 #(
    parameter int SIZE               = 2,
    parameter int DATA_WIDTH         = 8,
    parameter int LOCAL_PSUM_WIDTH   = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int NUM_TILES          = SIZE,
    parameter int ACC_WIDTH          = 32,
    parameter bit ENABLE_LOCAL_ACCUM = 1'b1,
    parameter int TILE_COUNT_WIDTH   = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic work_i,
    // Runtime tile count used only by the optional local accumulators.
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

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

    // Accumulated outputs from the bottom-row psum stream.
    output logic signed [(ACC_WIDTH*SIZE)-1:0] result_flatten_o,
    output logic                               done_o,

    // High after the weight stream reaches the bottom PE of each column.
    output logic [SIZE-1:0] wgt_load_done_o,

    // Sticky overflow flags from every PE: bit index = row*SIZE + column.
    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o
);

  // ========================================================
  // Input unpacking
  // ========================================================
  logic signed [DATA_WIDTH-1:0] act_row0_i;
  assign act_row0_i = act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] act_row1_i;
  assign act_row1_i = act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];

  logic signed [DATA_WIDTH-1:0] wgt_col0_i;
  assign wgt_col0_i = wgt_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH];
  logic signed [DATA_WIDTH-1:0] wgt_col1_i;
  assign wgt_col1_i = wgt_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH];

  // ========================================================
  // Internal routing wires
  // ========================================================
  // ROW 0 -> ROW 1 connections
  logic signed [      DATA_WIDTH-1:0] act_0_0_to_0_1;
  logic                               act_v_0_0_to_0_1;
  logic signed [      DATA_WIDTH-1:0] wgt_0_0_to_1_0;
  logic                               wgt_v_0_0_to_1_0;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_0_0_to_1_0;
  logic                               psum_v_0_0_to_1_0;

  logic signed [      DATA_WIDTH-1:0] wgt_0_1_to_1_1;
  logic                               wgt_v_0_1_to_1_1;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_0_1_to_1_1;
  logic                               psum_v_0_1_to_1_1;

  // ROW 1 connections (Outputs)
  logic signed [      DATA_WIDTH-1:0] act_1_0_to_1_1;
  logic                               act_v_1_0_to_1_1;

  logic                               wgt_v_1_0_done;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_1_0_out;
  logic                               psum_v_1_0_out;

  logic                               wgt_v_1_1_done;
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_1_1_out;
  logic                               psum_v_1_1_out;

  logic signed [       ACC_WIDTH-1:0] result_1_0_acc;
  logic signed [       ACC_WIDTH-1:0] result_1_1_acc;
  logic                               acc_done_1_0;
  logic                               acc_done_1_1;

  // ========================================================
  // Output packing
  // ========================================================
  assign psum_flatten_o[(0*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = psum_1_0_out;
  assign psum_valid_o[0] = psum_v_1_0_out;
  assign wgt_load_done_o[0] = wgt_v_1_0_done;

  assign psum_flatten_o[(1*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] = psum_1_1_out;
  assign psum_valid_o[1] = psum_v_1_1_out;
  assign wgt_load_done_o[1] = wgt_v_1_1_done;

  assign result_flatten_o[(0*ACC_WIDTH)+:ACC_WIDTH] = result_1_0_acc;
  assign result_flatten_o[(1*ACC_WIDTH)+:ACC_WIDTH] = result_1_1_acc;
  assign done_o = acc_done_1_0 && acc_done_1_1;

  // ========================================================
  // PE array instantiation
  // ========================================================

  // ---------------- ROW 0 ----------------
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_0_0 (
      .clk            (clk),
      .rst_n          (rst_n),
      .act_i          (act_row0_i),
      .act_valid_i    (act_valid_i[0]),
      .act_o          (act_0_0_to_0_1),
      .act_valid_o    (act_v_0_0_to_0_1),
      .psum_i         ({LOCAL_PSUM_WIDTH{1'b0}}),
      .psum_valid_i   (act_valid_i[0]),
      .psum_o         (psum_0_0_to_1_0),
      .psum_valid_o   (psum_v_0_0_to_1_0),
      .weight_i       (wgt_col0_i),
      .weight_load_i  (wgt_load_i[0]),
      .weight_switch_i(weight_switch_i),
      .weight_o       (wgt_0_0_to_1_0),
      .weight_valid_o (wgt_v_0_0_to_1_0),
      .overflow_clr_i (overflow_clr_i),
      .overflow_o     (overflow_flatten_o[(0*SIZE)+0])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_0_1 (
      .clk(clk),
      .rst_n(rst_n),
      .act_i(act_0_0_to_0_1),
      .act_valid_i(act_v_0_0_to_0_1),
      .act_o(),  // Đầu ra bỏ trống vì nằm ở rìa phải
      .act_valid_o(),
      .psum_i({LOCAL_PSUM_WIDTH{1'b0}}),
      .psum_valid_i(act_v_0_0_to_0_1),
      .psum_o(psum_0_1_to_1_1),
      .psum_valid_o(psum_v_0_1_to_1_1),
      .weight_i(wgt_col1_i),
      .weight_load_i(wgt_load_i[1]),
      .weight_switch_i(weight_switch_i),
      .weight_o(wgt_0_1_to_1_1),
      .weight_valid_o(wgt_v_0_1_to_1_1),
      .overflow_clr_i(overflow_clr_i),
      .overflow_o(overflow_flatten_o[(0*SIZE)+1])
  );

  // ---------------- ROW 1 ----------------
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_1_0 (
      .clk(clk),
      .rst_n(rst_n),
      .act_i(act_row1_i),
      .act_valid_i(act_valid_i[1]),
      .act_o(act_1_0_to_1_1),
      .act_valid_o(act_v_1_0_to_1_1),
      .psum_i(psum_0_0_to_1_0),
      .psum_valid_i(psum_v_0_0_to_1_0),
      .psum_o(psum_1_0_out),
      .psum_valid_o(psum_v_1_0_out),
      .weight_i(wgt_0_0_to_1_0),
      .weight_load_i(wgt_v_0_0_to_1_0),
      .weight_switch_i(weight_switch_i),
      .weight_o(),  // Đầu ra bỏ trống vì nằm ở đáy
      .weight_valid_o(wgt_v_1_0_done),
      .overflow_clr_i(overflow_clr_i),
      .overflow_o(overflow_flatten_o[(1*SIZE)+0])
  );

  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
  ) pe_1_1 (
      .clk            (clk),
      .rst_n          (rst_n),
      .act_i          (act_1_0_to_1_1),
      .act_valid_i    (act_v_1_0_to_1_1),
      .act_o          (),
      .act_valid_o    (),
      .psum_i         (psum_0_1_to_1_1),
      .psum_valid_i   (psum_v_0_1_to_1_1),
      .psum_o         (psum_1_1_out),
      .psum_valid_o   (psum_v_1_1_out),
      .weight_i       (wgt_0_1_to_1_1),
      .weight_load_i  (wgt_v_0_1_to_1_1),
      .weight_switch_i(weight_switch_i),
      .weight_o       (),
      .weight_valid_o (wgt_v_1_1_done),
      .overflow_clr_i (overflow_clr_i),
      .overflow_o     (overflow_flatten_o[(1*SIZE)+1])
  );

  generate
    if (ENABLE_LOCAL_ACCUM) begin : GEN_LOCAL_ACCUM
      localparam int WORK_PROP_DELAY = 4;

      logic [(WORK_PROP_DELAY*SIZE)-1:0] work_pipe;
      logic                              acc_work_1_0;
      logic                              acc_work_1_1;

      assign acc_work_1_0 = work_pipe[WORK_PROP_DELAY-1];
      assign acc_work_1_1 = work_pipe[(2*WORK_PROP_DELAY)-1];

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          work_pipe <= '0;
        end else begin
          work_pipe[0] <= work_i;
          for (int idx = 1; idx < (WORK_PROP_DELAY * SIZE); idx++) begin
            work_pipe[idx] <= work_pipe[idx-1];
          end
        end
      end

      output_accumulator_v2 #(
          .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
          .ACC_WIDTH       (ACC_WIDTH),
          .NUM_TILES       (NUM_TILES)
      ) out_acc_1_0 (
          .clk         (clk),
          .rst_n       (rst_n),
          .work_i      (acc_work_1_0),
          .num_tiles_i (num_tiles_i),
          .psum_i      (psum_1_0_out),
          .psum_valid_i(psum_v_1_0_out),
          .result_o    (result_1_0_acc),
          .done_o      (acc_done_1_0)
      );

      output_accumulator_v2 #(
          .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
          .ACC_WIDTH       (ACC_WIDTH),
          .NUM_TILES       (NUM_TILES)
      ) out_acc_1_1 (
          .clk         (clk),
          .rst_n       (rst_n),
          .work_i      (acc_work_1_1),
          .num_tiles_i (num_tiles_i),
          .psum_i      (psum_1_1_out),
          .psum_valid_i(psum_v_1_1_out),
          .result_o    (result_1_1_acc),
          .done_o      (acc_done_1_1)
      );
    end else begin : GEN_NO_LOCAL_ACCUM
      assign result_1_0_acc = '0;
      assign result_1_1_acc = '0;
      assign acc_done_1_0   = work_i & 1'b0;
      assign acc_done_1_1   = 1'b0;
    end
  endgenerate

endmodule : ws_sa_2x2

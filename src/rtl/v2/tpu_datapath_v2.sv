`timescale 1ns / 1ps

// TPU-style datapath without the unified buffer.
module tpu_datapath_v2 #(
    parameter int SIZE              = 2,
    parameter int DATA_WIDTH        = 8,
    parameter int LOCAL_PSUM_WIDTH  = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int NUM_TILES         = SIZE,
    parameter int ACC_WIDTH         = 32,
    parameter int ACC_DEPTH         = 16,
    parameter int ACC_ADDR_WIDTH    = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int ACT_WIDTH         = ACC_WIDTH,
    parameter int OUT_WIDTH         = 8,
    parameter int ACT_MODE          = 1,
    parameter int ACT_CLIP_MAX      = 6,
    parameter int ACT_INPUT_SHIFT   = 0,
    parameter int ACT_FRAC_BITS     = 8,
    parameter int NORM_SHIFT        = 0,
    parameter bit NORM_ROUND_ENABLE = 1'b1,
    parameter int POOL_MODE         = 0,
    parameter int POOL_WINDOW       = 2,
    parameter int WGT_FIFO_DEPTH    = 16,
    parameter int TILE_COUNT_WIDTH  = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic work_i,
    // Number of K-dimension tiles for the current workload: ceil(K / SIZE).
    // For odd K, the padded tail tile still counts here.
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input  logic start_wgt_load_i,
    output logic wgt_fetcher_ready_o,

    input  logic [(DATA_WIDTH*SIZE)-1:0] wgt_fifo_wdata_i,
    input  logic                         wgt_fifo_wr_en_i,
    output logic                         wgt_fifo_full_o,
    output logic                         wgt_fifo_empty_o,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_i,
    input logic        [SIZE-1:0]              act_valid_raw_i,

    input logic                           accumulator_clear_all_i,
    input logic                           accumulator_row_clear_i,
    input logic [ACC_ADDR_WIDTH-1:0]     accumulator_row_clear_addr_i,
    input logic                           accumulator_write_en_i,
    input logic [ACC_ADDR_WIDTH-1:0]     accumulator_write_addr_i,
    input logic                           accumulator_read_en_i,
    input logic [ACC_ADDR_WIDTH-1:0]     accumulator_read_addr_i,

    input logic                           vpu_input_done_i,

    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_o,
    output logic        [SIZE-1:0]                    mxu_psum_valid_o,
    output logic        [SIZE-1:0]                    wgt_load_done_o,

    output logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_o,
    output logic                                accumulator_read_valid_o,
    output logic                                accumulator_row_done_o,
    output logic [ACC_ADDR_WIDTH-1:0]          accumulator_row_done_addr_o,
    output logic [ACC_DEPTH-1:0]               accumulator_row_ready_o,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_o,
    output logic                               vpu_data_valid_o,
    output logic                               done_o,

    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o
);

  logic [SIZE-1:0] wgt_load_done_w;

  logic signed [(ACC_WIDTH*SIZE)-1:0] mxu_local_acc_result_w;
  logic                                mxu_local_acc_done_w;

  logic                                accumulator_write_en_w;
  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_w;
  logic                                accumulator_read_valid_w;
  logic                                accumulator_row_done_w;
  logic [ACC_ADDR_WIDTH-1:0]          accumulator_row_done_addr_w;
  logic [ACC_DEPTH-1:0]               accumulator_row_ready_w;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_w;
  logic                                vpu_data_valid_w;
  logic                                vpu_done_w;

  assign accumulator_write_en_w = accumulator_write_en_i && (|mxu_psum_valid_o);

  mxu_2x2 #(
      .SIZE              (SIZE),
      .DATA_WIDTH        (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH  (LOCAL_PSUM_WIDTH),
      .NUM_TILES         (NUM_TILES),
      .ACC_WIDTH         (ACC_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b0),
      .WGT_FIFO_DEPTH    (WGT_FIFO_DEPTH),
      .TILE_COUNT_WIDTH  (TILE_COUNT_WIDTH)
  ) u_mxu (
      .clk               (clk),
      .rst_n             (rst_n),
      .work_i            (work_i),
      .num_tiles_i       (num_tiles_i),
      .start_wgt_load_i  (start_wgt_load_i),
      .wgt_fetcher_ready_o(wgt_fetcher_ready_o),
      .wgt_fifo_wdata_i  (wgt_fifo_wdata_i),
      .wgt_fifo_wr_en_i  (wgt_fifo_wr_en_i),
      .wgt_fifo_full_o   (wgt_fifo_full_o),
      .wgt_fifo_empty_o  (wgt_fifo_empty_o),
      .act_flat_raw_i    (act_flat_raw_i),
      .act_valid_raw_i   (act_valid_raw_i),
      .psum_flatten_o    (mxu_psum_flatten_o),
      .psum_valid_o      (mxu_psum_valid_o),
      .result_flatten_o  (mxu_local_acc_result_w),
      .done_o            (mxu_local_acc_done_w),
      .wgt_load_done_o   (wgt_load_done_w),
      .overflow_clr_i    (overflow_clr_i),
      .overflow_flatten_o(overflow_flatten_o)
  );

  accumulator_array_v2 #(
      .SIZE            (SIZE),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .ACC_WIDTH       (ACC_WIDTH),
      .DEPTH           (ACC_DEPTH),
      .ADDR_WIDTH      (ACC_ADDR_WIDTH),
      .NUM_TILES       (NUM_TILES),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH)
  ) u_accumulator_array (
      .clk             (clk),
      .rst_n           (rst_n),
      .clear_all_i     (accumulator_clear_all_i),
      .num_tiles_i     (num_tiles_i),
      .row_clear_i     (accumulator_row_clear_i),
      .row_clear_addr_i(accumulator_row_clear_addr_i),
      .write_en_i      (accumulator_write_en_w),
      .write_addr_i    (accumulator_write_addr_i),
      .psum_flatten_i  (mxu_psum_flatten_o),
      .psum_valid_i    (mxu_psum_valid_o),
      .read_en_i       (accumulator_read_en_i),
      .read_addr_i     (accumulator_read_addr_i),
      .read_data_flatten_o(accumulator_read_flatten_w),
      .read_valid_o    (accumulator_read_valid_w),
      .row_done_o      (accumulator_row_done_w),
      .row_done_addr_o (accumulator_row_done_addr_w),
      .row_ready_o     (accumulator_row_ready_w)
  );

  vector_processing_unit_v2 #(
      .SIZE             (SIZE),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACT_WIDTH        (ACT_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_MODE),
      .ACT_CLIP_MAX     (ACT_CLIP_MAX),
      .ACT_INPUT_SHIFT  (ACT_INPUT_SHIFT),
      .ACT_FRAC_BITS    (ACT_FRAC_BITS),
      .NORM_SHIFT       (NORM_SHIFT),
      .NORM_ROUND_ENABLE(NORM_ROUND_ENABLE),
      .POOL_MODE        (POOL_MODE),
      .POOL_WINDOW      (POOL_WINDOW)
  ) u_vector_processing_unit (
      .clk           (clk),
      .rst_n         (rst_n),
      .acc_flatten_i (accumulator_read_flatten_w),
      .acc_valid_i   (accumulator_read_valid_w),
      .done_i        (vpu_input_done_i),
      .data_flatten_o(vpu_data_flatten_w),
      .data_valid_o  (vpu_data_valid_w),
      .done_o        (vpu_done_w)
  );

  assign wgt_load_done_o              = wgt_load_done_w;
  assign accumulator_read_flatten_o   = accumulator_read_flatten_w | (mxu_local_acc_result_w & '0);
  assign accumulator_read_valid_o     = accumulator_read_valid_w;
  assign accumulator_row_done_o       = accumulator_row_done_w;
  assign accumulator_row_done_addr_o  = accumulator_row_done_addr_w;
  assign accumulator_row_ready_o      = accumulator_row_ready_w;
  assign vpu_data_flatten_o           = vpu_data_flatten_w;
  assign vpu_data_valid_o             = vpu_data_valid_w;
  assign done_o                       = vpu_done_w | (mxu_local_acc_done_w & 1'b0);

endmodule : tpu_datapath_v2

`timescale 1ns / 1ps

// V3 2x2 MXU compatibility wrapper.
//
// This is the first integration point for the V3 activation and weight
// buffering blocks. It keeps the proven 2x2 WS systolic array underneath, but
// replaces the old direct activation feed and FIFO weight path with:
//
//   activation_window_gather_v3 -> act_skew_buffer_2x2 -> ws_sa_2x2
//   weight_tile_buffer_v3       -----------------------> ws_sa_2x2
//
// The controller still owns address generation and schedule timing.
module mxu_v3 #(
    parameter int SIZE               = 2,
    parameter int DATA_WIDTH         = 8,
    parameter int ACT_ADDR_WIDTH     = 13,
    parameter int WGT_ADDR_WIDTH     = 16,
    parameter int TAG_WIDTH          = 16,
    parameter int LOCAL_PSUM_WIDTH   = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int NUM_TILES          = SIZE,
    parameter int ACC_WIDTH          = 32,
    parameter int ACT_FIFO_DEPTH     = 4,
    parameter int COUNTER_WIDTH      = 32,
    parameter int TILE_COUNT_WIDTH   = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1,
    parameter int MAC_COUNT_WIDTH    = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,
    input logic compute_enable_i,
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input  logic                          act_req_valid_i,
    output logic                          act_req_ready_o,
    input  logic [SIZE*ACT_ADDR_WIDTH-1:0] act_req_addr_flatten_i,
    input  logic [SIZE-1:0]                act_req_lane_valid_i,
    input  logic [SIZE-1:0]                act_req_lane_zero_i,
    input  logic [TAG_WIDTH-1:0]           act_req_tag_i,

    output logic                         ub_rd_en_o,
    output logic [ACT_ADDR_WIDTH-1:0]    ub_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] ub_rd_data_i,
    input  logic                         ub_rd_valid_i,

    input  logic                               wgt_req_valid_i,
    output logic                               wgt_req_ready_o,
    input  logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0] wgt_req_addr_flatten_i,
    input  logic [SIZE*SIZE-1:0]               wgt_req_valid_mask_i,
    input  logic [SIZE*SIZE-1:0]               wgt_req_zero_mask_i,
    input  logic [TAG_WIDTH-1:0]               wgt_req_tag_i,
    input  logic                               wgt_tile_release_i,
    input  logic                               wgt_stream_start_i,
    output logic                               wgt_stream_ready_o,
    output logic                               wgt_tile_valid_o,
    output logic [TAG_WIDTH-1:0]               wgt_tile_tag_o,
    output logic                               wgt_stream_done_o,

    output logic                         weight_rd_en_o,
    output logic [WGT_ADDR_WIDTH-1:0]    weight_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] weight_rd_data_i,
    input  logic                         weight_rd_valid_i,

    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,
    output logic [SIZE-1:0]                         psum_valid_o,
    output logic [MAC_COUNT_WIDTH-1:0]               valid_mac_count_o,
    output logic signed [(ACC_WIDTH*SIZE)-1:0]       result_flatten_o,
    output logic                                     done_o,
    output logic [SIZE-1:0]                          wgt_load_done_o,

    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o,

    output logic busy_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_fetch_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_output_stall_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_vectors_pushed_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_lane_reads_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_load_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_reuse_count_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_empty_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_full_cycles_o
);

  logic signed [(DATA_WIDTH*SIZE)-1:0] act_vec_flatten_w;
  logic [SIZE-1:0] act_vec_valid_mask_w;
  logic act_vec_valid_w;
  logic act_vec_ready_w;
  logic act_gather_busy_w;
  logic act_fifo_full_w;
  logic act_fifo_empty_w;

  logic signed [(DATA_WIDTH*SIZE)-1:0] act_raw_flatten_w;
  logic [SIZE-1:0] act_raw_valid_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_skewed_w;
  logic [SIZE-1:0] act_valid_skewed_w;

  logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_row_flatten_w;
  logic [SIZE-1:0] wgt_row_load_w;
  logic weight_switch_w;
  logic wgt_buffer_busy_w;

  assign act_vec_ready_w = act_vec_valid_w;
  assign act_raw_flatten_w = act_vec_valid_w ? act_vec_flatten_w : '0;
  assign act_raw_valid_w = act_vec_valid_w ? act_vec_valid_mask_w : '0;
  assign busy_o = act_gather_busy_w || wgt_buffer_busy_w;

  activation_window_gather_v3 #(
      .ARRAY_K      (SIZE),
      .DATA_WIDTH   (DATA_WIDTH),
      .ADDR_WIDTH   (ACT_ADDR_WIDTH),
      .TAG_WIDTH    (TAG_WIDTH),
      .FIFO_DEPTH   (ACT_FIFO_DEPTH),
      .COUNTER_WIDTH(COUNTER_WIDTH)
  ) u_act_gather (
      .clk                      (clk),
      .rst_n                    (rst_n),
      .clear_i                  (clear_i),
      .req_valid_i              (act_req_valid_i),
      .req_ready_o              (act_req_ready_o),
      .req_addr_flatten_i       (act_req_addr_flatten_i),
      .req_lane_valid_i         (act_req_lane_valid_i),
      .req_lane_zero_i          (act_req_lane_zero_i),
      .req_tag_i                (act_req_tag_i),
      .ub_rd_en_o               (ub_rd_en_o),
      .ub_rd_addr_o             (ub_rd_addr_o),
      .ub_rd_data_i             (ub_rd_data_i),
      .ub_rd_valid_i            (ub_rd_valid_i),
      .act_vec_flatten_o        (act_vec_flatten_w),
      .act_valid_o              (act_vec_valid_mask_w),
      .act_tag_o                (),
      .act_vec_valid_o          (act_vec_valid_w),
      .act_vec_ready_i          (act_vec_ready_w),
      .busy_o                   (act_gather_busy_w),
      .fifo_full_o              (act_fifo_full_w),
      .fifo_empty_o             (act_fifo_empty_w),
      .dbg_fetch_cycles_o       (dbg_act_fetch_cycles_o),
      .dbg_output_stall_cycles_o(dbg_act_output_stall_cycles_o),
      .dbg_vectors_pushed_o     (dbg_act_vectors_pushed_o),
      .dbg_lane_reads_o         (dbg_act_lane_reads_o)
  );

  act_skew_buffer_2x2 #(
      .SIZE      (SIZE),
      .DATA_WIDTH(DATA_WIDTH)
  ) u_skew_buffer (
      .clk               (clk),
      .rst_n             (rst_n),
      .act_flat_raw_i    (act_raw_flatten_w),
      .act_valid_raw_i   (act_raw_valid_w),
      .act_skewed_o      (act_skewed_w),
      .act_valid_skewed_o(act_valid_skewed_w)
  );

  weight_tile_buffer_v3 #(
      .ARRAY_K      (SIZE),
      .ARRAY_OC     (SIZE),
      .DATA_WIDTH   (DATA_WIDTH),
      .ADDR_WIDTH   (WGT_ADDR_WIDTH),
      .TAG_WIDTH    (TAG_WIDTH),
      .COUNTER_WIDTH(COUNTER_WIDTH)
  ) u_weight_buffer (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .clear_i                         (clear_i),
      .tile_release_i                  (wgt_tile_release_i),
      .req_valid_i                     (wgt_req_valid_i),
      .req_ready_o                     (wgt_req_ready_o),
      .req_addr_flatten_i              (wgt_req_addr_flatten_i),
      .req_weight_valid_i              (wgt_req_valid_mask_i),
      .req_weight_zero_i               (wgt_req_zero_mask_i),
      .req_tag_i                       (wgt_req_tag_i),
      .weight_rd_en_o                  (weight_rd_en_o),
      .weight_rd_addr_o                (weight_rd_addr_o),
      .weight_rd_data_i                (weight_rd_data_i),
      .weight_rd_valid_i               (weight_rd_valid_i),
      .tile_flatten_o                  (),
      .tile_valid_mask_o               (),
      .tile_tag_o                      (wgt_tile_tag_o),
      .tile_valid_o                    (wgt_tile_valid_o),
      .stream_start_i                  (wgt_stream_start_i),
      .stream_ready_o                  (wgt_stream_ready_o),
      .wgt_row_flatten_o               (wgt_row_flatten_w),
      .wgt_row_load_o                  (wgt_row_load_w),
      .weight_switch_o                 (weight_switch_w),
      .stream_done_o                   (wgt_stream_done_o),
      .busy_o                          (wgt_buffer_busy_w),
      .dbg_weight_load_cycles_o        (dbg_weight_load_cycles_o),
      .dbg_weight_reuse_count_o        (dbg_weight_reuse_count_o),
      .dbg_weight_buffer_empty_cycles_o(dbg_weight_buffer_empty_cycles_o),
      .dbg_weight_buffer_full_cycles_o (dbg_weight_buffer_full_cycles_o)
  );

  ws_sa_2x2 #(
      .SIZE              (SIZE),
      .DATA_WIDTH        (DATA_WIDTH),
      .LOCAL_PSUM_WIDTH  (LOCAL_PSUM_WIDTH),
      .NUM_TILES         (NUM_TILES),
      .ACC_WIDTH         (ACC_WIDTH),
      .ENABLE_LOCAL_ACCUM(1'b0),
      .TILE_COUNT_WIDTH  (TILE_COUNT_WIDTH),
      .MAC_COUNT_WIDTH   (MAC_COUNT_WIDTH)
  ) u_systolic_array (
      .clk               (clk),
      .rst_n             (rst_n),
      .work_i            (compute_enable_i && act_vec_valid_w),
      .num_tiles_i       (num_tiles_i),
      .wgt_flatten_i     (wgt_row_flatten_w),
      .wgt_load_i        (wgt_row_load_w),
      .weight_switch_i   (weight_switch_w),
      .act_flatten_i     (act_skewed_w),
      .act_valid_i       (act_valid_skewed_w),
      .psum_flatten_o    (psum_flatten_o),
      .psum_valid_o      (psum_valid_o),
      .valid_mac_count_o (valid_mac_count_o),
      .result_flatten_o  (result_flatten_o),
      .done_o            (done_o),
      .wgt_load_done_o   (wgt_load_done_o),
      .overflow_clr_i    (overflow_clr_i),
      .overflow_flatten_o(overflow_flatten_o)
  );

endmodule : mxu_v3

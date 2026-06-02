`timescale 1ns / 1ps

// V3 TPU datapath, 2x2 compatibility stage.
//
// This keeps the proven V2 post-MXU path:
//   psum_packer_v2 -> accumulator_array_v2 -> vector_processing_unit_v2
//
// The MXU input side is upgraded to:
//   activation_window_gather_v3 + weight_tile_buffer_v3 inside mxu_v3
module tpu_datapath_v3 #(
    parameter int SIZE                = 2,
    parameter int DATA_WIDTH          = 8,
    parameter int ACT_ADDR_WIDTH      = 13,
    parameter int WGT_ADDR_WIDTH      = 16,
    parameter int TAG_WIDTH           = 16,
    parameter int LOCAL_PSUM_WIDTH    = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int MAX_NUM_TILES       = 128,
    parameter int ACC_WIDTH           = 32,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int ACT_WIDTH           = ACC_WIDTH,
    parameter int OUT_WIDTH           = 8,
    parameter int ACT_MODE            = 1,
    parameter int ACT_CLIP_MAX        = 6,
    parameter int ACT_INPUT_SHIFT     = 0,
    parameter int ACT_FRAC_BITS       = 8,
    parameter bit QUANT_ENABLE        = 1'b0,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int QUANT_CLAMP_MIN     = -128,
    parameter int QUANT_CLAMP_MAX     = 127,
    parameter int NORM_SHIFT          = 0,
    parameter bit NORM_ROUND_ENABLE   = 1'b1,
    parameter int POOL_MODE           = 0,
    parameter int POOL_WINDOW         = 2,
    parameter int ACT_FIFO_DEPTH      = 4,
    parameter bit GATED_ACT_LAUNCH    = 1'b0,
    parameter int COUNTER_WIDTH       = 32,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1,
    parameter int MAC_COUNT_WIDTH     = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,
    input logic compute_enable_i,
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input  logic                            act_req_valid_i,
    output logic                            act_req_ready_o,
    input  logic [SIZE*ACT_ADDR_WIDTH-1:0]  act_req_addr_flatten_i,
    input  logic [SIZE-1:0]                 act_req_lane_valid_i,
    input  logic [SIZE-1:0]                 act_req_lane_zero_i,
    input  logic [TAG_WIDTH-1:0]            act_req_tag_i,
    input  logic                            act_launch_i,
    output logic                            act_launch_ready_o,

    output logic                         ub_rd_en_o,
    output logic [ACT_ADDR_WIDTH-1:0]    ub_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] ub_rd_data_i,
    input  logic                         ub_rd_valid_i,

    input  logic                                 wgt_req_valid_i,
    output logic                                 wgt_req_ready_o,
    input  logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0]  wgt_req_addr_flatten_i,
    input  logic [SIZE*SIZE-1:0]                 wgt_req_valid_mask_i,
    input  logic [SIZE*SIZE-1:0]                 wgt_req_zero_mask_i,
    input  logic [TAG_WIDTH-1:0]                 wgt_req_tag_i,
    input  logic                                 wgt_tile_release_i,
    input  logic                                 wgt_stream_start_i,
    output logic                                 wgt_stream_ready_o,
    output logic                                 wgt_tile_valid_o,
    output logic [TAG_WIDTH-1:0]                 wgt_tile_tag_o,
    output logic                                 wgt_stream_done_o,

    output logic                         weight_rd_en_o,
    output logic [WGT_ADDR_WIDTH-1:0]    weight_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] weight_rd_data_i,
    input  logic                         weight_rd_valid_i,

    input logic                      accumulator_clear_all_i,
    input logic                      accumulator_row_clear_i,
    input logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_i,
    input logic                      accumulator_write_en_i,
    input logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_i,
    input logic                      accumulator_read_en_i,
    input logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_i,

    input logic                                         vpu_input_done_i,
    input logic [1:0]                                   vpu_act_mode_i,
    input logic signed [         (BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_i,
    input logic signed [ (REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_i,
    input logic        [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_i,
    input logic signed [                 ACC_WIDTH-1:0] vpu_output_zero_point_i,

    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_o,
    output logic [SIZE-1:0]                          mxu_psum_valid_o,
    output logic [MAC_COUNT_WIDTH-1:0]                mxu_valid_mac_count_o,
    output logic                                      psum_packer_busy_o,
    output logic [SIZE-1:0]                           wgt_load_done_o,

    output logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_o,
    output logic                               accumulator_read_valid_o,
    output logic                               accumulator_row_done_o,
    output logic [ACC_ADDR_WIDTH-1:0]          accumulator_row_done_addr_o,
    output logic [ACC_DEPTH-1:0]               accumulator_row_ready_o,

    output logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_o,
    output logic                               vpu_data_valid_o,
    output logic                               done_o,

    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o,

    output logic [COUNTER_WIDTH-1:0] dbg_act_fetch_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_output_stall_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_vectors_pushed_o,
    output logic [COUNTER_WIDTH-1:0] dbg_act_lane_reads_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_load_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_reuse_count_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_empty_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_full_cycles_o
);

  logic [SIZE-1:0] wgt_load_done_w;
  logic mxu_busy_w;

  logic signed [(ACC_WIDTH*SIZE)-1:0] mxu_local_acc_result_w;
  logic mxu_local_acc_done_w;

  logic                                      packed_psum_valid_w;
  logic [ACC_ADDR_WIDTH-1:0]                 packed_write_addr_w;
  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] packed_psum_flatten_w;
  logic [SIZE-1:0]                           packed_psum_lane_valid_w;

  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_w;
  logic accumulator_read_valid_w;
  logic accumulator_row_done_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_done_addr_w;
  logic [ACC_DEPTH-1:0] accumulator_row_ready_w;

  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_w;
  logic vpu_data_valid_w;
  logic vpu_done_w;

  mxu_v3 #(
      .SIZE            (SIZE),
      .DATA_WIDTH      (DATA_WIDTH),
      .ACT_ADDR_WIDTH  (ACT_ADDR_WIDTH),
      .WGT_ADDR_WIDTH  (WGT_ADDR_WIDTH),
      .TAG_WIDTH       (TAG_WIDTH),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .NUM_TILES       (MAX_NUM_TILES),
      .ACC_WIDTH       (ACC_WIDTH),
      .ACT_FIFO_DEPTH  (ACT_FIFO_DEPTH),
      .GATED_ACT_LAUNCH(GATED_ACT_LAUNCH),
      .COUNTER_WIDTH   (COUNTER_WIDTH),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH),
      .MAC_COUNT_WIDTH (MAC_COUNT_WIDTH)
  ) u_mxu (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (clear_i),
      .compute_enable_i                 (compute_enable_i),
      .num_tiles_i                      (num_tiles_i),
      .act_req_valid_i                  (act_req_valid_i),
      .act_req_ready_o                  (act_req_ready_o),
      .act_req_addr_flatten_i           (act_req_addr_flatten_i),
      .act_req_lane_valid_i             (act_req_lane_valid_i),
      .act_req_lane_zero_i              (act_req_lane_zero_i),
      .act_req_tag_i                    (act_req_tag_i),
      .act_launch_i                     (act_launch_i),
      .act_launch_ready_o               (act_launch_ready_o),
      .ub_rd_en_o                       (ub_rd_en_o),
      .ub_rd_addr_o                     (ub_rd_addr_o),
      .ub_rd_data_i                     (ub_rd_data_i),
      .ub_rd_valid_i                    (ub_rd_valid_i),
      .wgt_req_valid_i                  (wgt_req_valid_i),
      .wgt_req_ready_o                  (wgt_req_ready_o),
      .wgt_req_addr_flatten_i           (wgt_req_addr_flatten_i),
      .wgt_req_valid_mask_i             (wgt_req_valid_mask_i),
      .wgt_req_zero_mask_i              (wgt_req_zero_mask_i),
      .wgt_req_tag_i                    (wgt_req_tag_i),
      .wgt_tile_release_i               (wgt_tile_release_i),
      .wgt_stream_start_i               (wgt_stream_start_i),
      .wgt_stream_ready_o               (wgt_stream_ready_o),
      .wgt_tile_valid_o                 (wgt_tile_valid_o),
      .wgt_tile_tag_o                   (wgt_tile_tag_o),
      .wgt_stream_done_o                (wgt_stream_done_o),
      .weight_rd_en_o                   (weight_rd_en_o),
      .weight_rd_addr_o                 (weight_rd_addr_o),
      .weight_rd_data_i                 (weight_rd_data_i),
      .weight_rd_valid_i                (weight_rd_valid_i),
      .psum_flatten_o                   (mxu_psum_flatten_o),
      .psum_valid_o                     (mxu_psum_valid_o),
      .valid_mac_count_o                (mxu_valid_mac_count_o),
      .result_flatten_o                 (mxu_local_acc_result_w),
      .done_o                           (mxu_local_acc_done_w),
      .wgt_load_done_o                  (wgt_load_done_w),
      .overflow_clr_i                   (overflow_clr_i),
      .overflow_flatten_o               (overflow_flatten_o),
      .busy_o                           (mxu_busy_w),
      .dbg_act_fetch_cycles_o           (dbg_act_fetch_cycles_o),
      .dbg_act_output_stall_cycles_o    (dbg_act_output_stall_cycles_o),
      .dbg_act_vectors_pushed_o         (dbg_act_vectors_pushed_o),
      .dbg_act_lane_reads_o             (dbg_act_lane_reads_o),
      .dbg_weight_load_cycles_o         (dbg_weight_load_cycles_o),
      .dbg_weight_reuse_count_o         (dbg_weight_reuse_count_o),
      .dbg_weight_buffer_empty_cycles_o (dbg_weight_buffer_empty_cycles_o),
      .dbg_weight_buffer_full_cycles_o  (dbg_weight_buffer_full_cycles_o)
  );

  psum_packer_v2 #(
      .SIZE            (SIZE),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .ADDR_WIDTH      (ACC_ADDR_WIDTH)
  ) u_psum_packer (
      .clk                  (clk),
      .rst_n                (rst_n),
      .clear_i              (accumulator_clear_all_i),
      .capture_en_i         (accumulator_write_en_i),
      .write_addr_i         (accumulator_write_addr_i),
      .psum_flatten_i       (mxu_psum_flatten_o),
      .psum_valid_i         (mxu_psum_valid_o),
      .packed_valid_o       (packed_psum_valid_w),
      .packed_write_addr_o  (packed_write_addr_w),
      .packed_psum_flatten_o(packed_psum_flatten_w),
      .packed_psum_valid_o  (packed_psum_lane_valid_w),
      .busy_o               (psum_packer_busy_o)
  );

  accumulator_array_v2 #(
      .SIZE            (SIZE),
      .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
      .ACC_WIDTH       (ACC_WIDTH),
      .DEPTH           (ACC_DEPTH),
      .ADDR_WIDTH      (ACC_ADDR_WIDTH),
      .NUM_TILES       (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH(TILE_COUNT_WIDTH)
  ) u_accumulator_array (
      .clk                (clk),
      .rst_n              (rst_n),
      .clear_all_i        (accumulator_clear_all_i),
      .num_tiles_i        (num_tiles_i),
      .row_clear_i        (accumulator_row_clear_i),
      .row_clear_addr_i   (accumulator_row_clear_addr_i),
      .write_en_i         (packed_psum_valid_w),
      .write_addr_i       (packed_write_addr_w),
      .psum_flatten_i     (packed_psum_flatten_w),
      .psum_valid_i       (packed_psum_lane_valid_w),
      .read_en_i          (accumulator_read_en_i),
      .read_addr_i        (accumulator_read_addr_i),
      .read_data_flatten_o(accumulator_read_flatten_w),
      .read_valid_o       (accumulator_read_valid_w),
      .row_done_o         (accumulator_row_done_w),
      .row_done_addr_o    (accumulator_row_done_addr_w),
      .row_ready_o        (accumulator_row_ready_w)
  );

  vector_processing_unit_v2 #(
      .SIZE               (SIZE),
      .ACC_WIDTH          (ACC_WIDTH),
      .ACT_WIDTH          (ACT_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .ACT_MODE           (ACT_MODE),
      .ACT_CLIP_MAX       (ACT_CLIP_MAX),
      .ACT_INPUT_SHIFT    (ACT_INPUT_SHIFT),
      .ACT_FRAC_BITS      (ACT_FRAC_BITS),
      .QUANT_ENABLE       (QUANT_ENABLE),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .QUANT_CLAMP_MIN    (QUANT_CLAMP_MIN),
      .QUANT_CLAMP_MAX    (QUANT_CLAMP_MAX),
      .NORM_SHIFT         (NORM_SHIFT),
      .NORM_ROUND_ENABLE  (NORM_ROUND_ENABLE),
      .POOL_MODE          (POOL_MODE),
      .POOL_WINDOW        (POOL_WINDOW)
  ) u_vector_processing_unit (
      .clk                         (clk),
      .rst_n                       (rst_n),
      .acc_flatten_i               (accumulator_read_flatten_w),
      .acc_valid_i                 (accumulator_read_valid_w),
      .done_i                      (vpu_input_done_i),
      .act_mode_i                  (vpu_act_mode_i),
      .bias_flatten_i              (vpu_bias_flatten_i),
      .requant_multiplier_flatten_i(vpu_requant_multiplier_flatten_i),
      .requant_shift_flatten_i     (vpu_requant_shift_flatten_i),
      .output_zero_point_i         (vpu_output_zero_point_i),
      .data_flatten_o              (vpu_data_flatten_w),
      .data_valid_o                (vpu_data_valid_w),
      .done_o                      (vpu_done_w)
  );

  assign wgt_load_done_o             = wgt_load_done_w;
  assign accumulator_read_flatten_o  = accumulator_read_flatten_w;
  assign accumulator_read_valid_o    = accumulator_read_valid_w;
  assign accumulator_row_done_o      = accumulator_row_done_w;
  assign accumulator_row_done_addr_o = accumulator_row_done_addr_w;
  assign accumulator_row_ready_o     = accumulator_row_ready_w;
  assign vpu_data_flatten_o          = vpu_data_flatten_w;
  assign vpu_data_valid_o            = vpu_data_valid_w;
  assign done_o                      = vpu_done_w;

endmodule : tpu_datapath_v3

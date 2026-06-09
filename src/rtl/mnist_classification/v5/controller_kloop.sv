`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// ROM-driven controller for one output-channel tile across all K tiles.
//
// V3 keeps the V2 datapath contract but makes the K-loop scheduler generic for
// SIZE=4 experiments. The historical V2 controller was hardcoded around two
// activation lanes, two weight rows, and two output lanes.
module controller_kloop #(
    parameter int SIZE                = 2,
    parameter int DATA_WIDTH          = 8,
    parameter int ACC_WIDTH           = 32,
    parameter int OUT_WIDTH           = 8,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int UB_ADDR_WIDTH       = 13,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int MAX_NUM_TILES       = 128,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1,
    parameter int TAG_DEPTH           = ACC_DEPTH,
    parameter int TAG_COUNT_WIDTH     = (TAG_DEPTH > 1) ? $clog2(TAG_DEPTH + 1) : 1,
    parameter int TAG_PTR_WIDTH       = (TAG_DEPTH > 1) ? $clog2(TAG_DEPTH) : 1,
    parameter int BANK_DEPTH          = 8192,
    parameter int ROM_ADDR_WIDTH      = 16,
    parameter int WEIGHT_DEPTH        = 4952,
    parameter int WEIGHT_ADDR_WIDTH   = (WEIGHT_DEPTH > 1) ? $clog2(WEIGHT_DEPTH) : 1,
    parameter int PARAM_DEPTH         = 44,
    parameter int PARAM_ADDR_WIDTH    = (PARAM_DEPTH > 1) ? $clog2(PARAM_DEPTH) : 1,
    parameter int LANE_COUNT_WIDTH    = (SIZE > 1) ? $clog2(SIZE + 1) : 1,
    parameter int DBG_STATE_COUNT     = 17,
    parameter int DBG_PREFETCH_COUNT  = 33,
    parameter bit ENABLE_PACKED_ACT_READ = 1'b0
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [31:0] dbg_cycle_count_o,
    output logic [15:0] dbg_k_tile_o,
    output logic [31:0] dbg_useful_mac_count_o,
    output logic [(32*DBG_STATE_COUNT)-1:0] dbg_state_exec_counts_flat_o,
    output logic [(32*DBG_PREFETCH_COUNT)-1:0] dbg_prefetch_counts_flat_o,
    output logic [31:0] dbg_error_code_o,

    input logic [1:0] layer_idx_i,
    input logic       use_descriptor_banks_i,
    input logic       read_bank_i,
    input logic       write_bank_i,
    input logic [UB_ADDR_WIDTH-1:0] activation_base_addr_i,
    input logic [UB_ADDR_WIDTH-1:0] output_base_addr_i,
    input logic [ACC_ADDR_WIDTH:0]  block_size_i,
    input logic [15:0] spatial_idx_i,
    input logic [15:0] oc_tile_idx_i,

    output logic                         ub_rd_en_o,
    output logic                         ub_rd_bank_o,
    output logic [UB_ADDR_WIDTH-1:0]     ub_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] ub_rd_data_i,
    input  logic                         ub_rd_valid_i,
    output logic                         ub_rd_packed_en_o,
    output logic                         ub_rd_packed_bank_o,
    output logic [UB_ADDR_WIDTH-1:0]     ub_rd_packed_addr_o,
    input  logic signed [(DATA_WIDTH*SIZE)-1:0] ub_rd_packed_data_i,
    input  logic                         ub_rd_packed_valid_i,

    output logic                         ub_wr_en_o,
    output logic                         ub_wr_bank_o,
    output logic [UB_ADDR_WIDTH-1:0]     ub_wr_addr_o,
    output logic signed [DATA_WIDTH-1:0] ub_wr_data_o,
    output logic [15:0]                  ub_wr_spatial_idx_o,
    output logic [15:0]                  ub_wr_oc_idx_o,

    output logic                         work_o,
    output logic [TILE_COUNT_WIDTH-1:0]  num_tiles_o,
    output logic                         start_wgt_load_o,
    output logic [(DATA_WIDTH*SIZE)-1:0] wgt_fifo_wdata_o,
    output logic                         wgt_fifo_wr_en_o,
    input  logic                         wgt_fifo_full_i,
    input  logic                         wgt_fetcher_ready_i,
    input  logic [SIZE-1:0]              wgt_load_done_i,

    output logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_o,
    output logic [SIZE-1:0]                     act_valid_raw_o,

    output logic                      accumulator_clear_all_o,
    output logic                      accumulator_row_clear_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_o,
    output logic                      accumulator_write_en_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_o,
    output logic                      accumulator_read_en_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_o,
    input  logic [ACC_DEPTH-1:0]      accumulator_row_ready_i,

    output logic                                         vpu_input_done_o,
    output logic [1:0]                                   vpu_act_mode_o,
    output logic signed [(BIAS_WIDTH*SIZE)-1:0]          vpu_bias_flatten_o,
    output logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0]  vpu_requant_multiplier_flatten_o,
    output logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0]        vpu_requant_shift_flatten_o,
    output logic signed [ACC_WIDTH-1:0]                  vpu_output_zero_point_o,
    input  logic signed [(OUT_WIDTH*SIZE)-1:0]           vpu_data_flatten_i,
    input  logic                                         vpu_data_valid_i,

    input logic [SIZE-1:0] mxu_psum_valid_i,
    input logic            psum_packer_busy_i
);

  typedef enum logic [4:0] {
    S_IDLE,
    S_CLEAR_ACC_BLOCK,
    S_FETCH_ROM,
    S_WAIT_ROM,
    S_WRITE_WEIGHT_ROW,
    S_START_WEIGHT_LOAD,
    S_WAIT_WEIGHT_LOAD,
    S_READ_ACT_REQ,
    S_READ_ACT_WAIT,
    S_LAUNCH_ACT,
    S_DRAIN_MXU,
    S_WAIT_ACC_READY,
    S_READ_ACC_ROW,
    S_WAIT_VPU_OUTPUT,
    S_WRITE_OUTPUT_LANE,
    S_DONE,
    S_ERROR
  } state_t;

  typedef enum logic [2:0] {
    PREFETCH_IDLE,
    PREFETCH_FETCH_ROM,
    PREFETCH_WAIT_ROM,
    PREFETCH_WRITE_WEIGHT_ROW,
    PREFETCH_DONE
  } prefetch_state_t;

  typedef enum logic [1:0] {
    ACT_PREFETCH_IDLE,
    ACT_PREFETCH_REQ,
    ACT_PREFETCH_WAIT,
    ACT_PREFETCH_DONE
  } act_prefetch_state_t;

  localparam logic [31:0] ERR_SIZE            = 32'h0002_0001;
  localparam logic [31:0] ERR_DESC_INVALID    = 32'h0002_0002;
  localparam logic [31:0] ERR_BLOCK_SIZE      = 32'h0002_0003;
  localparam logic [31:0] ERR_SPATIAL         = 32'h0002_0004;
  localparam logic [31:0] ERR_K_TILE_COUNT    = 32'h0002_0005;
  localparam logic [31:0] ERR_OC_TILE         = 32'h0002_0006;
  localparam logic [31:0] ERR_ROM_VALID       = 32'h0002_0008;
  localparam logic [31:0] ERR_WGT_FIFO_FULL   = 32'h0002_0009;
  localparam logic [31:0] ERR_INPUT_ADDR      = 32'h0002_000a;
  localparam logic [31:0] ERR_OUTPUT_ADDR     = 32'h0002_000b;
  localparam logic [31:0] ERR_TAG_OVERFLOW    = 32'h0002_000c;
  localparam logic [31:0] ERR_TAG_UNDERFLOW   = 32'h0002_000d;

  localparam int ACC_COUNT_WIDTH = ACC_ADDR_WIDTH + 1;
  localparam int ADDR_CALC_WIDTH = 32;
  localparam int ACT_REUSE_DEPTH = 128;
  localparam int ACT_REUSE_PTR_WIDTH =
      (ACT_REUSE_DEPTH <= 1) ? 1 : $clog2(ACT_REUSE_DEPTH);
  localparam int ACT_PREFETCH_DEPTH = 16;
  localparam int ACT_PREFETCH_SLOT_WIDTH = (ACT_PREFETCH_DEPTH <= 1) ? 1 : $clog2(ACT_PREFETCH_DEPTH);
  localparam int ACT_PREFETCH_CHAIN_MAX_CYCLE = (SIZE * SIZE) + SIZE + 2;
  localparam bit ENABLE_EARLY_ACT_PREFETCH = 1'b0;
  localparam int PREFETCH_ATTEMPTS_IDX             = 0;
  localparam int PREFETCH_PUSHES_IDX               = 1;
  localparam int PREFETCH_HITS_IDX                 = 2;
  localparam int PREFETCH_MISSES_IDX               = 3;
  localparam int PREFETCH_DROPS_FULL_IDX           = 4;
  localparam int PREFETCH_INVALIDATED_BOUNDARY_IDX = 5;
  localparam int PREFETCH_QUEUE_FULL_CYCLES_IDX    = 6;
  localparam int PREFETCH_QUEUE_EMPTY_ON_NEED_IDX  = 7;
  localparam int PREFETCH_MAX_OCCUPANCY_IDX        = 8;
  localparam int PREFETCH_OCCUPANCY_SUM_IDX        = 9;
  localparam int PREFETCH_OCCUPANCY_SAMPLES_IDX    = 10;
  localparam int PREFETCH_CURRENT_OCCUPANCY_IDX    = 11;
  localparam int PREFETCH_EARLY_ATTEMPTS_IDX       = 12;
  localparam int PREFETCH_EARLY_PUSHES_IDX         = 13;
  localparam int PREFETCH_DRAIN_ATTEMPTS_IDX       = 14;
  localparam int PREFETCH_DRAIN_PUSHES_IDX         = 15;
  localparam int PREFETCH_STALL_QUEUE_FULL_IDX     = 16;
  localparam int PREFETCH_STALL_UB_BUSY_IDX        = 17;
  localparam int PREFETCH_STALL_NO_CANDIDATE_IDX   = 18;
  localparam int PREFETCH_MISS_NO_ENTRY_IDX        = 19;
  localparam int PREFETCH_MISS_TAG_MISMATCH_IDX    = 20;
  localparam int PREFETCH_MISS_LANE_INCOMPLETE_IDX = 21;
  localparam int PREFETCH_MISS_INVALID_BOUNDARY_IDX = 22;
  localparam int PREFETCH_MISS_WRONG_K_TILE_IDX    = 23;
  localparam int PREFETCH_MISS_WRONG_SPATIAL_IDX   = 24;
  localparam int PREFETCH_MISS_WRONG_OC_TILE_IDX   = 25;
  localparam int PREFETCH_VECTOR_START_IDX         = 26;
  localparam int PREFETCH_VECTOR_PUSH_IDX          = 27;
  localparam int PREFETCH_LANE_REQ_IDX             = 28;
  localparam int PREFETCH_LANE_CAPTURE_IDX         = 29;
  localparam int PREFETCH_ISSUE_CYCLES_IDX         = 30;
  localparam int PREFETCH_BUBBLE_CYCLES_IDX        = 31;
  localparam int PREFETCH_BUSY_CYCLES_IDX          = 32;

  state_t state_q;
  prefetch_state_t prefetch_state_q;
  act_prefetch_state_t act_prefetch_state_q;

  logic [1:0] layer_idx_q;
  logic use_descriptor_banks_q;
  logic read_bank_q;
  logic write_bank_q;
  logic [UB_ADDR_WIDTH-1:0] activation_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_q;
  logic [ACC_ADDR_WIDTH:0] block_size_q;
  logic [15:0] spatial_idx_q;
  logic [15:0] oc_tile_idx_q;
  logic [15:0] k_tile_q;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_q;
  logic [15:0] prefetch_k_tile_q;
  logic [15:0] prefetch_weight_stream_row_q;
  logic [ACC_ADDR_WIDTH:0] act_prefetch_stream_idx_q;
  logic [15:0] act_prefetch_lane_q;
  logic [1:0] act_prefetch_valid_pipe_q;
  logic [15:0] act_prefetch_lane_pipe_q[0:1];
  logic [UB_ADDR_WIDTH-1:0] act_prefetch_addr_pipe_q[0:1];
  logic [1:0] act_prefetch_packed_valid_pipe_q;
  logic [15:0] act_prefetch_packed_start_lane_pipe_q[0:1];
  logic [SIZE-1:0] act_prefetch_packed_mask_pipe_q[0:1];
  logic [UB_ADDR_WIDTH-1:0] act_prefetch_packed_base_addr_pipe_q[0:1];
  logic signed [DATA_WIDTH-1:0] act_prefetch_lane_data_q[0:SIZE-1];
  logic [SIZE-1:0] act_prefetch_lane_done_q;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_prefetch_queue_data_q[0:ACT_PREFETCH_DEPTH-1];
  logic [ACC_ADDR_WIDTH:0] act_prefetch_queue_stream_q[0:ACT_PREFETCH_DEPTH-1];
  logic [ACT_PREFETCH_DEPTH-1:0] act_prefetch_entry_valid_q;
  logic [15:0] act_prefetch_tag_k_tile_q;
  logic act_prefetch_tag_read_bank_q;
  logic [15:0] drain_prefetch_cycle_q;
  logic [ACT_REUSE_DEPTH-1:0] act_reuse_valid_q;
  logic [UB_ADDR_WIDTH-1:0] act_reuse_addr_q[0:ACT_REUSE_DEPTH-1];
  logic signed [DATA_WIDTH-1:0] act_reuse_data_q[0:ACT_REUSE_DEPTH-1];
  logic [ACT_REUSE_PTR_WIDTH-1:0] act_reuse_wr_ptr_q;

  logic desc_valid_w;
  layer_type_t desc_layer_type_w;
  logic [15:0] desc_in_h_w;
  logic [15:0] desc_in_w_w;
  logic [15:0] desc_in_ch_w;
  logic [15:0] desc_out_h_w;
  logic [15:0] desc_out_w_w;
  logic [15:0] desc_out_ch_w;
  logic [15:0] desc_kernel_h_w;
  logic [15:0] desc_kernel_w_w;
  logic [15:0] desc_k_total_w;
  logic [15:0] desc_num_k_tiles_w;
  logic [15:0] desc_num_oc_tiles_w;
  logic [15:0] desc_num_spatial_w;
  logic [15:0] desc_weight_base_w;
  logic [15:0] desc_bias_base_w;
  logic [15:0] desc_requant_base_w;
  act_mode_t desc_act_mode_w;
  logic desc_read_bank_w;
  logic desc_write_bank_w;

  logic [15:0] spatial_stream_idx_w;
  logic [ROM_ADDR_WIDTH*SIZE-1:0]      act_addr_flatten_w;
  logic [SIZE-1:0]                     act_valid_w;
  logic [SIZE-1:0]                     act_zero_w;
  logic [ROM_ADDR_WIDTH*SIZE*SIZE-1:0] weight_addr_flatten_w;
  logic [SIZE*SIZE-1:0]                weight_valid_w;
  logic [SIZE*SIZE-1:0]                weight_zero_w;
  logic [16*SIZE-1:0]                  k_index_flatten_bus_w;
  logic [16*SIZE-1:0]                  oc_index_flatten_bus_w;
  logic [15:0]                         oc_idx_w[0:SIZE-1];
  logic [SIZE-1:0]                     oc_valid_w;

  logic rom_en_w;
  logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_w[0:SIZE*SIZE-1];
  logic [PARAM_ADDR_WIDTH-1:0] bias_addr_w[0:SIZE-1];
  logic [PARAM_ADDR_WIDTH-1:0] requant_addr_w[0:SIZE-1];

  logic signed [DATA_WIDTH-1:0] weight_data_w[0:SIZE*SIZE-1];
  logic [SIZE*SIZE-1:0] weight_data_valid_w;
  logic signed [DATA_WIDTH-1:0] weight_mux_w[0:SIZE*SIZE-1];
  logic signed [BIAS_WIDTH-1:0] bias_data_w[0:SIZE-1];
  logic [SIZE-1:0] bias_data_valid_w;
  logic signed [REQUANT_MULT_WIDTH-1:0] requant_mult_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_mult_valid_w;
  logic [REQUANT_SHIFT_WIDTH-1:0] requant_shift_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_shift_valid_w;

  logic signed [DATA_WIDTH-1:0] act_lane_q[0:SIZE-1];
  logic [SIZE-1:0] wgt_load_seen_q;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_q;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_next_data_q;
  logic vpu_next_valid_q;
  logic vpu_prefetch_pending_q;
  logic vpu_prefetch_done_q;

  logic [ACC_ADDR_WIDTH:0] stream_idx_q;
  logic [ACC_ADDR_WIDTH:0] acc_read_idx_q;
  logic [ACC_ADDR_WIDTH:0] next_acc_read_idx_w;
  logic [ACC_ADDR_WIDTH:0] row_after_next_acc_idx_w;
  logic [15:0] weight_stream_row_q;
  logic [15:0] act_fetch_lane_q;
  logic [1:0] act_read_valid_pipe_q;
  logic [15:0] act_read_lane_pipe_q[0:1];
  logic [UB_ADDR_WIDTH-1:0] act_read_addr_pipe_q[0:1];
  logic [1:0] act_read_packed_valid_pipe_q;
  logic [15:0] act_read_packed_start_lane_pipe_q[0:1];
  logic [SIZE-1:0] act_read_packed_mask_pipe_q[0:1];
  logic [UB_ADDR_WIDTH-1:0] act_read_packed_base_addr_pipe_q[0:1];
  logic [15:0] output_lane_q;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_q;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_q;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_q;
  logic [1:0] act_mode_q;

  logic [ACC_ADDR_WIDTH-1:0] tag_mem_q[0:TAG_DEPTH-1];
  logic [TAG_PTR_WIDTH-1:0] tag_wr_ptr_q;
  logic [TAG_PTR_WIDTH-1:0] tag_rd_ptr_q;
  logic [TAG_COUNT_WIDTH-1:0] tag_count_q;
  logic [31:0] state_exec_counts_q[0:DBG_STATE_COUNT-1];
  logic [31:0] prefetch_counts_q[0:DBG_PREFETCH_COUNT-1];

  logic first_psum_valid_w;
  logic tag_stream_active_w;
  logic tag_push_w;
  logic tag_pop_w;
  logic tag_overflow_w;
  logic tag_underflow_w;
  logic all_rows_ready_w;
  logic [ACC_ADDR_WIDTH-1:0] tag_front_w;

  logic last_k_tile_w;
  logic [ADDR_CALC_WIDTH-1:0] act_addr_w[0:SIZE-1];
  logic [ADDR_CALC_WIDTH-1:0] output_addr_w[0:SIZE-1];
  logic [ADDR_CALC_WIDTH-1:0] output_spatial_w;
  logic [ADDR_CALC_WIDTH-1:0] act_lane_addr_w;
  logic [ADDR_CALC_WIDTH-1:0] output_lane_addr_w;
  logic act_read_capture_w;
  logic act_read_packed_capture_w;
  logic act_read_pipeline_empty_w;
  logic inner_read_bank_w;
  logic inner_write_bank_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_stream_row_data_w;
  logic [15:0] address_k_tile_w;
  logic [ACC_ADDR_WIDTH:0] address_stream_idx_w;
  logic [15:0] weight_stream_row_sel_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_launch_w;
  logic [SIZE-1:0] param_valid_required_w;
  logic launch_act_from_wait_w;
  logic act_prefetch_capture_w;
  logic act_prefetch_packed_capture_w;
  logic act_prefetch_pipe_empty_w;
  logic [SIZE-1:0] act_prefetch_lane_done_next_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_prefetch_vector_next_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_prefetch_match_data_w;
  logic act_prefetch_match_w;
  logic [ACT_PREFETCH_SLOT_WIDTH-1:0] act_prefetch_match_slot_w;
  logic [ACT_PREFETCH_SLOT_WIDTH-1:0] act_prefetch_push_slot_w;
  logic act_prefetch_push_slot_valid_w;
  logic act_prefetch_same_tag_entry_w;
  logic act_prefetch_wrong_spatial_entry_w;
  logic act_prefetch_addr_error_w;
  logic act_prefetch_can_continue_w;
  logic act_prefetch_queue_empty_on_need_w;
  logic [31:0] act_prefetch_occupancy_w;
  logic [ACC_ADDR_WIDTH:0] act_prefetch_next_stream_idx_w;
  logic [ADDR_CALC_WIDTH-1:0] act_prefetch_lane_addr_w;
  logic act_prefetch_active_w;
  logic act_prefetch_address_select_w;
  logic act_prefetch_next_tag_match_w;
  logic act_prefetch_queue_full_w;
  logic act_prefetch_can_start_next_w;
  logic act_prefetch_has_candidate_w;
  logic act_prefetch_early_service_w;
  logic act_prefetch_service_window_w;
  logic act_prefetch_service_ready_w;
  logic act_prefetch_lane_in_range_w;
  logic act_prefetch_req_active_w;
  logic act_prefetch_start_req_w;
  logic [SIZE-1:0] act_prefetch_zero_lane_mask_w;
  logic act_prefetch_issue_lane_found_w;
  logic [15:0] act_prefetch_issue_lane_w;
  logic [15:0] act_prefetch_next_lane_w;
  logic [31:0] act_prefetch_lane_req_count_w;
  logic [SIZE-1:0] act_prefetch_packed_mask_w;
  logic act_prefetch_packed_issue_w;
  logic [15:0] act_prefetch_packed_start_lane_w;
  logic [ADDR_CALC_WIDTH-1:0] act_prefetch_packed_base_addr_w;
  logic [31:0] act_prefetch_packed_lane_count_w;
  logic act_prefetch_lane_req_w;
  logic act_prefetch_chain_lane_req_w;
  logic act_prefetch_ub_issue_w;
  logic act_prefetch_vector_done_w;
  logic act_prefetch_vector_push_w;
  logic act_prefetch_chain_issue_w;
  logic act_prefetch_chain_has_runway_w;
  logic [15:0] act_prefetch_addr_lane_sel_w;
  logic act_prefetch_k_tag_match_w;
  logic act_prefetch_read_bank_tag_match_w;
  logic act_prefetch_lane_incomplete_on_need_w;
  logic act_packed_prefix_valid_w;
  logic [SIZE-1:0] act_packed_prefix_mask_w;
  logic [15:0] act_packed_next_lane_w;
  logic [31:0] act_packed_lane_count_w;
  logic [ADDR_CALC_WIDTH-1:0] act_packed_base_addr_w;
  logic drain_payload_active_w;
  logic act_reuse_lane_hit_w[0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] act_reuse_lane_data_w[0:SIZE-1];
  logic act_reuse_prefix_valid_w;
  logic [SIZE-1:0] act_reuse_prefix_mask_w;
  logic [15:0] act_reuse_next_lane_w;
  logic has_next_acc_row_w;
  logic has_row_after_next_w;
  logic row_after_next_is_last_w;
  logic output_lane_last_w;
  logic prefetched_vpu_available_w;
  logic signed [(OUT_WIDTH*SIZE)-1:0] prefetched_vpu_data_w;

  function automatic logic [TAG_PTR_WIDTH-1:0] next_tag_ptr(
      input logic [TAG_PTR_WIDTH-1:0] ptr_i);
    if (TAG_DEPTH == 1) begin
      next_tag_ptr = '0;
    end else if (ptr_i == TAG_PTR_WIDTH'(TAG_DEPTH - 1)) begin
      next_tag_ptr = '0;
    end else begin
      next_tag_ptr = ptr_i + TAG_PTR_WIDTH'(1);
    end
  endfunction

  function automatic logic [31:0] count_valid_weights(
      input logic [SIZE*SIZE-1:0] valid_i);
    logic [31:0] count;
    begin
      count = '0;
      for (int idx = 0; idx < SIZE * SIZE; idx++) begin
        count = count + 32'(valid_i[idx]);
      end
      count_valid_weights = count;
    end
  endfunction

  function automatic logic [31:0] count_prefetch_occupancy(
      input logic [ACT_PREFETCH_DEPTH-1:0] valid_i);
    logic [31:0] count;
    begin
      count = '0;
      for (int idx = 0; idx < ACT_PREFETCH_DEPTH; idx++) begin
        count = count + 32'(valid_i[idx]);
      end
      count_prefetch_occupancy = count;
    end
  endfunction

  function automatic logic [31:0] count_lane_mask(
      input logic [SIZE-1:0] mask_i);
    logic [31:0] count;
    begin
      count = '0;
      for (int idx = 0; idx < SIZE; idx++) begin
        count = count + 32'(mask_i[idx]);
      end
      count_lane_mask = count;
    end
  endfunction

  function automatic logic [ACT_REUSE_PTR_WIDTH-1:0] next_act_reuse_ptr(
      input logic [ACT_REUSE_PTR_WIDTH-1:0] ptr_i);
    if (ACT_REUSE_DEPTH == 1) begin
      next_act_reuse_ptr = '0;
    end else if (ptr_i == ACT_REUSE_PTR_WIDTH'(ACT_REUSE_DEPTH - 1)) begin
      next_act_reuse_ptr = '0;
    end else begin
      next_act_reuse_ptr = ptr_i + ACT_REUSE_PTR_WIDTH'(1);
    end
  endfunction

  layer_descriptor_rom u_layer_descriptor_rom (
      .layer_idx_i    (layer_idx_q),
      .valid_o        (desc_valid_w),
      .layer_type_o   (desc_layer_type_w),
      .in_h_o         (desc_in_h_w),
      .in_w_o         (desc_in_w_w),
      .in_ch_o        (desc_in_ch_w),
      .out_h_o        (desc_out_h_w),
      .out_w_o        (desc_out_w_w),
      .out_ch_o       (desc_out_ch_w),
      .kernel_h_o     (desc_kernel_h_w),
      .kernel_w_o     (desc_kernel_w_w),
      .k_total_o      (desc_k_total_w),
      .num_k_tiles_o  (desc_num_k_tiles_w),
      .num_oc_tiles_o (desc_num_oc_tiles_w),
      .num_spatial_o  (desc_num_spatial_w),
      .weight_base_o  (desc_weight_base_w),
      .bias_base_o    (desc_bias_base_w),
      .requant_base_o (desc_requant_base_w),
      .act_mode_o     (desc_act_mode_w),
      .read_bank_o    (desc_read_bank_w),
      .write_bank_o   (desc_write_bank_w)
  );

  assign spatial_stream_idx_w = spatial_idx_q + 16'(address_stream_idx_w);

  address_generator #(
      .SIZE      (SIZE),
      .ADDR_WIDTH(ROM_ADDR_WIDTH),
      .DIM_WIDTH (16)
  ) u_address_generator (
      .layer_type_i          (desc_layer_type_w),
      .activation_base_addr_i(ROM_ADDR_WIDTH'(activation_base_addr_q)),
      .weight_base_addr_i    (ROM_ADDR_WIDTH'(desc_weight_base_w)),
      .in_h_i                (desc_in_h_w),
      .in_w_i                (desc_in_w_w),
      .out_w_i               (desc_out_w_w),
      .out_ch_i              (desc_out_ch_w),
      .kernel_h_i            (desc_kernel_h_w),
      .kernel_w_i            (desc_kernel_w_w),
      .k_total_i             (desc_k_total_w),
      .spatial_idx_i         (spatial_stream_idx_w),
      .k_tile_idx_i          (address_k_tile_w),
      .oc_tile_idx_i         (oc_tile_idx_q),
      .act_addr_flatten_o    (act_addr_flatten_w),
      .act_valid_o           (act_valid_w),
      .act_zero_o            (act_zero_w),
      .weight_addr_flatten_o (weight_addr_flatten_w),
      .weight_valid_o        (weight_valid_w),
      .weight_zero_o         (weight_zero_w),
      .k_index_flatten_o     (k_index_flatten_bus_w),
      .oc_index_flatten_o    (oc_index_flatten_bus_w)
  );

  generate
    for (genvar idx = 0; idx < SIZE * SIZE; idx++) begin : GEN_WEIGHT_ROMS
      assign weight_addr_w[idx] =
          WEIGHT_ADDR_WIDTH'(weight_addr_flatten_w[(idx*ROM_ADDR_WIDTH)+:ROM_ADDR_WIDTH]);
      assign weight_mux_w[idx] = weight_valid_w[idx] ? weight_data_w[idx] : '0;

      weight_rom #(
          .DATA_WIDTH(DATA_WIDTH),
          .DEPTH     (WEIGHT_DEPTH),
          .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
      ) u_weight_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (rom_en_w),
          .addr_i (weight_addr_w[idx]),
          .data_o (weight_data_w[idx]),
          .valid_o(weight_data_valid_w[idx])
      );
    end

    for (genvar lane = 0; lane < SIZE; lane++) begin : GEN_PARAM_ROMS
      assign oc_idx_w[lane] = oc_index_flatten_bus_w[(lane*16)+:16];
      assign oc_valid_w[lane] = (oc_idx_w[lane] < desc_out_ch_w);
      assign bias_addr_w[lane] =
          oc_valid_w[lane] ? PARAM_ADDR_WIDTH'(desc_bias_base_w + oc_idx_w[lane]) : '0;
      assign requant_addr_w[lane] =
          oc_valid_w[lane] ? PARAM_ADDR_WIDTH'(desc_requant_base_w + oc_idx_w[lane]) : '0;
      assign param_valid_required_w[lane] = 1'b1;

      bias_rom #(
          .DATA_WIDTH(BIAS_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH)
      ) u_bias_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (rom_en_w),
          .addr_i (bias_addr_w[lane]),
          .data_o (bias_data_w[lane]),
          .valid_o(bias_data_valid_w[lane])
      );

      requant_mult_rom #(
          .DATA_WIDTH(REQUANT_MULT_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH)
      ) u_requant_mult_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (rom_en_w),
          .addr_i (requant_addr_w[lane]),
          .data_o (requant_mult_data_w[lane]),
          .valid_o(requant_mult_valid_w[lane])
      );

      requant_shift_rom #(
          .DATA_WIDTH(REQUANT_SHIFT_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH)
      ) u_requant_shift_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (rom_en_w),
          .addr_i (requant_addr_w[lane]),
          .data_o (requant_shift_data_w[lane]),
          .valid_o(requant_shift_valid_w[lane])
      );
    end
  endgenerate

  generate
    for (genvar state_idx = 0; state_idx < DBG_STATE_COUNT; state_idx++) begin : GEN_STATE_EXEC_COUNTS
      assign dbg_state_exec_counts_flat_o[(state_idx*32)+:32] = state_exec_counts_q[state_idx];
    end
  endgenerate

  generate
    for (genvar prefetch_idx = 0; prefetch_idx < DBG_PREFETCH_COUNT; prefetch_idx++) begin : GEN_PREFETCH_COUNTS
      assign dbg_prefetch_counts_flat_o[(prefetch_idx*32)+:32] =
          prefetch_counts_q[prefetch_idx];
    end
  endgenerate

  assign act_prefetch_active_w = (act_prefetch_state_q != ACT_PREFETCH_IDLE)
                              && (act_prefetch_state_q != ACT_PREFETCH_DONE);
  assign act_prefetch_early_service_w =
      ENABLE_EARLY_ACT_PREFETCH
      && (state_q == S_READ_ACT_WAIT)
      && act_read_pipeline_empty_w
      && (act_prefetch_can_start_next_w
          || (act_prefetch_active_w && (act_prefetch_stream_idx_q == '0)));
  assign act_prefetch_start_req_w =
      act_prefetch_early_service_w
      && act_prefetch_can_start_next_w;
  assign act_prefetch_address_select_w =
      ((state_q == S_DRAIN_MXU) || act_prefetch_early_service_w)
      && (act_prefetch_active_w || act_prefetch_can_start_next_w);
  assign act_prefetch_next_tag_match_w =
      (act_prefetch_tag_k_tile_q == (k_tile_q + 16'd1))
      && (act_prefetch_tag_read_bank_q == inner_read_bank_w);
  assign act_prefetch_queue_full_w =
      (act_prefetch_occupancy_w == 32'(ACT_PREFETCH_DEPTH));
  assign act_prefetch_can_start_next_w =
      !last_k_tile_w
      && !act_prefetch_next_tag_match_w
      && ((act_prefetch_state_q == ACT_PREFETCH_IDLE)
          || (act_prefetch_state_q == ACT_PREFETCH_DONE));
  assign act_prefetch_has_candidate_w =
      !last_k_tile_w
      && (act_prefetch_active_w || act_prefetch_can_start_next_w);
  assign act_prefetch_service_window_w =
      ((state_q == S_DRAIN_MXU) && drain_payload_active_w)
      || act_prefetch_early_service_w;
  assign act_prefetch_service_ready_w =
      act_prefetch_service_window_w
      && act_prefetch_has_candidate_w
      && !act_prefetch_queue_full_w;
  assign act_prefetch_lane_in_range_w = (act_prefetch_lane_q < 16'(SIZE));
  assign act_prefetch_req_active_w =
      act_prefetch_service_ready_w
      && (act_prefetch_state_q == ACT_PREFETCH_REQ)
      && act_prefetch_lane_in_range_w;
  always_comb begin
    act_prefetch_zero_lane_mask_w = '0;
    act_prefetch_issue_lane_found_w = 1'b0;
    act_prefetch_issue_lane_w = act_prefetch_lane_q;
    act_prefetch_next_lane_w = act_prefetch_lane_q;
    act_prefetch_lane_req_count_w = '0;
    act_prefetch_packed_mask_w = '0;
    act_prefetch_packed_issue_w = 1'b0;
    act_prefetch_packed_start_lane_w = act_prefetch_lane_q;
    act_prefetch_packed_base_addr_w = '0;
    act_prefetch_packed_lane_count_w = '0;

    if (act_prefetch_lane_req_w) begin
      logic [15:0] req_start_lane_w;
      logic [31:0] packed_lane_count_w;
      logic packed_continue_w;

      req_start_lane_w = act_prefetch_chain_lane_req_w ? 16'd0 : act_prefetch_lane_q;
      act_prefetch_issue_lane_w = req_start_lane_w;
      act_prefetch_packed_start_lane_w = req_start_lane_w;
      act_prefetch_next_lane_w = 16'(SIZE);
      packed_lane_count_w = '0;
      packed_continue_w = 1'b0;

      for (int lane = 0; lane < SIZE; lane++) begin
        if ((16'(lane) >= req_start_lane_w) && !act_prefetch_issue_lane_found_w) begin
          act_prefetch_lane_req_count_w = act_prefetch_lane_req_count_w + 32'd1;
          if (act_zero_w[lane]) begin
            act_prefetch_zero_lane_mask_w[lane] = 1'b1;
          end else begin
            act_prefetch_issue_lane_found_w = 1'b1;
            act_prefetch_issue_lane_w = 16'(lane);
            act_prefetch_packed_start_lane_w = 16'(lane);
            act_prefetch_packed_base_addr_w = act_addr_w[lane];
            act_prefetch_packed_mask_w[lane] = 1'b1;
            packed_lane_count_w = 32'd1;
            packed_continue_w = 1'b1;
          end
        end else if (act_prefetch_issue_lane_found_w
                     && packed_continue_w
                     && (16'(lane) > act_prefetch_issue_lane_w)) begin
          if (!act_zero_w[lane]
              && (act_addr_w[lane]
                  == (act_prefetch_packed_base_addr_w
                      + ADDR_CALC_WIDTH'(lane - int'(act_prefetch_issue_lane_w))))) begin
            act_prefetch_packed_mask_w[lane] = 1'b1;
            packed_lane_count_w = packed_lane_count_w + 32'd1;
            act_prefetch_lane_req_count_w = act_prefetch_lane_req_count_w + 32'd1;
          end else begin
            packed_continue_w = 1'b0;
          end
        end
      end

      if (act_prefetch_issue_lane_found_w) begin
        act_prefetch_packed_lane_count_w = packed_lane_count_w;
        act_prefetch_next_lane_w = act_prefetch_issue_lane_w + 16'(packed_lane_count_w);
        act_prefetch_packed_issue_w =
            ENABLE_PACKED_ACT_READ
            && (packed_lane_count_w >= 32'd2)
            && ((act_prefetch_packed_base_addr_w + ADDR_CALC_WIDTH'(packed_lane_count_w - 32'd1))
                < ADDR_CALC_WIDTH'(BANK_DEPTH));
      end
    end
  end
  assign act_prefetch_lane_req_w =
      act_prefetch_req_active_w
      || act_prefetch_chain_lane_req_w
      || act_prefetch_start_req_w;
  always_comb begin
    act_prefetch_ub_issue_w = 1'b0;
    if (act_prefetch_packed_issue_w) begin
      act_prefetch_ub_issue_w = 1'b1;
    end else if (act_prefetch_lane_req_w) begin
      act_prefetch_ub_issue_w =
          act_prefetch_issue_lane_found_w
          && (act_prefetch_lane_addr_w < ADDR_CALC_WIDTH'(BANK_DEPTH));
    end
  end
  assign act_prefetch_vector_done_w =
      act_prefetch_service_ready_w
      && (act_prefetch_state_q == ACT_PREFETCH_WAIT)
      && act_prefetch_pipe_empty_w
      && (act_prefetch_lane_done_next_w == {SIZE{1'b1}});
  assign act_prefetch_vector_push_w =
      act_prefetch_vector_done_w && act_prefetch_push_slot_valid_w;
  assign act_prefetch_chain_issue_w =
      (state_q == S_DRAIN_MXU)
      && act_prefetch_vector_push_w
      && act_prefetch_can_continue_w
      && act_prefetch_chain_has_runway_w;
  assign act_prefetch_chain_lane_req_w = act_prefetch_chain_issue_w;
  assign act_prefetch_k_tag_match_w = (act_prefetch_tag_k_tile_q == k_tile_q);
  assign act_prefetch_read_bank_tag_match_w =
      (act_prefetch_tag_read_bank_q == inner_read_bank_w);
  assign act_prefetch_lane_incomplete_on_need_w =
      act_prefetch_k_tag_match_w
      && act_prefetch_read_bank_tag_match_w
      && act_prefetch_active_w
      && (act_prefetch_stream_idx_q == stream_idx_q)
      && !act_prefetch_match_w;

  assign address_k_tile_w =
      (((state_q == S_DRAIN_MXU) && (prefetch_state_q != PREFETCH_IDLE))
       || act_prefetch_address_select_w)
      ? ((act_prefetch_can_start_next_w && (state_q == S_READ_ACT_WAIT))
          ? (k_tile_q + 16'd1)
          : prefetch_k_tile_q)
      : k_tile_q;
  assign address_stream_idx_w =
      act_prefetch_chain_issue_w
      ? act_prefetch_next_stream_idx_w
      : (((act_prefetch_can_start_next_w && (state_q == S_READ_ACT_WAIT)))
          ? '0
          : (act_prefetch_address_select_w ? act_prefetch_stream_idx_q : stream_idx_q));
  assign weight_stream_row_sel_w =
      ((state_q == S_DRAIN_MXU) && (prefetch_state_q == PREFETCH_WRITE_WEIGHT_ROW))
      ? prefetch_weight_stream_row_q
      : weight_stream_row_q;
  assign rom_en_w = (state_q == S_FETCH_ROM)
                 || ((state_q == S_DRAIN_MXU) && (prefetch_state_q == PREFETCH_FETCH_ROM));
  assign num_tiles_o = num_tiles_q;
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_k_tile_o = k_tile_q;
  assign inner_read_bank_w = use_descriptor_banks_q ? desc_read_bank_w : read_bank_q;
  assign inner_write_bank_w = use_descriptor_banks_q ? desc_write_bank_w : write_bank_q;
  assign last_k_tile_w = ((TILE_COUNT_WIDTH'(k_tile_q) + TILE_COUNT_WIDTH'(1)) >= num_tiles_q);
  assign act_read_capture_w = ub_rd_valid_i && act_read_valid_pipe_q[1];
  assign act_read_packed_capture_w = ub_rd_packed_valid_i && act_read_packed_valid_pipe_q[1];
  assign act_prefetch_capture_w = ub_rd_valid_i && act_prefetch_valid_pipe_q[1];
  assign act_prefetch_packed_capture_w =
      ub_rd_packed_valid_i && act_prefetch_packed_valid_pipe_q[1];
  assign act_read_pipeline_empty_w = !act_read_valid_pipe_q[0]
                                  && !act_read_packed_valid_pipe_q[0]
                                  && (!act_read_valid_pipe_q[1] || act_read_capture_w)
                                  && (!act_read_packed_valid_pipe_q[1]
                                      || act_read_packed_capture_w);
  assign act_prefetch_pipe_empty_w = !act_prefetch_valid_pipe_q[0]
                                  && !act_prefetch_packed_valid_pipe_q[0]
                                  && (!act_prefetch_valid_pipe_q[1]
                                      || act_prefetch_capture_w)
                                  && (!act_prefetch_packed_valid_pipe_q[1]
                                      || act_prefetch_packed_capture_w);
  assign launch_act_from_wait_w = (state_q == S_READ_ACT_WAIT)
                               && act_read_pipeline_empty_w;

  assign output_spatial_w = ADDR_CALC_WIDTH'(spatial_idx_q) + ADDR_CALC_WIDTH'(acc_read_idx_q);
  assign act_lane_addr_w = (act_fetch_lane_q < 16'(SIZE)) ? act_addr_w[act_fetch_lane_q] : '0;
  assign act_prefetch_addr_lane_sel_w = act_prefetch_chain_issue_w ? '0 : act_prefetch_issue_lane_w;
  assign act_prefetch_lane_addr_w =
      (act_prefetch_addr_lane_sel_w < 16'(SIZE)) ? act_addr_w[act_prefetch_addr_lane_sel_w] : '0;
  assign output_lane_addr_w = output_addr_w[output_lane_q];
  assign next_acc_read_idx_w = acc_read_idx_q + ACC_COUNT_WIDTH'(1);
  assign row_after_next_acc_idx_w = acc_read_idx_q + ACC_COUNT_WIDTH'(2);
  assign has_next_acc_row_w = (next_acc_read_idx_w < block_size_q);
  assign has_row_after_next_w = (row_after_next_acc_idx_w < block_size_q);
  assign row_after_next_is_last_w =
      ((acc_read_idx_q + ACC_COUNT_WIDTH'(3)) >= block_size_q);
  assign output_lane_last_w = ((output_lane_q + 16'd1) >= 16'(SIZE));
  assign prefetched_vpu_available_w = vpu_next_valid_q
                                   || (vpu_prefetch_pending_q && vpu_data_valid_i);
  assign prefetched_vpu_data_w =
      (vpu_prefetch_pending_q && vpu_data_valid_i) ? vpu_data_flatten_i : vpu_next_data_q;
  assign act_prefetch_next_stream_idx_w =
      act_prefetch_stream_idx_q + ACC_COUNT_WIDTH'(1);
  assign act_prefetch_can_continue_w =
      (act_prefetch_next_stream_idx_w < block_size_q);
  assign act_prefetch_chain_has_runway_w =
      (drain_prefetch_cycle_q <= 16'(ACT_PREFETCH_CHAIN_MAX_CYCLE));
  assign act_prefetch_occupancy_w = count_prefetch_occupancy(act_prefetch_entry_valid_q);
  assign drain_payload_active_w = psum_packer_busy_i || (|mxu_psum_valid_i);
  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      act_reuse_lane_hit_w[lane] = 1'b0;
      act_reuse_lane_data_w[lane] = '0;

      if ((desc_layer_type_w == LAYER_CONV)
          && !act_zero_w[lane]
          && (act_addr_w[lane] < ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
        for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
          if (act_reuse_valid_q[idx]
              && (act_reuse_addr_q[idx] == UB_ADDR_WIDTH'(act_addr_w[lane]))) begin
            act_reuse_lane_hit_w[lane] = 1'b1;
            act_reuse_lane_data_w[lane] = act_reuse_data_q[idx];
          end
        end
      end
    end
  end

  always_comb begin
    act_reuse_prefix_valid_w = 1'b0;
    act_reuse_prefix_mask_w = '0;
    act_reuse_next_lane_w = act_fetch_lane_q;

    if ((desc_layer_type_w == LAYER_CONV) && (act_fetch_lane_q < 16'(SIZE))) begin
      logic prefix_active_w;

      prefix_active_w = 1'b1;
      for (int lane = 0; lane < SIZE; lane++) begin
        if ((16'(lane) >= act_fetch_lane_q) && prefix_active_w) begin
          if (act_zero_w[lane] || act_reuse_lane_hit_w[lane]) begin
            act_reuse_prefix_valid_w = 1'b1;
            act_reuse_prefix_mask_w[lane] = 1'b1;
            act_reuse_next_lane_w = 16'(lane + 1);
          end else begin
            prefix_active_w = 1'b0;
          end
        end
      end
    end
  end
  always_comb begin
    act_packed_prefix_valid_w = 1'b0;
    act_packed_prefix_mask_w = '0;
    act_packed_next_lane_w = act_fetch_lane_q;
    act_packed_lane_count_w = '0;
    act_packed_base_addr_w = act_lane_addr_w;

    if (act_fetch_lane_q < 16'(SIZE)) begin
      logic prefix_valid;
      logic [31:0] lane_count;
      logic [ADDR_CALC_WIDTH-1:0] base_addr;

      prefix_valid = !act_zero_w[int'(act_fetch_lane_q)];
      lane_count = '0;
      base_addr = act_addr_w[int'(act_fetch_lane_q)];

      if (prefix_valid) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          if ((16'(lane) >= act_fetch_lane_q) && prefix_valid) begin
            if (!act_zero_w[lane]
                && (act_addr_w[lane]
                    == (base_addr + ADDR_CALC_WIDTH'(lane - int'(act_fetch_lane_q))))) begin
              act_packed_prefix_mask_w[lane] = 1'b1;
              lane_count = lane_count + 32'd1;
            end else begin
              prefix_valid = 1'b0;
            end
          end
        end
      end

      act_packed_lane_count_w = lane_count;
      act_packed_next_lane_w = act_fetch_lane_q + 16'(lane_count);
      act_packed_base_addr_w = base_addr;
      act_packed_prefix_valid_w =
          ENABLE_PACKED_ACT_READ
          && (lane_count >= 32'd2)
          && (base_addr < ADDR_CALC_WIDTH'(BANK_DEPTH));
    end
  end
  always_comb begin
    act_prefetch_match_w = 1'b0;
    act_prefetch_match_data_w = '0;
    act_prefetch_match_slot_w = '0;
    act_prefetch_same_tag_entry_w = 1'b0;
    act_prefetch_wrong_spatial_entry_w = 1'b0;

    for (int idx = 0; idx < ACT_PREFETCH_DEPTH; idx++) begin
      if (act_prefetch_entry_valid_q[idx]
          && act_prefetch_k_tag_match_w
          && act_prefetch_read_bank_tag_match_w) begin
        act_prefetch_same_tag_entry_w = 1'b1;
        if (act_prefetch_queue_stream_q[idx] == stream_idx_q) begin
          act_prefetch_match_w = 1'b1;
          act_prefetch_match_slot_w = ACT_PREFETCH_SLOT_WIDTH'(idx);
          act_prefetch_match_data_w = act_prefetch_queue_data_q[idx];
        end else begin
          act_prefetch_wrong_spatial_entry_w = 1'b1;
        end
      end
    end
  end

  always_comb begin
    act_prefetch_push_slot_valid_w = 1'b0;
    act_prefetch_push_slot_w = '0;
    for (int idx = 0; idx < ACT_PREFETCH_DEPTH; idx++) begin
      if (!act_prefetch_entry_valid_q[idx] && !act_prefetch_push_slot_valid_w) begin
        act_prefetch_push_slot_valid_w = 1'b1;
        act_prefetch_push_slot_w = ACT_PREFETCH_SLOT_WIDTH'(idx);
      end
    end
  end

  assign act_prefetch_queue_empty_on_need_w =
      act_prefetch_k_tag_match_w
      && act_prefetch_read_bank_tag_match_w
      && !act_prefetch_match_w;
  always_comb begin
    act_prefetch_addr_error_w = 1'b0;
    if (((state_q == S_DRAIN_MXU) || (state_q == S_READ_ACT_WAIT))
        && (act_prefetch_state_q == ACT_PREFETCH_REQ)
        && (act_prefetch_lane_req_w || act_prefetch_lane_q < 16'(SIZE))) begin
      if (act_prefetch_packed_issue_w) begin
        act_prefetch_addr_error_w =
            ((act_prefetch_packed_base_addr_w
              + ADDR_CALC_WIDTH'(act_prefetch_packed_lane_count_w - 32'd1))
             >= ADDR_CALC_WIDTH'(BANK_DEPTH));
      end else begin
        act_prefetch_addr_error_w =
            act_prefetch_issue_lane_found_w
            && (act_prefetch_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH));
      end
    end
  end

  always_comb begin
    act_prefetch_lane_done_next_w = act_prefetch_lane_done_q;
    if (act_prefetch_capture_w
        && (act_prefetch_lane_pipe_q[1] < 16'(SIZE))) begin
      act_prefetch_lane_done_next_w[int'(act_prefetch_lane_pipe_q[1])] = 1'b1;
    end
    if (act_prefetch_packed_capture_w) begin
      for (int lane = 0; lane < SIZE; lane++) begin
        if (act_prefetch_packed_mask_pipe_q[1][lane]) begin
          act_prefetch_lane_done_next_w[lane] = 1'b1;
        end
      end
    end
  end

  always_comb begin
    act_prefetch_vector_next_w = '0;
    for (int lane = 0; lane < SIZE; lane++) begin
      if (act_prefetch_packed_capture_w
          && act_prefetch_packed_mask_pipe_q[1][lane]
          && (16'(lane) >= act_prefetch_packed_start_lane_pipe_q[1])) begin
        act_prefetch_vector_next_w[(lane*DATA_WIDTH)+:DATA_WIDTH] =
            ub_rd_packed_data_i[((lane - int'(act_prefetch_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];
      end else if (act_prefetch_capture_w && (act_prefetch_lane_pipe_q[1] == 16'(lane))) begin
        act_prefetch_vector_next_w[(lane*DATA_WIDTH)+:DATA_WIDTH] = ub_rd_data_i;
      end else begin
        act_prefetch_vector_next_w[(lane*DATA_WIDTH)+:DATA_WIDTH] =
            act_prefetch_lane_data_q[lane];
      end
    end
  end

  always_comb begin
    for (int lane = 0; lane < SIZE; lane++) begin
      act_addr_w[lane] = ADDR_CALC_WIDTH'(act_addr_flatten_w[(lane*ROM_ADDR_WIDTH)+:ROM_ADDR_WIDTH]);
      output_addr_w[lane] = ADDR_CALC_WIDTH'(output_base_addr_q)
                          + (ADDR_CALC_WIDTH'(oc_idx_w[lane]) *
                             ADDR_CALC_WIDTH'(desc_num_spatial_w))
                          + output_spatial_w;
    end
  end

  always_comb begin
    all_rows_ready_w = (block_size_q != '0);
    for (int row = 0; row < ACC_DEPTH; row++) begin
      if (row < block_size_q) begin
        all_rows_ready_w &= accumulator_row_ready_i[row];
      end
    end
  end

  always_comb begin
    weight_stream_row_data_w = '0;
    for (int col = 0; col < SIZE; col++) begin
      weight_stream_row_data_w[(col*DATA_WIDTH)+:DATA_WIDTH] =
          weight_mux_w[(weight_stream_row_sel_w * 16'(SIZE)) + 16'(col)];
    end
  end

  always_comb begin
    act_flatten_launch_w = '0;
    for (int lane = 0; lane < SIZE; lane++) begin
      if (act_read_packed_capture_w
          && act_read_packed_mask_pipe_q[1][lane]
          && (16'(lane) >= act_read_packed_start_lane_pipe_q[1])) begin
        act_flatten_launch_w[(lane*DATA_WIDTH)+:DATA_WIDTH] =
            ub_rd_packed_data_i[((lane - int'(act_read_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];
      end else if (act_read_capture_w && (act_read_lane_pipe_q[1] == 16'(lane))) begin
        act_flatten_launch_w[(lane*DATA_WIDTH)+:DATA_WIDTH] = ub_rd_data_i;
      end else begin
        act_flatten_launch_w[(lane*DATA_WIDTH)+:DATA_WIDTH] = act_lane_q[lane];
      end
    end
  end

  assign first_psum_valid_w = 1'b0;
  assign tag_stream_active_w = 1'b0;
  assign tag_push_w      = 1'b0;
  assign tag_pop_w       = 1'b0;
  assign tag_overflow_w  = 1'b0;
  assign tag_underflow_w = 1'b0;
  assign tag_front_w     = (tag_count_q != '0) ? tag_mem_q[tag_rd_ptr_q] : '0;

  assign accumulator_write_en_o   = (state_q == S_LAUNCH_ACT) || launch_act_from_wait_w;
  assign accumulator_write_addr_o = stream_idx_q[ACC_ADDR_WIDTH-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      prefetch_state_q <= PREFETCH_IDLE;
      act_prefetch_state_q <= ACT_PREFETCH_IDLE;
      done_o <= 1'b0;
      error_o <= 1'b0;
      dbg_cycle_count_o <= '0;
      dbg_error_code_o <= '0;
      dbg_useful_mac_count_o <= '0;
      layer_idx_q <= '0;
      use_descriptor_banks_q <= 1'b0;
      read_bank_q <= 1'b0;
      write_bank_q <= 1'b1;
      activation_base_addr_q <= '0;
      output_base_addr_q <= '0;
      block_size_q <= '0;
      spatial_idx_q <= '0;
      oc_tile_idx_q <= '0;
      k_tile_q <= '0;
      num_tiles_q <= TILE_COUNT_WIDTH'(1);
      prefetch_k_tile_q <= '0;
      prefetch_weight_stream_row_q <= '0;
      act_prefetch_stream_idx_q <= '0;
      act_prefetch_lane_q <= '0;
      act_prefetch_valid_pipe_q <= '0;
      act_prefetch_packed_valid_pipe_q <= '0;
      act_prefetch_lane_done_q <= '0;
      act_prefetch_entry_valid_q <= '0;
      act_prefetch_tag_k_tile_q <= '0;
      act_prefetch_tag_read_bank_q <= 1'b0;
      drain_prefetch_cycle_q <= '0;
      act_reuse_wr_ptr_q <= '0;
      stream_idx_q <= '0;
      acc_read_idx_q <= '0;
      weight_stream_row_q <= '0;
      act_fetch_lane_q <= '0;
      act_read_valid_pipe_q <= '0;
      act_read_packed_valid_pipe_q <= '0;
      output_lane_q <= '0;
      wgt_load_seen_q <= '0;
      vpu_data_q <= '0;
      vpu_next_data_q <= '0;
      vpu_next_valid_q <= 1'b0;
      vpu_prefetch_pending_q <= 1'b0;
      vpu_prefetch_done_q <= 1'b0;
      bias_flatten_q <= '0;
      requant_multiplier_flatten_q <= '0;
      requant_shift_flatten_q <= '0;
      act_mode_q <= ACT_BYPASS;
      tag_wr_ptr_q <= '0;
      tag_rd_ptr_q <= '0;
      tag_count_q <= '0;

      ub_rd_en_o <= 1'b0;
      ub_rd_bank_o <= 1'b0;
      ub_rd_addr_o <= '0;
      ub_rd_packed_en_o <= 1'b0;
      ub_rd_packed_bank_o <= 1'b0;
      ub_rd_packed_addr_o <= '0;
      ub_wr_en_o <= 1'b0;
      ub_wr_bank_o <= 1'b0;
      ub_wr_addr_o <= '0;
      ub_wr_data_o <= '0;
      ub_wr_spatial_idx_o <= '0;
      ub_wr_oc_idx_o <= '0;
      work_o <= 1'b0;
      start_wgt_load_o <= 1'b0;
      wgt_fifo_wdata_o <= '0;
      wgt_fifo_wr_en_o <= 1'b0;
      act_flat_raw_o <= '0;
      act_valid_raw_o <= '0;
      accumulator_clear_all_o <= 1'b0;
      accumulator_row_clear_o <= 1'b0;
      accumulator_row_clear_addr_o <= '0;
      accumulator_read_en_o <= 1'b0;
      accumulator_read_addr_o <= '0;
      vpu_input_done_o <= 1'b0;
      vpu_act_mode_o <= ACT_BYPASS;
      vpu_bias_flatten_o <= '0;
      vpu_requant_multiplier_flatten_o <= '0;
      vpu_requant_shift_flatten_o <= '0;
      vpu_output_zero_point_o <= '0;

      for (int idx = 0; idx < 2; idx++) begin
        act_read_lane_pipe_q[idx] <= '0;
        act_read_addr_pipe_q[idx] <= '0;
        act_read_packed_start_lane_pipe_q[idx] <= '0;
        act_read_packed_mask_pipe_q[idx] <= '0;
        act_read_packed_base_addr_pipe_q[idx] <= '0;
        act_prefetch_lane_pipe_q[idx] <= '0;
        act_prefetch_addr_pipe_q[idx] <= '0;
        act_prefetch_packed_start_lane_pipe_q[idx] <= '0;
        act_prefetch_packed_mask_pipe_q[idx] <= '0;
        act_prefetch_packed_base_addr_pipe_q[idx] <= '0;
      end

      for (int lane = 0; lane < SIZE; lane++) begin
        act_lane_q[lane] <= '0;
        act_prefetch_lane_data_q[lane] <= '0;
      end

      for (int idx = 0; idx < ACT_PREFETCH_DEPTH; idx++) begin
        act_prefetch_queue_data_q[idx] <= '0;
        act_prefetch_queue_stream_q[idx] <= '0;
      end

      for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
        act_reuse_valid_q[idx] <= 1'b0;
        act_reuse_addr_q[idx] <= '0;
        act_reuse_data_q[idx] <= '0;
      end

      for (int idx = 0; idx < TAG_DEPTH; idx++) begin
        tag_mem_q[idx] <= '0;
      end

      for (int idx = 0; idx < DBG_STATE_COUNT; idx++) begin
        state_exec_counts_q[idx] <= '0;
      end

      for (int idx = 0; idx < DBG_PREFETCH_COUNT; idx++) begin
        prefetch_counts_q[idx] <= '0;
      end
    end else begin : p_seq
      logic [ACT_REUSE_PTR_WIDTH-1:0] act_reuse_wr_ptr_next_v;
      logic act_reuse_found_v;
      logic [ACT_REUSE_PTR_WIDTH-1:0] act_reuse_slot_v;

      act_reuse_wr_ptr_next_v = act_reuse_wr_ptr_q;
      done_o <= 1'b0;
      ub_rd_en_o <= 1'b0;
      ub_rd_packed_en_o <= 1'b0;
      ub_wr_en_o <= 1'b0;
      work_o <= 1'b0;
      start_wgt_load_o <= 1'b0;
      wgt_fifo_wr_en_o <= 1'b0;
      act_flat_raw_o <= '0;
      act_valid_raw_o <= '0;
      accumulator_clear_all_o <= 1'b0;
      accumulator_row_clear_o <= 1'b0;
      accumulator_read_en_o <= 1'b0;
      vpu_input_done_o <= vpu_prefetch_done_q;
      vpu_act_mode_o <= act_mode_q;
      vpu_bias_flatten_o <= bias_flatten_q;
      vpu_requant_multiplier_flatten_o <= requant_multiplier_flatten_q;
      vpu_requant_shift_flatten_o <= requant_shift_flatten_q;
      vpu_output_zero_point_o <= '0;
      ub_wr_spatial_idx_o <= '0;
      ub_wr_oc_idx_o <= '0;

      act_read_valid_pipe_q[1] <= act_read_valid_pipe_q[0];
      act_read_valid_pipe_q[0] <= 1'b0;
      act_read_lane_pipe_q[1] <= act_read_lane_pipe_q[0];
      act_read_lane_pipe_q[0] <= '0;
      act_read_addr_pipe_q[1] <= act_read_addr_pipe_q[0];
      act_read_addr_pipe_q[0] <= '0;
      act_read_packed_valid_pipe_q[1] <= act_read_packed_valid_pipe_q[0];
      act_read_packed_valid_pipe_q[0] <= 1'b0;
      act_read_packed_start_lane_pipe_q[1] <= act_read_packed_start_lane_pipe_q[0];
      act_read_packed_start_lane_pipe_q[0] <= '0;
      act_read_packed_mask_pipe_q[1] <= act_read_packed_mask_pipe_q[0];
      act_read_packed_mask_pipe_q[0] <= '0;
      act_read_packed_base_addr_pipe_q[1] <= act_read_packed_base_addr_pipe_q[0];
      act_read_packed_base_addr_pipe_q[0] <= '0;
      act_prefetch_valid_pipe_q[1] <= act_prefetch_valid_pipe_q[0];
      act_prefetch_valid_pipe_q[0] <= 1'b0;
      act_prefetch_lane_pipe_q[1] <= act_prefetch_lane_pipe_q[0];
      act_prefetch_lane_pipe_q[0] <= '0;
      act_prefetch_addr_pipe_q[1] <= act_prefetch_addr_pipe_q[0];
      act_prefetch_addr_pipe_q[0] <= '0;
      act_prefetch_packed_valid_pipe_q[1] <= act_prefetch_packed_valid_pipe_q[0];
      act_prefetch_packed_valid_pipe_q[0] <= 1'b0;
      act_prefetch_packed_start_lane_pipe_q[1] <= act_prefetch_packed_start_lane_pipe_q[0];
      act_prefetch_packed_start_lane_pipe_q[0] <= '0;
      act_prefetch_packed_mask_pipe_q[1] <= act_prefetch_packed_mask_pipe_q[0];
      act_prefetch_packed_mask_pipe_q[0] <= '0;
      act_prefetch_packed_base_addr_pipe_q[1] <= act_prefetch_packed_base_addr_pipe_q[0];
      act_prefetch_packed_base_addr_pipe_q[0] <= '0;

      if (act_read_capture_w) begin
        act_lane_q[act_read_lane_pipe_q[1]] <= ub_rd_data_i;

        if (desc_layer_type_w == LAYER_CONV) begin
          act_reuse_found_v = 1'b0;
          act_reuse_slot_v = act_reuse_wr_ptr_next_v;
          for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
            if (!act_reuse_found_v
                && act_reuse_valid_q[idx]
                && (act_reuse_addr_q[idx] == act_read_addr_pipe_q[1])) begin
              act_reuse_found_v = 1'b1;
              act_reuse_slot_v = ACT_REUSE_PTR_WIDTH'(idx);
            end
          end

          act_reuse_valid_q[act_reuse_slot_v] <= 1'b1;
          act_reuse_addr_q[act_reuse_slot_v] <= act_read_addr_pipe_q[1];
          act_reuse_data_q[act_reuse_slot_v] <= ub_rd_data_i;
          if (!act_reuse_found_v) begin
            act_reuse_wr_ptr_next_v = next_act_reuse_ptr(act_reuse_wr_ptr_next_v);
          end
        end
      end

      if (act_read_packed_capture_w) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          if (act_read_packed_mask_pipe_q[1][lane]
              && (16'(lane) >= act_read_packed_start_lane_pipe_q[1])) begin
            logic [UB_ADDR_WIDTH-1:0] act_reuse_write_addr_w;

            act_lane_q[lane] <=
                ub_rd_packed_data_i[((lane - int'(act_read_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];

            if (desc_layer_type_w == LAYER_CONV) begin
              act_reuse_write_addr_w =
                  act_read_packed_base_addr_pipe_q[1]
                  + UB_ADDR_WIDTH'(lane - int'(act_read_packed_start_lane_pipe_q[1]));
              act_reuse_found_v = 1'b0;
              act_reuse_slot_v = act_reuse_wr_ptr_next_v;
              for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
                if (!act_reuse_found_v
                    && act_reuse_valid_q[idx]
                    && (act_reuse_addr_q[idx] == act_reuse_write_addr_w)) begin
                  act_reuse_found_v = 1'b1;
                  act_reuse_slot_v = ACT_REUSE_PTR_WIDTH'(idx);
                end
              end

              act_reuse_valid_q[act_reuse_slot_v] <= 1'b1;
              act_reuse_addr_q[act_reuse_slot_v] <= act_reuse_write_addr_w;
              act_reuse_data_q[act_reuse_slot_v] <=
                  ub_rd_packed_data_i[((lane - int'(act_read_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];
              if (!act_reuse_found_v) begin
                act_reuse_wr_ptr_next_v = next_act_reuse_ptr(act_reuse_wr_ptr_next_v);
              end
            end
          end
        end
      end

      if (act_prefetch_capture_w) begin
        act_prefetch_lane_data_q[act_prefetch_lane_pipe_q[1]] <= ub_rd_data_i;
        act_prefetch_lane_done_q[act_prefetch_lane_pipe_q[1]] <= 1'b1;
        prefetch_counts_q[PREFETCH_LANE_CAPTURE_IDX] <=
            prefetch_counts_q[PREFETCH_LANE_CAPTURE_IDX] + 32'd1;

        if (desc_layer_type_w == LAYER_CONV) begin
          act_reuse_found_v = 1'b0;
          act_reuse_slot_v = act_reuse_wr_ptr_next_v;
          for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
            if (!act_reuse_found_v
                && act_reuse_valid_q[idx]
                && (act_reuse_addr_q[idx] == act_prefetch_addr_pipe_q[1])) begin
              act_reuse_found_v = 1'b1;
              act_reuse_slot_v = ACT_REUSE_PTR_WIDTH'(idx);
            end
          end

          act_reuse_valid_q[act_reuse_slot_v] <= 1'b1;
          act_reuse_addr_q[act_reuse_slot_v] <= act_prefetch_addr_pipe_q[1];
          act_reuse_data_q[act_reuse_slot_v] <= ub_rd_data_i;
          if (!act_reuse_found_v) begin
            act_reuse_wr_ptr_next_v = next_act_reuse_ptr(act_reuse_wr_ptr_next_v);
          end
        end
      end

      if (act_prefetch_packed_capture_w) begin
        for (int lane = 0; lane < SIZE; lane++) begin
          if (act_prefetch_packed_mask_pipe_q[1][lane]
              && (16'(lane) >= act_prefetch_packed_start_lane_pipe_q[1])) begin
            logic [UB_ADDR_WIDTH-1:0] act_reuse_write_addr_w;

            act_prefetch_lane_data_q[lane] <=
                ub_rd_packed_data_i[((lane - int'(act_prefetch_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];
            act_prefetch_lane_done_q[lane] <= 1'b1;

            if (desc_layer_type_w == LAYER_CONV) begin
              act_reuse_write_addr_w =
                  act_prefetch_packed_base_addr_pipe_q[1]
                  + UB_ADDR_WIDTH'(lane - int'(act_prefetch_packed_start_lane_pipe_q[1]));
              act_reuse_found_v = 1'b0;
              act_reuse_slot_v = act_reuse_wr_ptr_next_v;
              for (int idx = 0; idx < ACT_REUSE_DEPTH; idx++) begin
                if (!act_reuse_found_v
                    && act_reuse_valid_q[idx]
                    && (act_reuse_addr_q[idx] == act_reuse_write_addr_w)) begin
                  act_reuse_found_v = 1'b1;
                  act_reuse_slot_v = ACT_REUSE_PTR_WIDTH'(idx);
                end
              end

              act_reuse_valid_q[act_reuse_slot_v] <= 1'b1;
              act_reuse_addr_q[act_reuse_slot_v] <= act_reuse_write_addr_w;
              act_reuse_data_q[act_reuse_slot_v] <=
                  ub_rd_packed_data_i[((lane - int'(act_prefetch_packed_start_lane_pipe_q[1]))*DATA_WIDTH)+:DATA_WIDTH];
              if (!act_reuse_found_v) begin
                act_reuse_wr_ptr_next_v = next_act_reuse_ptr(act_reuse_wr_ptr_next_v);
              end
            end
          end
        end
        prefetch_counts_q[PREFETCH_LANE_CAPTURE_IDX] <=
            prefetch_counts_q[PREFETCH_LANE_CAPTURE_IDX]
            + count_lane_mask(act_prefetch_packed_mask_pipe_q[1]);
      end

      act_reuse_wr_ptr_q <= act_reuse_wr_ptr_next_v;

      if ((state_q == S_DRAIN_MXU) && drain_payload_active_w) begin
        drain_prefetch_cycle_q <= drain_prefetch_cycle_q + 16'd1;
      end else if (state_q != S_DRAIN_MXU) begin
        drain_prefetch_cycle_q <= '0;
      end

      if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
        state_exec_counts_q[int'(state_q)] <= state_exec_counts_q[int'(state_q)] + 32'd1;
        prefetch_counts_q[PREFETCH_OCCUPANCY_SUM_IDX] <=
            prefetch_counts_q[PREFETCH_OCCUPANCY_SUM_IDX] + act_prefetch_occupancy_w;
        prefetch_counts_q[PREFETCH_OCCUPANCY_SAMPLES_IDX] <=
            prefetch_counts_q[PREFETCH_OCCUPANCY_SAMPLES_IDX] + 32'd1;
        prefetch_counts_q[PREFETCH_CURRENT_OCCUPANCY_IDX] <= act_prefetch_occupancy_w;

        if (act_prefetch_occupancy_w == 32'(ACT_PREFETCH_DEPTH)) begin
          prefetch_counts_q[PREFETCH_QUEUE_FULL_CYCLES_IDX] <=
              prefetch_counts_q[PREFETCH_QUEUE_FULL_CYCLES_IDX] + 32'd1;
        end

        if (act_prefetch_occupancy_w > prefetch_counts_q[PREFETCH_MAX_OCCUPANCY_IDX]) begin
          prefetch_counts_q[PREFETCH_MAX_OCCUPANCY_IDX] <= act_prefetch_occupancy_w;
        end

        if (act_prefetch_active_w) begin
          prefetch_counts_q[PREFETCH_BUSY_CYCLES_IDX] <=
              prefetch_counts_q[PREFETCH_BUSY_CYCLES_IDX] + 32'd1;
        end

        if ((act_prefetch_req_active_w && (act_prefetch_lane_q == '0))
            || act_prefetch_chain_lane_req_w) begin
          prefetch_counts_q[PREFETCH_VECTOR_START_IDX] <=
              prefetch_counts_q[PREFETCH_VECTOR_START_IDX] + 32'd1;
        end

        if (act_prefetch_lane_req_w) begin
          prefetch_counts_q[PREFETCH_LANE_REQ_IDX] <=
              prefetch_counts_q[PREFETCH_LANE_REQ_IDX] + act_prefetch_lane_req_count_w;
        end

        if (act_prefetch_ub_issue_w) begin
          prefetch_counts_q[PREFETCH_ISSUE_CYCLES_IDX] <=
              prefetch_counts_q[PREFETCH_ISSUE_CYCLES_IDX] + 32'd1;
        end

        if (act_prefetch_vector_push_w) begin
          prefetch_counts_q[PREFETCH_VECTOR_PUSH_IDX] <=
              prefetch_counts_q[PREFETCH_VECTOR_PUSH_IDX] + 32'd1;
        end

        if (act_prefetch_active_w
            && !act_prefetch_ub_issue_w
            && !act_prefetch_vector_done_w) begin
          prefetch_counts_q[PREFETCH_BUBBLE_CYCLES_IDX] <=
              prefetch_counts_q[PREFETCH_BUBBLE_CYCLES_IDX] + 32'd1;
        end
      end

      if (tag_overflow_w) begin
        state_q <= S_ERROR;
        error_o <= 1'b1;
        dbg_error_code_o <= ERR_TAG_OVERFLOW;
      end else if (tag_underflow_w) begin
        state_q <= S_ERROR;
        error_o <= 1'b1;
        dbg_error_code_o <= ERR_TAG_UNDERFLOW;
      end else begin
        if (state_q == S_CLEAR_ACC_BLOCK) begin
          tag_wr_ptr_q <= '0;
          tag_rd_ptr_q <= '0;
          tag_count_q <= '0;
        end else begin
          unique case ({tag_push_w, tag_pop_w})
            2'b10: begin
              tag_mem_q[tag_wr_ptr_q] <= stream_idx_q[ACC_ADDR_WIDTH-1:0];
              tag_wr_ptr_q <= next_tag_ptr(tag_wr_ptr_q);
              tag_count_q <= tag_count_q + TAG_COUNT_WIDTH'(1);
            end
            2'b01: begin
              tag_rd_ptr_q <= next_tag_ptr(tag_rd_ptr_q);
              tag_count_q <= tag_count_q - TAG_COUNT_WIDTH'(1);
            end
            2'b11: begin
              tag_mem_q[tag_wr_ptr_q] <= stream_idx_q[ACC_ADDR_WIDTH-1:0];
              tag_wr_ptr_q <= next_tag_ptr(tag_wr_ptr_q);
              tag_rd_ptr_q <= next_tag_ptr(tag_rd_ptr_q);
            end
            default: begin
            end
          endcase
        end

        unique case (state_q)
          S_IDLE: begin
            error_o <= 1'b0;
            dbg_error_code_o <= '0;

            if (start_i) begin
              layer_idx_q <= layer_idx_i;
              use_descriptor_banks_q <= use_descriptor_banks_i;
              read_bank_q <= read_bank_i;
              write_bank_q <= write_bank_i;
              activation_base_addr_q <= activation_base_addr_i;
              output_base_addr_q <= output_base_addr_i;
              block_size_q <= block_size_i;
              spatial_idx_q <= spatial_idx_i;
              oc_tile_idx_q <= oc_tile_idx_i;
              prefetch_state_q <= PREFETCH_IDLE;
              prefetch_k_tile_q <= '0;
              prefetch_weight_stream_row_q <= '0;
              act_prefetch_state_q <= ACT_PREFETCH_IDLE;
              act_prefetch_stream_idx_q <= '0;
              act_prefetch_lane_q <= '0;
              act_prefetch_valid_pipe_q <= '0;
              act_prefetch_packed_valid_pipe_q <= '0;
              act_prefetch_lane_done_q <= '0;
              act_prefetch_entry_valid_q <= '0;
              drain_prefetch_cycle_q <= '0;
              act_reuse_valid_q <= '0;
              act_reuse_wr_ptr_q <= '0;
              vpu_next_valid_q <= 1'b0;
              vpu_prefetch_pending_q <= 1'b0;
              vpu_prefetch_done_q <= 1'b0;
              dbg_cycle_count_o <= '0;
              dbg_useful_mac_count_o <= '0;
              for (int idx = 0; idx < DBG_STATE_COUNT; idx++) begin
                state_exec_counts_q[idx] <= '0;
              end
              for (int idx = 0; idx < DBG_PREFETCH_COUNT; idx++) begin
                prefetch_counts_q[idx] <= '0;
              end
              state_q <= S_CLEAR_ACC_BLOCK;
            end
          end

          S_CLEAR_ACC_BLOCK: begin
            if (SIZE < 2) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_SIZE;
            end else if (!desc_valid_w) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_DESC_INVALID;
            end else if ((block_size_q == '0) || (block_size_q > ACC_COUNT_WIDTH'(ACC_DEPTH))) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_BLOCK_SIZE;
            end else if ((ADDR_CALC_WIDTH'(spatial_idx_q) + ADDR_CALC_WIDTH'(block_size_q))
                         > ADDR_CALC_WIDTH'(desc_num_spatial_w)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_SPATIAL;
            end else if ((desc_num_k_tiles_w == '0)
                         || (desc_num_k_tiles_w > 16'(MAX_NUM_TILES))) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_K_TILE_COUNT;
            end else if (oc_tile_idx_q >= desc_num_oc_tiles_w) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_OC_TILE;
            end else begin
              accumulator_clear_all_o <= 1'b1;
              num_tiles_q <= TILE_COUNT_WIDTH'(desc_num_k_tiles_w);
              k_tile_q <= '0;
              prefetch_state_q <= PREFETCH_IDLE;
              prefetch_k_tile_q <= '0;
              prefetch_weight_stream_row_q <= '0;
              act_prefetch_state_q <= ACT_PREFETCH_IDLE;
              act_prefetch_stream_idx_q <= '0;
              act_prefetch_lane_q <= '0;
              act_prefetch_valid_pipe_q <= '0;
              act_prefetch_packed_valid_pipe_q <= '0;
              act_prefetch_lane_done_q <= '0;
              act_prefetch_entry_valid_q <= '0;
              act_reuse_valid_q <= '0;
              act_reuse_wr_ptr_q <= '0;
              vpu_next_valid_q <= 1'b0;
              vpu_prefetch_pending_q <= 1'b0;
              vpu_prefetch_done_q <= 1'b0;
              stream_idx_q <= '0;
              acc_read_idx_q <= '0;
              wgt_load_seen_q <= '0;
              state_q <= S_FETCH_ROM;
            end
          end

          S_FETCH_ROM: begin
            state_q <= S_WAIT_ROM;
          end

          S_WAIT_ROM: begin
            if ((weight_data_valid_w != {SIZE*SIZE{1'b1}})
                || (bias_data_valid_w != param_valid_required_w)
                || (requant_mult_valid_w != param_valid_required_w)
                || (requant_shift_valid_w != param_valid_required_w)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_ROM_VALID;
            end else begin
              for (int lane = 0; lane < SIZE; lane++) begin
                if (oc_valid_w[lane]) begin
                  bias_flatten_q[(lane*BIAS_WIDTH)+:BIAS_WIDTH] <= bias_data_w[lane];
                  requant_multiplier_flatten_q[(lane*REQUANT_MULT_WIDTH)+:REQUANT_MULT_WIDTH] <=
                      requant_mult_data_w[lane];
                  requant_shift_flatten_q[(lane*REQUANT_SHIFT_WIDTH)+:REQUANT_SHIFT_WIDTH] <=
                      requant_shift_data_w[lane];
                end else begin
                  bias_flatten_q[(lane*BIAS_WIDTH)+:BIAS_WIDTH] <= '0;
                  requant_multiplier_flatten_q[(lane*REQUANT_MULT_WIDTH)+:REQUANT_MULT_WIDTH] <= '0;
                  requant_shift_flatten_q[(lane*REQUANT_SHIFT_WIDTH)+:REQUANT_SHIFT_WIDTH] <= '0;
                end
              end

              act_mode_q <= desc_act_mode_w;
              weight_stream_row_q <= 16'(SIZE - 1);
              state_q <= S_WRITE_WEIGHT_ROW;
            end
          end

          S_WRITE_WEIGHT_ROW: begin
            if (wgt_fifo_full_i) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_WGT_FIFO_FULL;
            end else begin
              wgt_fifo_wdata_o <= weight_stream_row_data_w;
              wgt_fifo_wr_en_o <= 1'b1;

              if (weight_stream_row_q == 16'd0) begin
                start_wgt_load_o <= 1'b1;
                wgt_load_seen_q <= '0;
                state_q <= S_WAIT_WEIGHT_LOAD;
              end else begin
                weight_stream_row_q <= weight_stream_row_q - 16'd1;
              end
            end
          end

          S_START_WEIGHT_LOAD: begin
            if (wgt_fetcher_ready_i) begin
              start_wgt_load_o <= 1'b1;
              wgt_load_seen_q <= '0;
              state_q <= S_WAIT_WEIGHT_LOAD;
            end
          end

          S_WAIT_WEIGHT_LOAD: begin
            wgt_load_seen_q <= wgt_load_seen_q | wgt_load_done_i;
            if (&(wgt_load_seen_q | wgt_load_done_i)) begin
              stream_idx_q <= '0;
              act_fetch_lane_q <= '0;
              act_read_valid_pipe_q <= '0;
              act_read_packed_valid_pipe_q <= '0;
              act_read_lane_pipe_q[0] <= '0;
              act_read_lane_pipe_q[1] <= '0;
              act_read_addr_pipe_q[0] <= '0;
              act_read_addr_pipe_q[1] <= '0;
              act_read_packed_start_lane_pipe_q[0] <= '0;
              act_read_packed_start_lane_pipe_q[1] <= '0;
              act_read_packed_mask_pipe_q[0] <= '0;
              act_read_packed_mask_pipe_q[1] <= '0;
              act_read_packed_base_addr_pipe_q[0] <= '0;
              act_read_packed_base_addr_pipe_q[1] <= '0;
              if (act_prefetch_match_w) begin
                for (int lane = 0; lane < SIZE; lane++) begin
                  act_lane_q[lane] <= act_prefetch_match_data_w[(lane*DATA_WIDTH)+:DATA_WIDTH];
                end
                act_prefetch_entry_valid_q[act_prefetch_match_slot_w] <= 1'b0;
                prefetch_counts_q[PREFETCH_HITS_IDX] <=
                    prefetch_counts_q[PREFETCH_HITS_IDX] + 32'd1;
                state_q <= S_READ_ACT_WAIT;
              end else begin
                state_q <= S_READ_ACT_REQ;
              end
            end
          end

          S_READ_ACT_REQ: begin
            if (!last_k_tile_w) begin
              if (act_prefetch_queue_full_w) begin
                prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] <=
                    prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] + 32'd1;
              end else begin
                prefetch_counts_q[PREFETCH_STALL_UB_BUSY_IDX] <=
                    prefetch_counts_q[PREFETCH_STALL_UB_BUSY_IDX] + 32'd1;
              end
            end else begin
              prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] <=
                  prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] + 32'd1;
            end

            if (act_prefetch_match_w && (act_fetch_lane_q == '0)) begin
              for (int lane = 0; lane < SIZE; lane++) begin
                act_lane_q[lane] <= act_prefetch_match_data_w[(lane*DATA_WIDTH)+:DATA_WIDTH];
              end
              act_prefetch_entry_valid_q[act_prefetch_match_slot_w] <= 1'b0;
              prefetch_counts_q[PREFETCH_HITS_IDX] <=
                  prefetch_counts_q[PREFETCH_HITS_IDX] + 32'd1;
              state_q <= S_READ_ACT_WAIT;
            end else if (act_fetch_lane_q >= 16'(SIZE)) begin
              state_q <= S_READ_ACT_WAIT;
            end else begin
              if (act_fetch_lane_q == '0) begin
                prefetch_counts_q[PREFETCH_MISSES_IDX] <=
                    prefetch_counts_q[PREFETCH_MISSES_IDX] + 32'd1;
                if (act_prefetch_queue_empty_on_need_w) begin
                  prefetch_counts_q[PREFETCH_QUEUE_EMPTY_ON_NEED_IDX] <=
                      prefetch_counts_q[PREFETCH_QUEUE_EMPTY_ON_NEED_IDX] + 32'd1;
                end
                if (act_prefetch_occupancy_w == 32'd0) begin
                  prefetch_counts_q[PREFETCH_MISS_NO_ENTRY_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_NO_ENTRY_IDX] + 32'd1;
                end else if (!act_prefetch_k_tag_match_w) begin
                  prefetch_counts_q[PREFETCH_MISS_WRONG_K_TILE_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_WRONG_K_TILE_IDX] + 32'd1;
                end else if (!act_prefetch_read_bank_tag_match_w) begin
                  prefetch_counts_q[PREFETCH_MISS_TAG_MISMATCH_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_TAG_MISMATCH_IDX] + 32'd1;
                end else if (act_prefetch_lane_incomplete_on_need_w) begin
                  prefetch_counts_q[PREFETCH_MISS_LANE_INCOMPLETE_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_LANE_INCOMPLETE_IDX] + 32'd1;
                end else if (act_prefetch_wrong_spatial_entry_w) begin
                  prefetch_counts_q[PREFETCH_MISS_WRONG_SPATIAL_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_WRONG_SPATIAL_IDX] + 32'd1;
                end else begin
                  prefetch_counts_q[PREFETCH_MISS_NO_ENTRY_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_NO_ENTRY_IDX] + 32'd1;
                end
              end

              if (act_reuse_prefix_valid_w
                  && (!act_packed_prefix_valid_w
                      || (act_reuse_next_lane_w >= 16'(SIZE)))) begin
                for (int lane = 0; lane < SIZE; lane++) begin
                  if (act_reuse_prefix_mask_w[lane]) begin
                    if (act_zero_w[lane]) begin
                      act_lane_q[lane] <= '0;
                    end else begin
                      act_lane_q[lane] <= act_reuse_lane_data_w[lane];
                    end
                  end
                end

                if (act_reuse_next_lane_w >= 16'(SIZE)) begin
                  act_fetch_lane_q <= 16'(SIZE);
                  state_q <= S_READ_ACT_WAIT;
                end else begin
                  act_fetch_lane_q <= act_reuse_next_lane_w;
                end
              end else if (act_packed_prefix_valid_w) begin
                ub_rd_packed_en_o <= 1'b1;
                ub_rd_packed_bank_o <= inner_read_bank_w;
                ub_rd_packed_addr_o <= UB_ADDR_WIDTH'(act_packed_base_addr_w);
                act_read_packed_valid_pipe_q[0] <= 1'b1;
                act_read_packed_start_lane_pipe_q[0] <= act_fetch_lane_q;
                act_read_packed_mask_pipe_q[0] <= act_packed_prefix_mask_w;
                act_read_packed_base_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_packed_base_addr_w);

                if (act_packed_next_lane_w >= 16'(SIZE)) begin
                  act_fetch_lane_q <= 16'(SIZE);
                  state_q <= S_READ_ACT_WAIT;
                end else begin
                  act_fetch_lane_q <= act_packed_next_lane_w;
                end
              end else if (act_zero_w[act_fetch_lane_q]) begin
                act_lane_q[act_fetch_lane_q] <= '0;
              end else if (act_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH)) begin
                state_q <= S_ERROR;
                error_o <= 1'b1;
                dbg_error_code_o <= ERR_INPUT_ADDR;
              end else begin
                ub_rd_en_o <= 1'b1;
                ub_rd_bank_o <= inner_read_bank_w;
                ub_rd_addr_o <= UB_ADDR_WIDTH'(act_lane_addr_w);
                act_read_valid_pipe_q[0] <= 1'b1;
                act_read_lane_pipe_q[0] <= act_fetch_lane_q;
                act_read_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_lane_addr_w);
              end

              if (act_reuse_prefix_valid_w || act_packed_prefix_valid_w) begin
                // act_fetch_lane_q/state_q already updated above.
              end else if (act_zero_w[act_fetch_lane_q]
                  || (act_lane_addr_w < ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                if ((act_fetch_lane_q + 16'd1) >= 16'(SIZE)) begin
                  act_fetch_lane_q <= 16'(SIZE);
                  state_q <= S_READ_ACT_WAIT;
                end else begin
                  act_fetch_lane_q <= act_fetch_lane_q + 16'd1;
                end
              end
            end
          end

          S_READ_ACT_WAIT: begin
            if (act_read_pipeline_empty_w) begin
              if (act_prefetch_early_service_w) begin
                if (act_prefetch_can_start_next_w) begin
                  prefetch_k_tile_q <= k_tile_q + 16'd1;
                  act_prefetch_stream_idx_q <= '0;
                  act_prefetch_lane_q <= '0;
                  act_prefetch_valid_pipe_q <= '0;
                  act_prefetch_packed_valid_pipe_q <= '0;
                  act_prefetch_lane_done_q <= '0;
                  if (|act_prefetch_entry_valid_q) begin
                    prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] <=
                        prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] + 32'd1;
                    prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] <=
                        prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] + 32'd1;
                  end
                  act_prefetch_entry_valid_q <= '0;
                  act_prefetch_tag_k_tile_q <= k_tile_q + 16'd1;
                  act_prefetch_tag_read_bank_q <= inner_read_bank_w;

                  prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] <=
                      prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] + 32'd1;
                  prefetch_counts_q[PREFETCH_EARLY_ATTEMPTS_IDX] <=
                      prefetch_counts_q[PREFETCH_EARLY_ATTEMPTS_IDX] + 32'd1;

                  for (int lane = 0; lane < SIZE; lane++) begin
                    if (act_prefetch_zero_lane_mask_w[lane]) begin
                      act_prefetch_lane_data_q[lane] <= '0;
                      act_prefetch_lane_done_q[lane] <= 1'b1;
                    end
                  end

                  if (act_prefetch_packed_issue_w) begin
                    ub_rd_packed_en_o <= 1'b1;
                    ub_rd_packed_bank_o <= inner_read_bank_w;
                    ub_rd_packed_addr_o <= UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                    act_prefetch_packed_valid_pipe_q[0] <= 1'b1;
                    act_prefetch_packed_start_lane_pipe_q[0] <=
                        act_prefetch_packed_start_lane_w;
                    act_prefetch_packed_mask_pipe_q[0] <= act_prefetch_packed_mask_w;
                    act_prefetch_packed_base_addr_pipe_q[0] <=
                        UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                  end else if (act_prefetch_issue_lane_found_w
                      && (act_prefetch_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                    state_q <= S_ERROR;
                    error_o <= 1'b1;
                    dbg_error_code_o <= ERR_INPUT_ADDR;
                  end else if (act_prefetch_issue_lane_found_w) begin
                    ub_rd_en_o <= 1'b1;
                    ub_rd_bank_o <= inner_read_bank_w;
                    ub_rd_addr_o <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                    act_prefetch_valid_pipe_q[0] <= 1'b1;
                    act_prefetch_lane_pipe_q[0] <= act_prefetch_issue_lane_w;
                    act_prefetch_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                  end

                  if (act_prefetch_next_lane_w >= 16'(SIZE)) begin
                    act_prefetch_lane_q <= 16'(SIZE);
                    act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                  end else begin
                    act_prefetch_lane_q <= act_prefetch_next_lane_w;
                    act_prefetch_state_q <= ACT_PREFETCH_REQ;
                  end
                end else if (!act_prefetch_has_candidate_w) begin
                  prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] <=
                      prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] + 32'd1;
                end else if (act_prefetch_queue_full_w) begin
                  prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] <=
                      prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] + 32'd1;
                end else begin
                  unique case (act_prefetch_state_q)
                    ACT_PREFETCH_REQ: begin
                      if (act_prefetch_lane_q >= 16'(SIZE)) begin
                        act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                      end else begin
                        if (act_prefetch_lane_q == '0) begin
                          prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] <=
                              prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] + 32'd1;
                          prefetch_counts_q[PREFETCH_EARLY_ATTEMPTS_IDX] <=
                              prefetch_counts_q[PREFETCH_EARLY_ATTEMPTS_IDX] + 32'd1;
                        end

                        for (int lane = 0; lane < SIZE; lane++) begin
                          if (act_prefetch_zero_lane_mask_w[lane]) begin
                            act_prefetch_lane_data_q[lane] <= '0;
                            act_prefetch_lane_done_q[lane] <= 1'b1;
                          end
                        end

                        if (act_prefetch_packed_issue_w) begin
                          ub_rd_packed_en_o <= 1'b1;
                          ub_rd_packed_bank_o <= inner_read_bank_w;
                          ub_rd_packed_addr_o <= UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                          act_prefetch_packed_valid_pipe_q[0] <= 1'b1;
                          act_prefetch_packed_start_lane_pipe_q[0] <=
                              act_prefetch_packed_start_lane_w;
                          act_prefetch_packed_mask_pipe_q[0] <= act_prefetch_packed_mask_w;
                          act_prefetch_packed_base_addr_pipe_q[0] <=
                              UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                        end else if (act_prefetch_issue_lane_found_w
                            && (act_prefetch_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                          state_q <= S_ERROR;
                          error_o <= 1'b1;
                          dbg_error_code_o <= ERR_INPUT_ADDR;
                        end else if (act_prefetch_issue_lane_found_w) begin
                          ub_rd_en_o <= 1'b1;
                          ub_rd_bank_o <= inner_read_bank_w;
                          ub_rd_addr_o <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                          act_prefetch_valid_pipe_q[0] <= 1'b1;
                          act_prefetch_lane_pipe_q[0] <= act_prefetch_issue_lane_w;
                          act_prefetch_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                        end

                        if (act_prefetch_next_lane_w >= 16'(SIZE)) begin
                          act_prefetch_lane_q <= 16'(SIZE);
                          act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                        end else begin
                          act_prefetch_lane_q <= act_prefetch_next_lane_w;
                        end
                      end
                    end

                    ACT_PREFETCH_WAIT: begin
                      if (act_prefetch_pipe_empty_w
                          && (act_prefetch_lane_done_next_w == {SIZE{1'b1}})) begin
                        if (act_prefetch_push_slot_valid_w) begin
                          act_prefetch_queue_data_q[act_prefetch_push_slot_w] <=
                              act_prefetch_vector_next_w;
                          act_prefetch_queue_stream_q[act_prefetch_push_slot_w] <=
                              act_prefetch_stream_idx_q;
                          act_prefetch_entry_valid_q[act_prefetch_push_slot_w] <= 1'b1;
                          prefetch_counts_q[PREFETCH_PUSHES_IDX] <=
                              prefetch_counts_q[PREFETCH_PUSHES_IDX] + 32'd1;
                          prefetch_counts_q[PREFETCH_EARLY_PUSHES_IDX] <=
                              prefetch_counts_q[PREFETCH_EARLY_PUSHES_IDX] + 32'd1;
                        end else begin
                          prefetch_counts_q[PREFETCH_DROPS_FULL_IDX] <=
                              prefetch_counts_q[PREFETCH_DROPS_FULL_IDX] + 32'd1;
                        end

                        if (act_prefetch_can_continue_w) begin
                          act_prefetch_stream_idx_q <= act_prefetch_next_stream_idx_w;
                          act_prefetch_lane_q <= '0;
                          act_prefetch_valid_pipe_q <= '0;
                          act_prefetch_packed_valid_pipe_q <= '0;
                          act_prefetch_lane_done_q <= '0;
                          act_prefetch_state_q <= ACT_PREFETCH_REQ;
                        end else begin
                          act_prefetch_state_q <= ACT_PREFETCH_DONE;
                        end
                      end
                    end

                    default: begin
                    end
                  endcase
                end
              end

              if (!act_prefetch_addr_error_w) begin
                act_flat_raw_o <= act_flatten_launch_w;
                act_valid_raw_o <= {SIZE{1'b1}};
                work_o <= 1'b1;
                dbg_useful_mac_count_o <= dbg_useful_mac_count_o + count_valid_weights(weight_valid_w);

                if ((stream_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
                  stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
                  if (!last_k_tile_w) begin
                    prefetch_state_q <= PREFETCH_FETCH_ROM;
                    prefetch_k_tile_q <= k_tile_q + 16'd1;
                    prefetch_weight_stream_row_q <= 16'(SIZE - 1);
                    if (!act_prefetch_next_tag_match_w) begin
                      act_prefetch_state_q <= ACT_PREFETCH_REQ;
                      act_prefetch_stream_idx_q <= '0;
                      act_prefetch_lane_q <= '0;
                      act_prefetch_valid_pipe_q <= '0;
                      act_prefetch_packed_valid_pipe_q <= '0;
                      act_prefetch_lane_done_q <= '0;
                      if (|act_prefetch_entry_valid_q) begin
                        prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] <=
                            prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] + 32'd1;
                        prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] <=
                            prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] + 32'd1;
                      end
                      act_prefetch_entry_valid_q <= '0;
                      act_prefetch_tag_k_tile_q <= k_tile_q + 16'd1;
                      act_prefetch_tag_read_bank_q <= inner_read_bank_w;
                    end
                  end else begin
                    prefetch_state_q <= PREFETCH_IDLE;
                    if (|act_prefetch_entry_valid_q) begin
                      prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] <=
                          prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] + 32'd1;
                      prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] <=
                          prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] + 32'd1;
                    end
                    act_prefetch_state_q <= ACT_PREFETCH_IDLE;
                  end
                  state_q <= S_DRAIN_MXU;
                end else begin
                  stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
                  act_fetch_lane_q <= '0;
                  act_read_valid_pipe_q <= '0;
                  act_read_packed_valid_pipe_q <= '0;
                  act_read_lane_pipe_q[0] <= '0;
                  act_read_lane_pipe_q[1] <= '0;
                  act_read_addr_pipe_q[0] <= '0;
                  act_read_addr_pipe_q[1] <= '0;
                  act_read_packed_start_lane_pipe_q[0] <= '0;
                  act_read_packed_start_lane_pipe_q[1] <= '0;
                  act_read_packed_mask_pipe_q[0] <= '0;
                  act_read_packed_mask_pipe_q[1] <= '0;
                  act_read_packed_base_addr_pipe_q[0] <= '0;
                  act_read_packed_base_addr_pipe_q[1] <= '0;
                  state_q <= S_READ_ACT_REQ;
                end
              end
            end
          end

          S_LAUNCH_ACT: begin
            act_flat_raw_o <= act_flatten_launch_w;
            act_valid_raw_o <= {SIZE{1'b1}};
            work_o <= 1'b1;
            dbg_useful_mac_count_o <= dbg_useful_mac_count_o + count_valid_weights(weight_valid_w);

            if ((stream_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              if (!last_k_tile_w) begin
                prefetch_state_q <= PREFETCH_FETCH_ROM;
                prefetch_k_tile_q <= k_tile_q + 16'd1;
                prefetch_weight_stream_row_q <= 16'(SIZE - 1);
                if (!act_prefetch_next_tag_match_w) begin
                  act_prefetch_state_q <= ACT_PREFETCH_REQ;
                  act_prefetch_stream_idx_q <= '0;
                  act_prefetch_lane_q <= '0;
                  act_prefetch_valid_pipe_q <= '0;
                  act_prefetch_packed_valid_pipe_q <= '0;
                  act_prefetch_lane_done_q <= '0;
                  if (|act_prefetch_entry_valid_q) begin
                    prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] <=
                        prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] + 32'd1;
                    prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] <=
                        prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] + 32'd1;
                  end
                  act_prefetch_entry_valid_q <= '0;
                  act_prefetch_tag_k_tile_q <= k_tile_q + 16'd1;
                  act_prefetch_tag_read_bank_q <= inner_read_bank_w;
                end
              end else begin
                prefetch_state_q <= PREFETCH_IDLE;
                if (|act_prefetch_entry_valid_q) begin
                  prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] <=
                      prefetch_counts_q[PREFETCH_INVALIDATED_BOUNDARY_IDX] + 32'd1;
                  prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] <=
                      prefetch_counts_q[PREFETCH_MISS_INVALID_BOUNDARY_IDX] + 32'd1;
                end
                act_prefetch_state_q <= ACT_PREFETCH_IDLE;
              end
              state_q <= S_DRAIN_MXU;
            end else begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              act_fetch_lane_q <= '0;
              act_read_valid_pipe_q <= '0;
              act_read_packed_valid_pipe_q <= '0;
              act_read_lane_pipe_q[0] <= '0;
              act_read_lane_pipe_q[1] <= '0;
              act_read_addr_pipe_q[0] <= '0;
              act_read_addr_pipe_q[1] <= '0;
              act_read_packed_start_lane_pipe_q[0] <= '0;
              act_read_packed_start_lane_pipe_q[1] <= '0;
              act_read_packed_mask_pipe_q[0] <= '0;
              act_read_packed_mask_pipe_q[1] <= '0;
              act_read_packed_base_addr_pipe_q[0] <= '0;
              act_read_packed_base_addr_pipe_q[1] <= '0;
              state_q <= S_READ_ACT_REQ;
            end
          end

          S_DRAIN_MXU: begin
            // Hide next K-tile ROM/FIFO preparation under drain, but do not
            // switch PE active weights until all old psums have packed.
            unique case (prefetch_state_q)
              PREFETCH_FETCH_ROM: begin
                prefetch_state_q <= PREFETCH_WAIT_ROM;
              end

              PREFETCH_WAIT_ROM: begin
                if (weight_data_valid_w != {SIZE*SIZE{1'b1}}) begin
                  state_q <= S_ERROR;
                  error_o <= 1'b1;
                  dbg_error_code_o <= ERR_ROM_VALID;
                end else begin
                  prefetch_state_q <= PREFETCH_WRITE_WEIGHT_ROW;
                end
              end

              PREFETCH_WRITE_WEIGHT_ROW: begin
                if (!wgt_fifo_full_i) begin
                  wgt_fifo_wdata_o <= weight_stream_row_data_w;
                  wgt_fifo_wr_en_o <= 1'b1;

                  if (prefetch_weight_stream_row_q == 16'd0) begin
                    prefetch_state_q <= PREFETCH_DONE;
                  end else begin
                    prefetch_weight_stream_row_q <= prefetch_weight_stream_row_q - 16'd1;
                  end
                end
              end

              default: begin
              end
            endcase

            if (drain_payload_active_w) begin
              // Fetch activation vectors for the next K tile only while there
              // is real drain payload. Prefetch must never extend drain.
              if (!act_prefetch_has_candidate_w) begin
                prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] <=
                    prefetch_counts_q[PREFETCH_STALL_NO_CANDIDATE_IDX] + 32'd1;
              end else if (act_prefetch_queue_full_w) begin
                prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] <=
                    prefetch_counts_q[PREFETCH_STALL_QUEUE_FULL_IDX] + 32'd1;
              end else begin
                unique case (act_prefetch_state_q)
                  ACT_PREFETCH_REQ: begin
                    if (act_prefetch_lane_q >= 16'(SIZE)) begin
                      act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                    end else begin
                      if (act_prefetch_lane_q == '0) begin
                        prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] <=
                            prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] + 32'd1;
                        prefetch_counts_q[PREFETCH_DRAIN_ATTEMPTS_IDX] <=
                            prefetch_counts_q[PREFETCH_DRAIN_ATTEMPTS_IDX] + 32'd1;
                      end

                      for (int lane = 0; lane < SIZE; lane++) begin
                        if (act_prefetch_zero_lane_mask_w[lane]) begin
                          act_prefetch_lane_data_q[lane] <= '0;
                          act_prefetch_lane_done_q[lane] <= 1'b1;
                        end
                      end

                      if (act_prefetch_packed_issue_w) begin
                        ub_rd_packed_en_o <= 1'b1;
                        ub_rd_packed_bank_o <= inner_read_bank_w;
                        ub_rd_packed_addr_o <= UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                        act_prefetch_packed_valid_pipe_q[0] <= 1'b1;
                        act_prefetch_packed_start_lane_pipe_q[0] <=
                            act_prefetch_packed_start_lane_w;
                        act_prefetch_packed_mask_pipe_q[0] <= act_prefetch_packed_mask_w;
                        act_prefetch_packed_base_addr_pipe_q[0] <=
                            UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                      end else if (act_prefetch_issue_lane_found_w
                          && (act_prefetch_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                        state_q <= S_ERROR;
                        error_o <= 1'b1;
                        dbg_error_code_o <= ERR_INPUT_ADDR;
                      end else if (act_prefetch_issue_lane_found_w) begin
                        ub_rd_en_o <= 1'b1;
                        ub_rd_bank_o <= inner_read_bank_w;
                        ub_rd_addr_o <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                        act_prefetch_valid_pipe_q[0] <= 1'b1;
                        act_prefetch_lane_pipe_q[0] <= act_prefetch_issue_lane_w;
                        act_prefetch_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                      end

                      if (act_prefetch_next_lane_w >= 16'(SIZE)) begin
                        act_prefetch_lane_q <= 16'(SIZE);
                        act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                      end else begin
                        act_prefetch_lane_q <= act_prefetch_next_lane_w;
                      end
                    end
                  end

                  ACT_PREFETCH_WAIT: begin
                    if (act_prefetch_pipe_empty_w
                        && (act_prefetch_lane_done_next_w == {SIZE{1'b1}})) begin
                      if (act_prefetch_push_slot_valid_w) begin
                        act_prefetch_queue_data_q[act_prefetch_push_slot_w] <=
                            act_prefetch_vector_next_w;
                        act_prefetch_queue_stream_q[act_prefetch_push_slot_w] <=
                            act_prefetch_stream_idx_q;
                        act_prefetch_entry_valid_q[act_prefetch_push_slot_w] <= 1'b1;
                        prefetch_counts_q[PREFETCH_PUSHES_IDX] <=
                            prefetch_counts_q[PREFETCH_PUSHES_IDX] + 32'd1;
                        prefetch_counts_q[PREFETCH_DRAIN_PUSHES_IDX] <=
                            prefetch_counts_q[PREFETCH_DRAIN_PUSHES_IDX] + 32'd1;
                      end else begin
                        prefetch_counts_q[PREFETCH_DROPS_FULL_IDX] <=
                            prefetch_counts_q[PREFETCH_DROPS_FULL_IDX] + 32'd1;
                      end

                      if (act_prefetch_can_continue_w) begin
                        act_prefetch_stream_idx_q <= act_prefetch_next_stream_idx_w;
                        act_prefetch_valid_pipe_q <= '0;
                        act_prefetch_packed_valid_pipe_q <= '0;
                        act_prefetch_lane_done_q <= '0;

                        if (act_prefetch_chain_issue_w) begin
                          prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] <=
                              prefetch_counts_q[PREFETCH_ATTEMPTS_IDX] + 32'd1;
                          prefetch_counts_q[PREFETCH_DRAIN_ATTEMPTS_IDX] <=
                              prefetch_counts_q[PREFETCH_DRAIN_ATTEMPTS_IDX] + 32'd1;

                          for (int lane = 0; lane < SIZE; lane++) begin
                            if (act_prefetch_zero_lane_mask_w[lane]) begin
                              act_prefetch_lane_data_q[lane] <= '0;
                              act_prefetch_lane_done_q[lane] <= 1'b1;
                            end
                          end

                          if (act_prefetch_packed_issue_w) begin
                            ub_rd_packed_en_o <= 1'b1;
                            ub_rd_packed_bank_o <= inner_read_bank_w;
                            ub_rd_packed_addr_o <= UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                            act_prefetch_packed_valid_pipe_q[0] <= 1'b1;
                            act_prefetch_packed_start_lane_pipe_q[0] <=
                                act_prefetch_packed_start_lane_w;
                            act_prefetch_packed_mask_pipe_q[0] <= act_prefetch_packed_mask_w;
                            act_prefetch_packed_base_addr_pipe_q[0] <=
                                UB_ADDR_WIDTH'(act_prefetch_packed_base_addr_w);
                          end else if (act_prefetch_issue_lane_found_w
                              && (act_prefetch_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                            state_q <= S_ERROR;
                            error_o <= 1'b1;
                            dbg_error_code_o <= ERR_INPUT_ADDR;
                          end else if (act_prefetch_issue_lane_found_w) begin
                            ub_rd_en_o <= 1'b1;
                            ub_rd_bank_o <= inner_read_bank_w;
                            ub_rd_addr_o <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                            act_prefetch_valid_pipe_q[0] <= 1'b1;
                            act_prefetch_lane_pipe_q[0] <= act_prefetch_issue_lane_w;
                            act_prefetch_addr_pipe_q[0] <= UB_ADDR_WIDTH'(act_prefetch_lane_addr_w);
                          end

                          if (act_prefetch_next_lane_w >= 16'(SIZE)) begin
                            act_prefetch_lane_q <= 16'(SIZE);
                            act_prefetch_state_q <= ACT_PREFETCH_WAIT;
                          end else begin
                            act_prefetch_lane_q <= act_prefetch_next_lane_w;
                            act_prefetch_state_q <= ACT_PREFETCH_REQ;
                          end
                        end else begin
                          act_prefetch_lane_q <= '0;
                          act_prefetch_state_q <= ACT_PREFETCH_REQ;
                        end
                      end else begin
                        act_prefetch_state_q <= ACT_PREFETCH_DONE;
                      end
                    end
                  end

                  default: begin
                  end
                endcase
              end
            end

            if (!act_prefetch_addr_error_w && !drain_payload_active_w) begin
              act_prefetch_state_q <= ACT_PREFETCH_IDLE;
              act_prefetch_valid_pipe_q <= '0;
              act_prefetch_packed_valid_pipe_q <= '0;
              act_prefetch_lane_q <= '0;
              act_prefetch_lane_done_q <= '0;
              if (last_k_tile_w) begin
                state_q <= S_WAIT_ACC_READY;
              end else if (prefetch_state_q == PREFETCH_DONE) begin
                k_tile_q <= prefetch_k_tile_q;
                prefetch_state_q <= PREFETCH_IDLE;
                stream_idx_q <= '0;
                wgt_load_seen_q <= '0;

                if (wgt_fetcher_ready_i) begin
                  start_wgt_load_o <= 1'b1;
                  state_q <= S_WAIT_WEIGHT_LOAD;
                end else begin
                  state_q <= S_START_WEIGHT_LOAD;
                end
              end else if (prefetch_state_q == PREFETCH_IDLE) begin
                k_tile_q <= k_tile_q + 16'd1;
                stream_idx_q <= '0;
                state_q <= S_FETCH_ROM;
              end else begin
                stream_idx_q <= '0;
              end
            end
          end

          S_WAIT_ACC_READY: begin
            if (all_rows_ready_w) begin
              acc_read_idx_q <= '0;
              state_q <= S_READ_ACC_ROW;
            end
          end

          S_READ_ACC_ROW: begin
            accumulator_read_en_o <= 1'b1;
            accumulator_read_addr_o <= acc_read_idx_q[ACC_ADDR_WIDTH-1:0];
            vpu_input_done_o <= (acc_read_idx_q == (block_size_q - ACC_COUNT_WIDTH'(1)));
            state_q <= S_WAIT_VPU_OUTPUT;
          end

          S_WAIT_VPU_OUTPUT: begin
            vpu_input_done_o <= vpu_prefetch_pending_q
                              ? vpu_prefetch_done_q
                              : (acc_read_idx_q == (block_size_q - ACC_COUNT_WIDTH'(1)));
            if (vpu_data_valid_i) begin
              vpu_data_q <= vpu_data_flatten_i;
              vpu_next_valid_q <= 1'b0;
              if (vpu_prefetch_pending_q) begin
                vpu_prefetch_pending_q <= 1'b0;
                vpu_prefetch_done_q <= 1'b0;
              end

              if (has_next_acc_row_w) begin
                accumulator_read_en_o <= 1'b1;
                accumulator_read_addr_o <= next_acc_read_idx_w[ACC_ADDR_WIDTH-1:0];
                vpu_prefetch_pending_q <= 1'b1;
                vpu_prefetch_done_q <= !has_row_after_next_w;
              end

              output_lane_q <= '0;
              state_q <= S_WRITE_OUTPUT_LANE;
            end
          end

          S_WRITE_OUTPUT_LANE: begin
            if (vpu_prefetch_pending_q && vpu_data_valid_i) begin
              vpu_next_data_q <= vpu_data_flatten_i;
              vpu_next_valid_q <= 1'b1;
              vpu_prefetch_pending_q <= 1'b0;
              vpu_prefetch_done_q <= 1'b0;
            end

            if (!oc_valid_w[output_lane_q]) begin
              if (output_lane_last_w) begin
                if (!has_next_acc_row_w) begin
                  state_q <= S_DONE;
                end else if (prefetched_vpu_available_w) begin
                  acc_read_idx_q <= next_acc_read_idx_w;
                  vpu_data_q <= prefetched_vpu_data_w;
                  vpu_next_valid_q <= 1'b0;
                  output_lane_q <= '0;

                  if (has_row_after_next_w) begin
                    accumulator_read_en_o <= 1'b1;
                    accumulator_read_addr_o <= row_after_next_acc_idx_w[ACC_ADDR_WIDTH-1:0];
                    vpu_prefetch_pending_q <= 1'b1;
                    vpu_prefetch_done_q <= row_after_next_is_last_w;
                  end

                  state_q <= S_WRITE_OUTPUT_LANE;
                end else begin
                  acc_read_idx_q <= next_acc_read_idx_w;
                  output_lane_q <= '0;
                  state_q <= S_WAIT_VPU_OUTPUT;
                end
              end else begin
                output_lane_q <= output_lane_q + 16'd1;
              end
            end else if (output_lane_addr_w >= ADDR_CALC_WIDTH'(BANK_DEPTH)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_OUTPUT_ADDR;
            end else begin
              ub_wr_en_o <= 1'b1;
              ub_wr_bank_o <= inner_write_bank_w;
              ub_wr_addr_o <= UB_ADDR_WIDTH'(output_lane_addr_w);
              ub_wr_data_o <= vpu_data_q[(output_lane_q*OUT_WIDTH)+:OUT_WIDTH];
              ub_wr_spatial_idx_o <= output_spatial_w[15:0];
              ub_wr_oc_idx_o <= oc_idx_w[output_lane_q];

              if (output_lane_last_w) begin
                if (!has_next_acc_row_w) begin
                  state_q <= S_DONE;
                end else if (prefetched_vpu_available_w) begin
                  acc_read_idx_q <= next_acc_read_idx_w;
                  vpu_data_q <= prefetched_vpu_data_w;
                  vpu_next_valid_q <= 1'b0;
                  output_lane_q <= '0;

                  if (has_row_after_next_w) begin
                    accumulator_read_en_o <= 1'b1;
                    accumulator_read_addr_o <= row_after_next_acc_idx_w[ACC_ADDR_WIDTH-1:0];
                    vpu_prefetch_pending_q <= 1'b1;
                    vpu_prefetch_done_q <= row_after_next_is_last_w;
                  end

                  state_q <= S_WRITE_OUTPUT_LANE;
                end else begin
                  acc_read_idx_q <= next_acc_read_idx_w;
                  output_lane_q <= '0;
                  state_q <= S_WAIT_VPU_OUTPUT;
                end
              end else begin
                output_lane_q <= output_lane_q + 16'd1;
              end
            end
          end

          S_DONE: begin
            done_o <= 1'b1;
            if (!start_i) begin
              state_q <= S_IDLE;
            end
          end

          S_ERROR: begin
            error_o <= 1'b1;
          end

          default: begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
          end
        endcase
      end
    end
  end

endmodule : controller_kloop

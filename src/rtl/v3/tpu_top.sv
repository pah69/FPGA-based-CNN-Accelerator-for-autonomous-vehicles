`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// End-to-end small-CNN sequencer around the V3 request-based layer datapath.
module tpu_top #(
    parameter int SIZE                = 2,
    parameter int DATA_WIDTH          = 8,
    parameter int LOCAL_PSUM_WIDTH    = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int ACC_WIDTH           = 32,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int OUT_WIDTH           = 8,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int MAX_NUM_TILES       = 128,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1,
    parameter int MAC_COUNT_WIDTH     = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1,
    parameter int WGT_FIFO_DEPTH      = 16,
    parameter int BANK_DEPTH          = 8192,
    parameter int UB_ADDR_WIDTH       = (BANK_DEPTH > 1) ? $clog2(BANK_DEPTH) : 1,
    parameter string WGT_INIT_FILE    = "small_cnn_sym_weights_i8.mem",
    parameter string BIAS_INIT_FILE   = "small_cnn_sym_biases_i32.mem",
    parameter string REQUANT_MULT_INIT_FILE = "small_cnn_sym_requant_mult_i32.mem",
    parameter string REQUANT_SHIFT_INIT_FILE = "small_cnn_sym_requant_shift_u6.mem"
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [2:0] dbg_stage_o,
    output logic [31:0] dbg_cycle_count_o,
    output logic [31:0] dbg_conv1_cycle_count_o,
    output logic [31:0] dbg_pool1_cycle_count_o,
    output logic [31:0] dbg_conv2_cycle_count_o,
    output logic [31:0] dbg_pool2_cycle_count_o,
    output logic [31:0] dbg_fc1_cycle_count_o,
    output logic [31:0] dbg_fc2_cycle_count_o,
    output logic [31:0] dbg_conv1_weight_load_cycles_o,
    output logic [31:0] dbg_conv1_activation_fetch_cycles_o,
    output logic [31:0] dbg_conv1_mxu_active_cycles_o,
    output logic [31:0] dbg_conv1_mxu_drain_cycles_o,
    output logic [31:0] dbg_conv1_accumulator_cycles_o,
    output logic [31:0] dbg_conv1_vpu_cycles_o,
    output logic [31:0] dbg_conv1_output_write_cycles_o,
    output logic [31:0] dbg_conv1_controller_idle_cycles_o,
    output logic [31:0] dbg_conv1_valid_mac_count_o,
    output logic [31:0] dbg_conv1_issued_mac_count_o,
    output logic [31:0] dbg_conv1_useful_mac_count_o,
    output logic [31:0] dbg_conv1_exclusive_state_cycles_o,
    output logic [31:0] dbg_conv2_weight_load_cycles_o,
    output logic [31:0] dbg_conv2_activation_fetch_cycles_o,
    output logic [31:0] dbg_conv2_mxu_active_cycles_o,
    output logic [31:0] dbg_conv2_mxu_drain_cycles_o,
    output logic [31:0] dbg_conv2_accumulator_cycles_o,
    output logic [31:0] dbg_conv2_vpu_cycles_o,
    output logic [31:0] dbg_conv2_output_write_cycles_o,
    output logic [31:0] dbg_conv2_controller_idle_cycles_o,
    output logic [31:0] dbg_conv2_valid_mac_count_o,
    output logic [31:0] dbg_conv2_issued_mac_count_o,
    output logic [31:0] dbg_conv2_useful_mac_count_o,
    output logic [31:0] dbg_conv2_exclusive_state_cycles_o,
    output logic [31:0] dbg_fc1_weight_load_cycles_o,
    output logic [31:0] dbg_fc1_activation_fetch_cycles_o,
    output logic [31:0] dbg_fc1_mxu_active_cycles_o,
    output logic [31:0] dbg_fc1_mxu_drain_cycles_o,
    output logic [31:0] dbg_fc1_accumulator_cycles_o,
    output logic [31:0] dbg_fc1_vpu_cycles_o,
    output logic [31:0] dbg_fc1_output_write_cycles_o,
    output logic [31:0] dbg_fc1_controller_idle_cycles_o,
    output logic [31:0] dbg_fc1_valid_mac_count_o,
    output logic [31:0] dbg_fc1_issued_mac_count_o,
    output logic [31:0] dbg_fc1_useful_mac_count_o,
    output logic [31:0] dbg_fc1_exclusive_state_cycles_o,
    output logic [31:0] dbg_error_code_o,

    input  logic                         host_rd_en_i,
    input  logic                         host_rd_bank_i,
    input  logic [UB_ADDR_WIDTH-1:0]     host_rd_addr_i,
    output logic signed [DATA_WIDTH-1:0] host_rd_data_o,
    output logic                         host_rd_valid_o,

    input logic                         host_wr_en_i,
    input logic                         host_wr_bank_i,
    input logic [UB_ADDR_WIDTH-1:0]     host_wr_addr_i,
    input logic signed [DATA_WIDTH-1:0] host_wr_data_i,

    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o,

    output logic [4:0]  dbg_layer_state_o,
    output logic [4:0]  dbg_layer_tile_state_o,
    output logic [15:0] dbg_layer_spatial_o,
    output logic [15:0] dbg_layer_oc_tile_o,
    output logic [15:0] dbg_layer_k_tile_o,
    output logic [3:0]  dbg_pool_state_o,
    output logic [15:0] dbg_pool_channel_o,
    output logic [15:0] dbg_pool_row_o,
    output logic [15:0] dbg_pool_col_o
);

  typedef enum logic [4:0] {
    S_IDLE,
    S_START_CONV1,
    S_RUN_CONV1,
    S_START_POOL1,
    S_RUN_POOL1,
    S_START_CONV2,
    S_RUN_CONV2,
    S_START_POOL2,
    S_RUN_POOL2,
    S_START_FC1,
    S_RUN_FC1,
    S_START_FC2,
    S_RUN_FC2,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [2:0] STAGE_IDLE  = 3'd0;
  localparam logic [2:0] STAGE_CONV1 = 3'd1;
  localparam logic [2:0] STAGE_POOL1 = 3'd2;
  localparam logic [2:0] STAGE_CONV2 = 3'd3;
  localparam logic [2:0] STAGE_POOL2 = 3'd4;
  localparam logic [2:0] STAGE_FC1   = 3'd5;
  localparam logic [2:0] STAGE_FC2   = 3'd6;

  localparam logic [4:0] TILE_S_IDLE              = 5'd0;
  localparam logic [4:0] TILE_S_CLEAR_ACC         = 5'd1;
  localparam logic [4:0] TILE_S_SEND_WGT_REQ      = 5'd2;
  localparam logic [4:0] TILE_S_WAIT_WGT_TILE     = 5'd3;
  localparam logic [4:0] TILE_S_STREAM_WGT        = 5'd4;
  localparam logic [4:0] TILE_S_WAIT_WGT_LOAD     = 5'd5;
  localparam logic [4:0] TILE_S_PREFETCH_WGT_REQ  = 5'd6;
  localparam logic [4:0] TILE_S_SEND_ACT_REQ      = 5'd7;
  localparam logic [4:0] TILE_S_WAIT_ACT_READY    = 5'd8;
  localparam logic [4:0] TILE_S_LAUNCH_ACT        = 5'd9;
  localparam logic [4:0] TILE_S_WAIT_PSUM         = 5'd10;
  localparam logic [4:0] TILE_S_RELEASE_WGT       = 5'd11;
  localparam logic [4:0] TILE_S_NEXT_K_TILE       = 5'd12;
  localparam logic [4:0] TILE_S_RELEASE_FINAL_WGT = 5'd13;
  localparam logic [4:0] TILE_S_WAIT_ACC_READY    = 5'd14;
  localparam logic [4:0] TILE_S_READ_ACC          = 5'd15;
  localparam logic [4:0] TILE_S_WAIT_ACC_READ     = 5'd16;
  localparam logic [4:0] TILE_S_WAIT_VPU          = 5'd17;
  localparam logic [4:0] TILE_S_DONE              = 5'd18;
  localparam logic [4:0] TILE_S_ERROR             = 5'd19;

  localparam logic [31:0] ERR_LAYER = 32'h0005_1000;
  localparam logic [31:0] ERR_POOL  = 32'h0005_2000;

  localparam int POOL_BYPASS = 0;

  state_t state_q;

  logic host_access_w;
  logic layer_active_w;
  logic pool_active_w;

  logic layer_start_q;
  logic layer_done_w;
  logic layer_busy_w;
  logic layer_error_w;
  logic [31:0] layer_error_code_w;
  logic [1:0] layer_idx_w;

  logic pool_start_q;
  logic pool_done_w;
  logic pool_busy_w;
  logic pool_error_w;
  logic [31:0] pool_error_code_w;
  logic pool_read_bank_w;
  logic pool_write_bank_w;
  logic [15:0] pool_in_h_w;
  logic [15:0] pool_in_w_w;
  logic [15:0] pool_channels_w;
  logic [15:0] pool_out_h_w;
  logic [15:0] pool_out_w_w;

  logic ub_rd_en_w;
  logic ub_rd_bank_w;
  logic [UB_ADDR_WIDTH-1:0] ub_rd_addr_w;
  logic signed [DATA_WIDTH-1:0] ub_rd_data_w;
  logic ub_rd_valid_w;
  logic ub_wr_en_w;
  logic ub_wr_bank_w;
  logic [UB_ADDR_WIDTH-1:0] ub_wr_addr_w;
  logic signed [DATA_WIDTH-1:0] ub_wr_data_w;

  logic layer_ub_rd_bank_w;
  logic layer_ub_wr_en_w;
  logic layer_ub_wr_bank_w;
  logic [UB_ADDR_WIDTH-1:0] layer_ub_wr_addr_w;
  logic signed [DATA_WIDTH-1:0] layer_ub_wr_data_w;
  logic layer_clear_w;
  logic datapath_clear_w;

  logic pool_ub_rd_en_w;
  logic pool_ub_rd_bank_w;
  logic [UB_ADDR_WIDTH-1:0] pool_ub_rd_addr_w;
  logic pool_ub_wr_en_w;
  logic pool_ub_wr_bank_w;
  logic [UB_ADDR_WIDTH-1:0] pool_ub_wr_addr_w;
  logic signed [DATA_WIDTH-1:0] pool_ub_wr_data_w;

  logic [TILE_COUNT_WIDTH-1:0] num_tiles_w;

  logic wgt_req_valid_w;
  logic wgt_req_ready_w;
  logic [SIZE*SIZE*UB_ADDR_WIDTH-1:0] wgt_req_addr_flatten_w;
  logic [SIZE*SIZE-1:0] wgt_req_valid_mask_w;
  logic [SIZE*SIZE-1:0] wgt_req_zero_mask_w;
  logic [15:0] wgt_req_tag_w;
  logic wgt_tile_release_w;
  logic wgt_stream_start_w;
  logic wgt_tile_valid_w;
  logic wgt_stream_ready_w;
  logic wgt_stream_done_w;
  logic [15:0] wgt_tile_tag_w;
  logic [SIZE-1:0] wgt_load_done_w;

  logic act_req_valid_w;
  logic act_req_ready_w;
  logic [SIZE*UB_ADDR_WIDTH-1:0] act_req_addr_flatten_w;
  logic [SIZE-1:0] act_req_lane_valid_w;
  logic [SIZE-1:0] act_req_lane_zero_w;
  logic [15:0] act_req_tag_w;
  logic act_launch_ready_w;
  logic act_launch_w;

  logic datapath_ub_rd_en_w;
  logic [UB_ADDR_WIDTH-1:0] datapath_ub_rd_addr_w;
  logic signed [DATA_WIDTH-1:0] datapath_ub_rd_data_w;
  logic datapath_ub_rd_valid_w;

  logic weight_rd_en_w;
  logic [UB_ADDR_WIDTH-1:0] weight_rd_addr_w;
  logic signed [DATA_WIDTH-1:0] weight_rd_data_w;
  logic weight_rd_valid_w;

  logic accumulator_clear_all_w;
  logic accumulator_row_clear_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_w;
  logic accumulator_write_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_w;
  logic accumulator_read_en_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_w;
  logic signed [(ACC_WIDTH*SIZE)-1:0] accumulator_read_flatten_w;
  logic accumulator_read_valid_w;
  logic accumulator_row_done_w;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_done_addr_w;
  logic [ACC_DEPTH-1:0] accumulator_row_ready_w;

  logic vpu_input_done_w;
  logic [1:0] vpu_act_mode_w;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] vpu_bias_flatten_w;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_w;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] vpu_requant_shift_flatten_w;
  logic signed [ACC_WIDTH-1:0] vpu_output_zero_point_w;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_flatten_w;
  logic vpu_data_valid_w;
  logic datapath_done_w;

  logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] mxu_psum_flatten_w;
  logic [SIZE-1:0] mxu_psum_valid_w;
  logic [MAC_COUNT_WIDTH-1:0] mxu_valid_mac_count_w;
  logic [31:0] mxu_valid_mac_count_ext_w;
  logic psum_packer_busy_w;

  logic profile_layer_active_w;
  logic profile_weight_load_w;
  logic profile_activation_fetch_w;
  logic profile_mxu_active_w;
  logic profile_mxu_drain_w;
  logic profile_accumulator_w;
  logic profile_vpu_w;
  logic profile_output_write_w;
  logic profile_controller_idle_w;

  function automatic logic [2:0] stage_from_state(input state_t state_i);
    begin
      unique case (state_i)
        S_START_CONV1, S_RUN_CONV1: stage_from_state = STAGE_CONV1;
        S_START_POOL1, S_RUN_POOL1: stage_from_state = STAGE_POOL1;
        S_START_CONV2, S_RUN_CONV2: stage_from_state = STAGE_CONV2;
        S_START_POOL2, S_RUN_POOL2: stage_from_state = STAGE_POOL2;
        S_START_FC1, S_RUN_FC1: stage_from_state = STAGE_FC1;
        S_START_FC2, S_RUN_FC2: stage_from_state = STAGE_FC2;
        default: stage_from_state = STAGE_IDLE;
      endcase
    end
  endfunction

  assign done_o = (state_q == S_DONE);
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign error_o = (state_q == S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_stage_o = stage_from_state(state_q);
  assign host_access_w = (state_q == S_IDLE) || (state_q == S_DONE) || (state_q == S_ERROR);
  assign layer_active_w = (state_q == S_START_CONV1) || (state_q == S_RUN_CONV1)
                       || (state_q == S_START_CONV2) || (state_q == S_RUN_CONV2)
                       || (state_q == S_START_FC1) || (state_q == S_RUN_FC1)
                       || (state_q == S_START_FC2) || (state_q == S_RUN_FC2);
  assign pool_active_w = (state_q == S_START_POOL1) || (state_q == S_RUN_POOL1)
                      || (state_q == S_START_POOL2) || (state_q == S_RUN_POOL2);
  assign mxu_valid_mac_count_ext_w = 32'(mxu_valid_mac_count_w);
  assign profile_layer_active_w = (stage_from_state(state_q) == STAGE_CONV1)
                               || (stage_from_state(state_q) == STAGE_CONV2)
                               || (stage_from_state(state_q) == STAGE_FC1);
  assign profile_weight_load_w = (dbg_layer_tile_state_o == TILE_S_SEND_WGT_REQ)
                              || (dbg_layer_tile_state_o == TILE_S_WAIT_WGT_TILE)
                              || (dbg_layer_tile_state_o == TILE_S_STREAM_WGT)
                              || (dbg_layer_tile_state_o == TILE_S_WAIT_WGT_LOAD)
                              || (dbg_layer_tile_state_o == TILE_S_PREFETCH_WGT_REQ);
  assign profile_activation_fetch_w = (dbg_layer_tile_state_o == TILE_S_SEND_ACT_REQ)
                                   || (dbg_layer_tile_state_o == TILE_S_WAIT_ACT_READY);
  assign profile_mxu_active_w = (mxu_valid_mac_count_w != '0);
  assign profile_mxu_drain_w = (dbg_layer_tile_state_o == TILE_S_WAIT_PSUM)
                             || (dbg_layer_tile_state_o == TILE_S_RELEASE_WGT)
                             || (dbg_layer_tile_state_o == TILE_S_NEXT_K_TILE)
                             || (dbg_layer_tile_state_o == TILE_S_RELEASE_FINAL_WGT);
  assign profile_accumulator_w = (dbg_layer_tile_state_o == TILE_S_WAIT_ACC_READY)
                              || (dbg_layer_tile_state_o == TILE_S_READ_ACC)
                              || (dbg_layer_tile_state_o == TILE_S_WAIT_ACC_READ);
  assign profile_vpu_w = (dbg_layer_tile_state_o == TILE_S_WAIT_VPU);
  assign profile_output_write_w = layer_ub_wr_en_w;
  assign profile_controller_idle_w = profile_layer_active_w
                                  && !profile_weight_load_w
                                  && !profile_activation_fetch_w
                                  && !profile_mxu_drain_w
                                  && !profile_accumulator_w
                                  && !profile_vpu_w
                                  && !profile_output_write_w;

  always_comb begin
    layer_idx_w = LAYER_IDX_CONV1;
    unique case (state_q)
      S_START_CONV2, S_RUN_CONV2: layer_idx_w = LAYER_IDX_CONV2;
      S_START_FC1, S_RUN_FC1: layer_idx_w = LAYER_IDX_FC1;
      S_START_FC2, S_RUN_FC2: layer_idx_w = LAYER_IDX_FC2;
      default: layer_idx_w = LAYER_IDX_CONV1;
    endcase
  end

  always_comb begin
    pool_read_bank_w  = 1'b1;
    pool_write_bank_w = 1'b0;
    pool_in_h_w       = CONV1_OUT_H;
    pool_in_w_w       = CONV1_OUT_W;
    pool_channels_w   = CONV1_OUT_CH;
    pool_out_h_w      = CONV2_IN_H;
    pool_out_w_w      = CONV2_IN_W;

    if ((state_q == S_START_POOL2) || (state_q == S_RUN_POOL2)) begin
      pool_in_h_w     = CONV2_OUT_H;
      pool_in_w_w     = CONV2_OUT_W;
      pool_channels_w = CONV2_OUT_CH;
      pool_out_h_w    = 16'd5;
      pool_out_w_w    = 16'd5;
    end
  end

  always_comb begin
    if (host_access_w) begin
      ub_rd_en_w   = host_rd_en_i;
      ub_rd_bank_w = host_rd_bank_i;
      ub_rd_addr_w = host_rd_addr_i;
      ub_wr_en_w   = host_wr_en_i;
      ub_wr_bank_w = host_wr_bank_i;
      ub_wr_addr_w = host_wr_addr_i;
      ub_wr_data_w = host_wr_data_i;
    end else if (pool_active_w) begin
      ub_rd_en_w   = pool_ub_rd_en_w;
      ub_rd_bank_w = pool_ub_rd_bank_w;
      ub_rd_addr_w = pool_ub_rd_addr_w;
      ub_wr_en_w   = pool_ub_wr_en_w;
      ub_wr_bank_w = pool_ub_wr_bank_w;
      ub_wr_addr_w = pool_ub_wr_addr_w;
      ub_wr_data_w = pool_ub_wr_data_w;
    end else if (layer_active_w) begin
      ub_rd_en_w   = datapath_ub_rd_en_w;
      ub_rd_bank_w = layer_ub_rd_bank_w;
      ub_rd_addr_w = datapath_ub_rd_addr_w;
      ub_wr_en_w   = layer_ub_wr_en_w;
      ub_wr_bank_w = layer_ub_wr_bank_w;
      ub_wr_addr_w = layer_ub_wr_addr_w;
      ub_wr_data_w = layer_ub_wr_data_w;
    end else begin
      ub_rd_en_w   = 1'b0;
      ub_rd_bank_w = 1'b0;
      ub_rd_addr_w = '0;
      ub_wr_en_w   = 1'b0;
      ub_wr_bank_w = 1'b0;
      ub_wr_addr_w = '0;
      ub_wr_data_w = '0;
    end
  end

  assign host_rd_data_o = ub_rd_data_w;
  assign host_rd_valid_o = host_access_w && ub_rd_valid_w;
  assign datapath_ub_rd_data_w = ub_rd_data_w;
  assign datapath_ub_rd_valid_w = ub_rd_valid_w && layer_active_w;
  assign layer_clear_w = 1'b0;
  assign datapath_clear_w = (state_q == S_START_CONV1)
                         || (state_q == S_START_CONV2)
                         || (state_q == S_START_FC1)
                         || (state_q == S_START_FC2);

  unified_buffer #(
      .DATA_WIDTH(DATA_WIDTH),
      .BANK_DEPTH(BANK_DEPTH),
      .ADDR_WIDTH(UB_ADDR_WIDTH)
  ) u_unified_buffer (
      .clk       (clk),
      .rst_n     (rst_n),
      .rd_en_i   (ub_rd_en_w),
      .rd_bank_i (ub_rd_bank_w),
      .rd_addr_i (ub_rd_addr_w),
      .rd_data_o (ub_rd_data_w),
      .rd_valid_o(ub_rd_valid_w),
      .wr_en_i   (ub_wr_en_w),
      .wr_bank_i (ub_wr_bank_w),
      .wr_addr_i (ub_wr_addr_w),
      .wr_data_i (ub_wr_data_w)
  );

  tpu_controller_v3_rom_layer #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH),
      .WGT_ADDR_WIDTH     (UB_ADDR_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .BANK_DEPTH         (BANK_DEPTH),
      .BIAS_INIT_FILE     (BIAS_INIT_FILE),
      .REQUANT_MULT_INIT_FILE(REQUANT_MULT_INIT_FILE),
      .REQUANT_SHIFT_INIT_FILE(REQUANT_SHIFT_INIT_FILE)
  ) u_layer_controller (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .start_i                          (layer_start_q),
      .clear_i                          (layer_clear_w),
      .done_o                           (layer_done_w),
      .busy_o                           (layer_busy_w),
      .error_o                          (layer_error_w),
      .dbg_state_o                      (dbg_layer_state_o),
      .dbg_tile_state_o                 (dbg_layer_tile_state_o),
      .dbg_spatial_idx_o                (dbg_layer_spatial_o),
      .dbg_oc_tile_o                    (dbg_layer_oc_tile_o),
      .dbg_k_tile_o                     (dbg_layer_k_tile_o),
      .dbg_cycle_count_o                (),
      .dbg_tile_count_o                 (),
      .dbg_error_code_o                 (layer_error_code_w),
      .layer_idx_i                      (layer_idx_w),
      .use_descriptor_banks_i           (1'b1),
      .read_bank_i                      (1'b0),
      .write_bank_i                     (1'b1),
      .activation_base_addr_i           ('0),
      .output_base_addr_i               ('0),
      .spatial_idx_i                    (16'd0),
      .single_spatial_i                 (1'b0),
      .ub_rd_bank_o                     (layer_ub_rd_bank_w),
      .ub_wr_en_o                       (layer_ub_wr_en_w),
      .ub_wr_bank_o                     (layer_ub_wr_bank_w),
      .ub_wr_addr_o                     (layer_ub_wr_addr_w),
      .ub_wr_data_o                     (layer_ub_wr_data_w),
      .wgt_req_valid_o                  (wgt_req_valid_w),
      .wgt_req_ready_i                  (wgt_req_ready_w),
      .wgt_req_addr_flatten_o           (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_o             (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_o              (wgt_req_zero_mask_w),
      .wgt_req_tag_o                    (wgt_req_tag_w),
      .wgt_tile_release_o               (wgt_tile_release_w),
      .wgt_stream_start_o               (wgt_stream_start_w),
      .wgt_tile_valid_i                 (wgt_tile_valid_w),
      .wgt_load_done_i                  (wgt_load_done_w),
      .act_req_valid_o                  (act_req_valid_w),
      .act_req_ready_i                  (act_req_ready_w),
      .act_req_addr_flatten_o           (act_req_addr_flatten_w),
      .act_req_lane_valid_o             (act_req_lane_valid_w),
      .act_req_lane_zero_o              (act_req_lane_zero_w),
      .act_req_tag_o                    (act_req_tag_w),
      .act_launch_ready_i               (act_launch_ready_w),
      .act_launch_o                     (act_launch_w),
      .accumulator_clear_all_o          (accumulator_clear_all_w),
      .accumulator_row_clear_o          (accumulator_row_clear_w),
      .accumulator_row_clear_addr_o     (accumulator_row_clear_addr_w),
      .accumulator_write_en_o           (accumulator_write_en_w),
      .accumulator_write_addr_o         (accumulator_write_addr_w),
      .accumulator_read_en_o            (accumulator_read_en_w),
      .accumulator_read_addr_o          (accumulator_read_addr_w),
      .accumulator_read_valid_i         (accumulator_read_valid_w),
      .accumulator_row_ready_i          (accumulator_row_ready_w),
      .vpu_input_done_o                 (vpu_input_done_w),
      .vpu_act_mode_o                   (vpu_act_mode_w),
      .vpu_bias_flatten_o               (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_o (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_o      (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_o          (vpu_output_zero_point_w),
      .vpu_data_flatten_i               (vpu_data_flatten_w),
      .vpu_data_valid_i                 (vpu_data_valid_w),
      .mxu_psum_valid_i                 (mxu_psum_valid_w),
      .psum_packer_busy_i               (psum_packer_busy_w),
      .num_tiles_o                      (num_tiles_w)
  );

  weight_rom #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH     (4952),
      .ADDR_WIDTH(UB_ADDR_WIDTH),
      .INIT_FILE (WGT_INIT_FILE)
  ) u_weight_rom (
      .clk    (clk),
      .rst_n  (rst_n),
      .en_i   (weight_rd_en_w),
      .addr_i (weight_rd_addr_w),
      .data_o (weight_rd_data_w),
      .valid_o(weight_rd_valid_w)
  );

  tpu_datapath_v3 #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .ACT_ADDR_WIDTH     (UB_ADDR_WIDTH),
      .WGT_ADDR_WIDTH     (UB_ADDR_WIDTH),
      .LOCAL_PSUM_WIDTH   (LOCAL_PSUM_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .ACC_WIDTH          (ACC_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .ACT_WIDTH          (ACC_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .QUANT_ENABLE       (1'b1),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .NORM_SHIFT         (0),
      .NORM_ROUND_ENABLE  (1'b1),
      .POOL_MODE          (POOL_BYPASS),
      .POOL_WINDOW        (2),
      .GATED_ACT_LAUNCH   (1'b1),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .MAC_COUNT_WIDTH    (MAC_COUNT_WIDTH)
  ) u_datapath (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .clear_i                          (datapath_clear_w),
      .compute_enable_i                 (1'b1),
      .num_tiles_i                      (num_tiles_w),
      .act_req_valid_i                  (act_req_valid_w),
      .act_req_ready_o                  (act_req_ready_w),
      .act_req_addr_flatten_i           (act_req_addr_flatten_w),
      .act_req_lane_valid_i             (act_req_lane_valid_w),
      .act_req_lane_zero_i              (act_req_lane_zero_w),
      .act_req_tag_i                    (act_req_tag_w),
      .act_launch_i                     (act_launch_w),
      .act_launch_ready_o               (act_launch_ready_w),
      .ub_rd_en_o                       (datapath_ub_rd_en_w),
      .ub_rd_addr_o                     (datapath_ub_rd_addr_w),
      .ub_rd_data_i                     (datapath_ub_rd_data_w),
      .ub_rd_valid_i                    (datapath_ub_rd_valid_w),
      .wgt_req_valid_i                  (wgt_req_valid_w),
      .wgt_req_ready_o                  (wgt_req_ready_w),
      .wgt_req_addr_flatten_i           (wgt_req_addr_flatten_w),
      .wgt_req_valid_mask_i             (wgt_req_valid_mask_w),
      .wgt_req_zero_mask_i              (wgt_req_zero_mask_w),
      .wgt_req_tag_i                    (wgt_req_tag_w),
      .wgt_tile_release_i               (wgt_tile_release_w),
      .wgt_stream_start_i               (wgt_stream_start_w),
      .wgt_stream_ready_o               (wgt_stream_ready_w),
      .wgt_tile_valid_o                 (wgt_tile_valid_w),
      .wgt_tile_tag_o                   (wgt_tile_tag_w),
      .wgt_stream_done_o                (wgt_stream_done_w),
      .weight_rd_en_o                   (weight_rd_en_w),
      .weight_rd_addr_o                 (weight_rd_addr_w),
      .weight_rd_data_i                 (weight_rd_data_w),
      .weight_rd_valid_i                (weight_rd_valid_w),
      .accumulator_clear_all_i          (accumulator_clear_all_w),
      .accumulator_row_clear_i          (accumulator_row_clear_w),
      .accumulator_row_clear_addr_i     (accumulator_row_clear_addr_w),
      .accumulator_write_en_i           (accumulator_write_en_w),
      .accumulator_write_addr_i         (accumulator_write_addr_w),
      .accumulator_read_en_i            (accumulator_read_en_w),
      .accumulator_read_addr_i          (accumulator_read_addr_w),
      .vpu_input_done_i                 (vpu_input_done_w),
      .vpu_act_mode_i                   (vpu_act_mode_w),
      .vpu_bias_flatten_i               (vpu_bias_flatten_w),
      .vpu_requant_multiplier_flatten_i (vpu_requant_multiplier_flatten_w),
      .vpu_requant_shift_flatten_i      (vpu_requant_shift_flatten_w),
      .vpu_output_zero_point_i          (vpu_output_zero_point_w),
      .mxu_psum_flatten_o               (mxu_psum_flatten_w),
      .mxu_psum_valid_o                 (mxu_psum_valid_w),
      .mxu_valid_mac_count_o            (mxu_valid_mac_count_w),
      .psum_packer_busy_o               (psum_packer_busy_w),
      .wgt_load_done_o                  (wgt_load_done_w),
      .accumulator_read_flatten_o       (accumulator_read_flatten_w),
      .accumulator_read_valid_o         (accumulator_read_valid_w),
      .accumulator_row_done_o           (accumulator_row_done_w),
      .accumulator_row_done_addr_o      (accumulator_row_done_addr_w),
      .accumulator_row_ready_o          (accumulator_row_ready_w),
      .vpu_data_flatten_o               (vpu_data_flatten_w),
      .vpu_data_valid_o                 (vpu_data_valid_w),
      .done_o                           (datapath_done_w),
      .overflow_clr_i                   (overflow_clr_i),
      .overflow_flatten_o               (overflow_flatten_o),
      .dbg_act_fetch_cycles_o           (),
      .dbg_act_output_stall_cycles_o    (),
      .dbg_act_vectors_pushed_o         (),
      .dbg_act_lane_reads_o             (),
      .dbg_weight_load_cycles_o         (),
      .dbg_weight_reuse_count_o         (),
      .dbg_weight_buffer_empty_cycles_o (),
      .dbg_weight_buffer_full_cycles_o  ()
  );

  maxpool2d_unit #(
      .DATA_WIDTH(DATA_WIDTH),
      .BANK_DEPTH(BANK_DEPTH),
      .ADDR_WIDTH(UB_ADDR_WIDTH),
      .DIM_WIDTH (16)
  ) u_maxpool2d_unit (
      .clk               (clk),
      .rst_n             (rst_n),
      .start_i           (pool_start_q),
      .done_o            (pool_done_w),
      .busy_o            (pool_busy_w),
      .error_o           (pool_error_w),
      .dbg_state_o       (dbg_pool_state_o),
      .dbg_channel_o     (dbg_pool_channel_o),
      .dbg_out_row_o     (dbg_pool_row_o),
      .dbg_out_col_o     (dbg_pool_col_o),
      .dbg_error_code_o  (pool_error_code_w),
      .read_bank_i       (pool_read_bank_w),
      .write_bank_i      (pool_write_bank_w),
      .input_base_addr_i ('0),
      .output_base_addr_i('0),
      .in_h_i            (pool_in_h_w),
      .in_w_i            (pool_in_w_w),
      .channels_i        (pool_channels_w),
      .out_h_i           (pool_out_h_w),
      .out_w_i           (pool_out_w_w),
      .ub_rd_en_o        (pool_ub_rd_en_w),
      .ub_rd_bank_o      (pool_ub_rd_bank_w),
      .ub_rd_addr_o      (pool_ub_rd_addr_w),
      .ub_rd_data_i      (ub_rd_data_w),
      .ub_rd_valid_i     (ub_rd_valid_w),
      .ub_wr_en_o        (pool_ub_wr_en_w),
      .ub_wr_bank_o      (pool_ub_wr_bank_w),
      .ub_wr_addr_o      (pool_ub_wr_addr_w),
      .ub_wr_data_o      (pool_ub_wr_data_w)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      layer_start_q <= 1'b0;
      pool_start_q <= 1'b0;
      dbg_cycle_count_o <= '0;
      dbg_conv1_cycle_count_o <= '0;
      dbg_pool1_cycle_count_o <= '0;
      dbg_conv2_cycle_count_o <= '0;
      dbg_pool2_cycle_count_o <= '0;
      dbg_fc1_cycle_count_o <= '0;
      dbg_fc2_cycle_count_o <= '0;
      dbg_conv1_weight_load_cycles_o <= '0;
      dbg_conv1_activation_fetch_cycles_o <= '0;
      dbg_conv1_mxu_active_cycles_o <= '0;
      dbg_conv1_mxu_drain_cycles_o <= '0;
      dbg_conv1_accumulator_cycles_o <= '0;
      dbg_conv1_vpu_cycles_o <= '0;
      dbg_conv1_output_write_cycles_o <= '0;
      dbg_conv1_controller_idle_cycles_o <= '0;
      dbg_conv1_valid_mac_count_o <= '0;
      dbg_conv1_issued_mac_count_o <= '0;
      dbg_conv1_useful_mac_count_o <= '0;
      dbg_conv1_exclusive_state_cycles_o <= '0;
      dbg_conv2_weight_load_cycles_o <= '0;
      dbg_conv2_activation_fetch_cycles_o <= '0;
      dbg_conv2_mxu_active_cycles_o <= '0;
      dbg_conv2_mxu_drain_cycles_o <= '0;
      dbg_conv2_accumulator_cycles_o <= '0;
      dbg_conv2_vpu_cycles_o <= '0;
      dbg_conv2_output_write_cycles_o <= '0;
      dbg_conv2_controller_idle_cycles_o <= '0;
      dbg_conv2_valid_mac_count_o <= '0;
      dbg_conv2_issued_mac_count_o <= '0;
      dbg_conv2_useful_mac_count_o <= '0;
      dbg_conv2_exclusive_state_cycles_o <= '0;
      dbg_fc1_weight_load_cycles_o <= '0;
      dbg_fc1_activation_fetch_cycles_o <= '0;
      dbg_fc1_mxu_active_cycles_o <= '0;
      dbg_fc1_mxu_drain_cycles_o <= '0;
      dbg_fc1_accumulator_cycles_o <= '0;
      dbg_fc1_vpu_cycles_o <= '0;
      dbg_fc1_output_write_cycles_o <= '0;
      dbg_fc1_controller_idle_cycles_o <= '0;
      dbg_fc1_valid_mac_count_o <= '0;
      dbg_fc1_issued_mac_count_o <= '0;
      dbg_fc1_useful_mac_count_o <= '0;
      dbg_fc1_exclusive_state_cycles_o <= '0;
      dbg_error_code_o <= '0;
    end else begin
      layer_start_q <= 1'b0;
      pool_start_q <= 1'b0;

      if (busy_o) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
        unique case (stage_from_state(state_q))
          STAGE_CONV1: dbg_conv1_cycle_count_o <= dbg_conv1_cycle_count_o + 32'd1;
          STAGE_POOL1: dbg_pool1_cycle_count_o <= dbg_pool1_cycle_count_o + 32'd1;
          STAGE_CONV2: dbg_conv2_cycle_count_o <= dbg_conv2_cycle_count_o + 32'd1;
          STAGE_POOL2: dbg_pool2_cycle_count_o <= dbg_pool2_cycle_count_o + 32'd1;
          STAGE_FC1:   dbg_fc1_cycle_count_o   <= dbg_fc1_cycle_count_o   + 32'd1;
          STAGE_FC2:   dbg_fc2_cycle_count_o   <= dbg_fc2_cycle_count_o   + 32'd1;
          default: begin
          end
        endcase

        if (profile_layer_active_w) begin
          unique case (stage_from_state(state_q))
            STAGE_CONV1: begin
              dbg_conv1_exclusive_state_cycles_o <= dbg_conv1_exclusive_state_cycles_o + 32'd1;
              if (profile_weight_load_w) begin
                dbg_conv1_weight_load_cycles_o <= dbg_conv1_weight_load_cycles_o + 32'd1;
              end
              if (profile_activation_fetch_w) begin
                dbg_conv1_activation_fetch_cycles_o <= dbg_conv1_activation_fetch_cycles_o + 32'd1;
              end
              if (profile_mxu_active_w) begin
                dbg_conv1_mxu_active_cycles_o <= dbg_conv1_mxu_active_cycles_o + 32'd1;
                dbg_conv1_valid_mac_count_o <= dbg_conv1_valid_mac_count_o + mxu_valid_mac_count_ext_w;
                dbg_conv1_issued_mac_count_o <= dbg_conv1_issued_mac_count_o + mxu_valid_mac_count_ext_w;
              end
              if (profile_mxu_drain_w) begin
                dbg_conv1_mxu_drain_cycles_o <= dbg_conv1_mxu_drain_cycles_o + 32'd1;
              end
              if (profile_accumulator_w) begin
                dbg_conv1_accumulator_cycles_o <= dbg_conv1_accumulator_cycles_o + 32'd1;
              end
              if (profile_vpu_w) begin
                dbg_conv1_vpu_cycles_o <= dbg_conv1_vpu_cycles_o + 32'd1;
              end
              if (profile_output_write_w) begin
                dbg_conv1_output_write_cycles_o <= dbg_conv1_output_write_cycles_o + 32'd1;
              end
              if (profile_controller_idle_w) begin
                dbg_conv1_controller_idle_cycles_o <= dbg_conv1_controller_idle_cycles_o + 32'd1;
              end
            end

            STAGE_CONV2: begin
              dbg_conv2_exclusive_state_cycles_o <= dbg_conv2_exclusive_state_cycles_o + 32'd1;
              if (profile_weight_load_w) begin
                dbg_conv2_weight_load_cycles_o <= dbg_conv2_weight_load_cycles_o + 32'd1;
              end
              if (profile_activation_fetch_w) begin
                dbg_conv2_activation_fetch_cycles_o <= dbg_conv2_activation_fetch_cycles_o + 32'd1;
              end
              if (profile_mxu_active_w) begin
                dbg_conv2_mxu_active_cycles_o <= dbg_conv2_mxu_active_cycles_o + 32'd1;
                dbg_conv2_valid_mac_count_o <= dbg_conv2_valid_mac_count_o + mxu_valid_mac_count_ext_w;
                dbg_conv2_issued_mac_count_o <= dbg_conv2_issued_mac_count_o + mxu_valid_mac_count_ext_w;
              end
              if (profile_mxu_drain_w) begin
                dbg_conv2_mxu_drain_cycles_o <= dbg_conv2_mxu_drain_cycles_o + 32'd1;
              end
              if (profile_accumulator_w) begin
                dbg_conv2_accumulator_cycles_o <= dbg_conv2_accumulator_cycles_o + 32'd1;
              end
              if (profile_vpu_w) begin
                dbg_conv2_vpu_cycles_o <= dbg_conv2_vpu_cycles_o + 32'd1;
              end
              if (profile_output_write_w) begin
                dbg_conv2_output_write_cycles_o <= dbg_conv2_output_write_cycles_o + 32'd1;
              end
              if (profile_controller_idle_w) begin
                dbg_conv2_controller_idle_cycles_o <= dbg_conv2_controller_idle_cycles_o + 32'd1;
              end
            end

            STAGE_FC1: begin
              dbg_fc1_exclusive_state_cycles_o <= dbg_fc1_exclusive_state_cycles_o + 32'd1;
              if (profile_weight_load_w) begin
                dbg_fc1_weight_load_cycles_o <= dbg_fc1_weight_load_cycles_o + 32'd1;
              end
              if (profile_activation_fetch_w) begin
                dbg_fc1_activation_fetch_cycles_o <= dbg_fc1_activation_fetch_cycles_o + 32'd1;
              end
              if (profile_mxu_active_w) begin
                dbg_fc1_mxu_active_cycles_o <= dbg_fc1_mxu_active_cycles_o + 32'd1;
                dbg_fc1_valid_mac_count_o <= dbg_fc1_valid_mac_count_o + mxu_valid_mac_count_ext_w;
                dbg_fc1_issued_mac_count_o <= dbg_fc1_issued_mac_count_o + mxu_valid_mac_count_ext_w;
              end
              if (profile_mxu_drain_w) begin
                dbg_fc1_mxu_drain_cycles_o <= dbg_fc1_mxu_drain_cycles_o + 32'd1;
              end
              if (profile_accumulator_w) begin
                dbg_fc1_accumulator_cycles_o <= dbg_fc1_accumulator_cycles_o + 32'd1;
              end
              if (profile_vpu_w) begin
                dbg_fc1_vpu_cycles_o <= dbg_fc1_vpu_cycles_o + 32'd1;
              end
              if (profile_output_write_w) begin
                dbg_fc1_output_write_cycles_o <= dbg_fc1_output_write_cycles_o + 32'd1;
              end
              if (profile_controller_idle_w) begin
                dbg_fc1_controller_idle_cycles_o <= dbg_fc1_controller_idle_cycles_o + 32'd1;
              end
            end

            default: begin
            end
          endcase
        end
      end

      unique case (state_q)
        S_IDLE: begin
          dbg_error_code_o <= '0;
          if (start_i) begin
            dbg_cycle_count_o <= '0;
            dbg_conv1_cycle_count_o <= '0;
            dbg_pool1_cycle_count_o <= '0;
            dbg_conv2_cycle_count_o <= '0;
            dbg_pool2_cycle_count_o <= '0;
            dbg_fc1_cycle_count_o <= '0;
            dbg_fc2_cycle_count_o <= '0;
            dbg_conv1_weight_load_cycles_o <= '0;
            dbg_conv1_activation_fetch_cycles_o <= '0;
            dbg_conv1_mxu_active_cycles_o <= '0;
            dbg_conv1_mxu_drain_cycles_o <= '0;
            dbg_conv1_accumulator_cycles_o <= '0;
            dbg_conv1_vpu_cycles_o <= '0;
            dbg_conv1_output_write_cycles_o <= '0;
            dbg_conv1_controller_idle_cycles_o <= '0;
            dbg_conv1_valid_mac_count_o <= '0;
            dbg_conv1_issued_mac_count_o <= '0;
            dbg_conv1_useful_mac_count_o <= '0;
            dbg_conv1_exclusive_state_cycles_o <= '0;
            dbg_conv2_weight_load_cycles_o <= '0;
            dbg_conv2_activation_fetch_cycles_o <= '0;
            dbg_conv2_mxu_active_cycles_o <= '0;
            dbg_conv2_mxu_drain_cycles_o <= '0;
            dbg_conv2_accumulator_cycles_o <= '0;
            dbg_conv2_vpu_cycles_o <= '0;
            dbg_conv2_output_write_cycles_o <= '0;
            dbg_conv2_controller_idle_cycles_o <= '0;
            dbg_conv2_valid_mac_count_o <= '0;
            dbg_conv2_issued_mac_count_o <= '0;
            dbg_conv2_useful_mac_count_o <= '0;
            dbg_conv2_exclusive_state_cycles_o <= '0;
            dbg_fc1_weight_load_cycles_o <= '0;
            dbg_fc1_activation_fetch_cycles_o <= '0;
            dbg_fc1_mxu_active_cycles_o <= '0;
            dbg_fc1_mxu_drain_cycles_o <= '0;
            dbg_fc1_accumulator_cycles_o <= '0;
            dbg_fc1_vpu_cycles_o <= '0;
            dbg_fc1_output_write_cycles_o <= '0;
            dbg_fc1_controller_idle_cycles_o <= '0;
            dbg_fc1_valid_mac_count_o <= '0;
            dbg_fc1_issued_mac_count_o <= '0;
            dbg_fc1_useful_mac_count_o <= '0;
            dbg_fc1_exclusive_state_cycles_o <= '0;
            state_q <= S_START_CONV1;
          end
        end

        S_START_CONV1: begin
          layer_start_q <= 1'b1;
          state_q <= S_RUN_CONV1;
        end

        S_RUN_CONV1: begin
          if (layer_error_w) begin
            dbg_error_code_o <= ERR_LAYER | {24'd0, STAGE_CONV1, layer_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (layer_done_w) begin
            dbg_conv1_useful_mac_count_o <= dbg_conv1_valid_mac_count_o;
            state_q <= S_START_POOL1;
          end
        end

        S_START_POOL1: begin
          pool_start_q <= 1'b1;
          state_q <= S_RUN_POOL1;
        end

        S_RUN_POOL1: begin
          if (pool_error_w) begin
            dbg_error_code_o <= ERR_POOL | {24'd0, STAGE_POOL1, pool_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (pool_done_w) begin
            state_q <= S_START_CONV2;
          end
        end

        S_START_CONV2: begin
          layer_start_q <= 1'b1;
          state_q <= S_RUN_CONV2;
        end

        S_RUN_CONV2: begin
          if (layer_error_w) begin
            dbg_error_code_o <= ERR_LAYER | {24'd0, STAGE_CONV2, layer_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (layer_done_w) begin
            dbg_conv2_useful_mac_count_o <= dbg_conv2_valid_mac_count_o;
            state_q <= S_START_POOL2;
          end
        end

        S_START_POOL2: begin
          pool_start_q <= 1'b1;
          state_q <= S_RUN_POOL2;
        end

        S_RUN_POOL2: begin
          if (pool_error_w) begin
            dbg_error_code_o <= ERR_POOL | {24'd0, STAGE_POOL2, pool_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (pool_done_w) begin
            state_q <= S_START_FC1;
          end
        end

        S_START_FC1: begin
          layer_start_q <= 1'b1;
          state_q <= S_RUN_FC1;
        end

        S_RUN_FC1: begin
          if (layer_error_w) begin
            dbg_error_code_o <= ERR_LAYER | {24'd0, STAGE_FC1, layer_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (layer_done_w) begin
            dbg_fc1_useful_mac_count_o <= dbg_fc1_valid_mac_count_o;
            state_q <= S_START_FC2;
          end
        end

        S_START_FC2: begin
          layer_start_q <= 1'b1;
          state_q <= S_RUN_FC2;
        end

        S_RUN_FC2: begin
          if (layer_error_w) begin
            dbg_error_code_o <= ERR_LAYER | {24'd0, STAGE_FC2, layer_error_code_w[4:0]};
            state_q <= S_ERROR;
          end else if (layer_done_w) begin
            state_q <= S_DONE;
          end
        end

        S_DONE: begin
          if (!start_i) begin
            state_q <= S_IDLE;
          end
        end

        S_ERROR: begin
          state_q <= S_ERROR;
        end

        default: begin
          dbg_error_code_o <= 32'h0005_ffff;
          state_q <= S_ERROR;
        end
      endcase
    end
  end

endmodule : tpu_top

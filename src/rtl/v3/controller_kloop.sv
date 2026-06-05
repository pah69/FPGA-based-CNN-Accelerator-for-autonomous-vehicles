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
    parameter int LANE_COUNT_WIDTH    = (SIZE > 1) ? $clog2(SIZE + 1) : 1
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

    output logic                         ub_wr_en_o,
    output logic                         ub_wr_bank_o,
    output logic [UB_ADDR_WIDTH-1:0]     ub_wr_addr_o,
    output logic signed [DATA_WIDTH-1:0] ub_wr_data_o,

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

  state_t state_q;

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

  logic [ACC_ADDR_WIDTH:0] stream_idx_q;
  logic [ACC_ADDR_WIDTH:0] acc_read_idx_q;
  logic [15:0] weight_stream_row_q;
  logic [15:0] act_fetch_lane_q;
  logic [1:0] act_read_valid_pipe_q;
  logic [15:0] act_read_lane_pipe_q[0:1];
  logic [15:0] output_lane_q;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_q;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_q;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_q;
  logic [1:0] act_mode_q;

  logic [ACC_ADDR_WIDTH-1:0] tag_mem_q[0:TAG_DEPTH-1];
  logic [TAG_PTR_WIDTH-1:0] tag_wr_ptr_q;
  logic [TAG_PTR_WIDTH-1:0] tag_rd_ptr_q;
  logic [TAG_COUNT_WIDTH-1:0] tag_count_q;

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
  logic inner_read_bank_w;
  logic inner_write_bank_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_stream_row_data_w;
  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_w;
  logic [SIZE-1:0] param_valid_required_w;

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

  assign spatial_stream_idx_w = spatial_idx_q + 16'(stream_idx_q);

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
      .k_tile_idx_i          (k_tile_q),
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

  assign rom_en_w = (state_q == S_FETCH_ROM);
  assign num_tiles_o = num_tiles_q;
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_k_tile_o = k_tile_q;
  assign inner_read_bank_w = use_descriptor_banks_q ? desc_read_bank_w : read_bank_q;
  assign inner_write_bank_w = use_descriptor_banks_q ? desc_write_bank_w : write_bank_q;
  assign last_k_tile_w = ((TILE_COUNT_WIDTH'(k_tile_q) + TILE_COUNT_WIDTH'(1)) >= num_tiles_q);
  assign act_read_capture_w = ub_rd_valid_i && act_read_valid_pipe_q[1];

  assign output_spatial_w = ADDR_CALC_WIDTH'(spatial_idx_q) + ADDR_CALC_WIDTH'(acc_read_idx_q);
  assign act_lane_addr_w = (act_fetch_lane_q < 16'(SIZE)) ? act_addr_w[act_fetch_lane_q] : '0;
  assign output_lane_addr_w = output_addr_w[output_lane_q];

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
          weight_mux_w[(weight_stream_row_q * 16'(SIZE)) + 16'(col)];
    end
  end

  always_comb begin
    act_flatten_w = '0;
    for (int lane = 0; lane < SIZE; lane++) begin
      act_flatten_w[(lane*DATA_WIDTH)+:DATA_WIDTH] = act_lane_q[lane];
    end
  end

  assign first_psum_valid_w = 1'b0;
  assign tag_stream_active_w = 1'b0;
  assign tag_push_w      = 1'b0;
  assign tag_pop_w       = 1'b0;
  assign tag_overflow_w  = 1'b0;
  assign tag_underflow_w = 1'b0;
  assign tag_front_w     = (tag_count_q != '0) ? tag_mem_q[tag_rd_ptr_q] : '0;

  assign accumulator_write_en_o   = (state_q == S_LAUNCH_ACT);
  assign accumulator_write_addr_o = stream_idx_q[ACC_ADDR_WIDTH-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
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
      stream_idx_q <= '0;
      acc_read_idx_q <= '0;
      weight_stream_row_q <= '0;
      act_fetch_lane_q <= '0;
      act_read_valid_pipe_q <= '0;
      output_lane_q <= '0;
      wgt_load_seen_q <= '0;
      vpu_data_q <= '0;
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
      ub_wr_en_o <= 1'b0;
      ub_wr_bank_o <= 1'b0;
      ub_wr_addr_o <= '0;
      ub_wr_data_o <= '0;
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
      end

      for (int lane = 0; lane < SIZE; lane++) begin
        act_lane_q[lane] <= '0;
      end

      for (int idx = 0; idx < TAG_DEPTH; idx++) begin
        tag_mem_q[idx] <= '0;
      end
    end else begin
      done_o <= 1'b0;
      ub_rd_en_o <= 1'b0;
      ub_wr_en_o <= 1'b0;
      work_o <= 1'b0;
      start_wgt_load_o <= 1'b0;
      wgt_fifo_wr_en_o <= 1'b0;
      act_flat_raw_o <= '0;
      act_valid_raw_o <= '0;
      accumulator_clear_all_o <= 1'b0;
      accumulator_row_clear_o <= 1'b0;
      accumulator_read_en_o <= 1'b0;
      vpu_input_done_o <= 1'b0;
      vpu_act_mode_o <= act_mode_q;
      vpu_bias_flatten_o <= bias_flatten_q;
      vpu_requant_multiplier_flatten_o <= requant_multiplier_flatten_q;
      vpu_requant_shift_flatten_o <= requant_shift_flatten_q;
      vpu_output_zero_point_o <= '0;

      act_read_valid_pipe_q[1] <= act_read_valid_pipe_q[0];
      act_read_valid_pipe_q[0] <= 1'b0;
      act_read_lane_pipe_q[1] <= act_read_lane_pipe_q[0];
      act_read_lane_pipe_q[0] <= '0;

      if (act_read_capture_w) begin
        act_lane_q[act_read_lane_pipe_q[1]] <= ub_rd_data_i;
      end

      if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
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
              dbg_cycle_count_o <= '0;
              dbg_useful_mac_count_o <= '0;
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
                state_q <= S_START_WEIGHT_LOAD;
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
              act_read_lane_pipe_q[0] <= '0;
              act_read_lane_pipe_q[1] <= '0;
              state_q <= S_READ_ACT_REQ;
            end
          end

          S_READ_ACT_REQ: begin
            if (act_fetch_lane_q >= 16'(SIZE)) begin
              state_q <= S_READ_ACT_WAIT;
            end else begin
              if (act_zero_w[act_fetch_lane_q]) begin
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
              end

              if (act_zero_w[act_fetch_lane_q]
                  || (act_lane_addr_w < ADDR_CALC_WIDTH'(BANK_DEPTH))) begin
                if ((act_fetch_lane_q + 16'd1) >= 16'(SIZE)) begin
                  act_fetch_lane_q <= 16'(SIZE);
                  if (act_zero_w[act_fetch_lane_q]
                      && !act_read_valid_pipe_q[0]
                      && (!act_read_valid_pipe_q[1] || act_read_capture_w)) begin
                    state_q <= S_LAUNCH_ACT;
                  end else begin
                    state_q <= S_READ_ACT_WAIT;
                  end
                end else begin
                  act_fetch_lane_q <= act_fetch_lane_q + 16'd1;
                end
              end
            end
          end

          S_READ_ACT_WAIT: begin
            if (!act_read_valid_pipe_q[0]
                && (!act_read_valid_pipe_q[1] || act_read_capture_w)) begin
              state_q <= S_LAUNCH_ACT;
            end
          end

          S_LAUNCH_ACT: begin
            act_flat_raw_o <= act_flatten_w;
            act_valid_raw_o <= {SIZE{1'b1}};
            work_o <= 1'b1;
            dbg_useful_mac_count_o <= dbg_useful_mac_count_o + count_valid_weights(weight_valid_w);

            if ((stream_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              state_q <= S_DRAIN_MXU;
            end else begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              act_fetch_lane_q <= '0;
              act_read_valid_pipe_q <= '0;
              act_read_lane_pipe_q[0] <= '0;
              act_read_lane_pipe_q[1] <= '0;
              state_q <= S_READ_ACT_REQ;
            end
          end

          S_DRAIN_MXU: begin
            if (!psum_packer_busy_i && !(|mxu_psum_valid_i)) begin
              if (last_k_tile_w) begin
                state_q <= S_WAIT_ACC_READY;
              end else begin
                k_tile_q <= k_tile_q + 16'd1;
                stream_idx_q <= '0;
                state_q <= S_FETCH_ROM;
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
            vpu_input_done_o <= (acc_read_idx_q == (block_size_q - ACC_COUNT_WIDTH'(1)));
            if (vpu_data_valid_i) begin
              vpu_data_q <= vpu_data_flatten_i;
              output_lane_q <= '0;
              state_q <= S_WRITE_OUTPUT_LANE;
            end
          end

          S_WRITE_OUTPUT_LANE: begin
            if (!oc_valid_w[output_lane_q]) begin
              if ((output_lane_q + 16'd1) >= 16'(SIZE)) begin
                if ((acc_read_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
                  state_q <= S_DONE;
                end else begin
                  acc_read_idx_q <= acc_read_idx_q + ACC_COUNT_WIDTH'(1);
                  state_q <= S_READ_ACC_ROW;
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

              if ((output_lane_q + 16'd1) >= 16'(SIZE)) begin
                if ((acc_read_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
                  state_q <= S_DONE;
                end else begin
                  acc_read_idx_q <= acc_read_idx_q + ACC_COUNT_WIDTH'(1);
                  state_q <= S_READ_ACC_ROW;
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

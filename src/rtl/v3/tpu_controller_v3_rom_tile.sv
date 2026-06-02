`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// ROM-backed V3 controller wrapper for one accumulator row and one OC tile.
//
// This wraps tpu_controller_v3_tile with layer descriptor ROM, bias/requant ROMs,
// and two-lane UB output writeback. Weight ROM access remains datapath-facing:
// tpu_datapath_v3 emits weight_rd_en/addr through weight_tile_buffer_v3.
module tpu_controller_v3_rom_tile #(
    parameter int SIZE                = 2,
    parameter int DATA_WIDTH          = 8,
    parameter int OUT_WIDTH           = 8,
    parameter int UB_ADDR_WIDTH       = 13,
    parameter int WGT_ADDR_WIDTH      = 13,
    parameter int TAG_WIDTH           = 16,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int ACC_WIDTH           = 32,
    parameter int MAX_NUM_TILES       = 128,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1,
    parameter int PARAM_DEPTH         = 44,
    parameter int PARAM_ADDR_WIDTH    = (PARAM_DEPTH > 1) ? $clog2(PARAM_DEPTH) : 1,
    parameter int BANK_DEPTH          = 8192,
    parameter string BIAS_INIT_FILE   = "small_cnn_sym_biases_i32.mem",
    parameter string REQUANT_MULT_INIT_FILE = "small_cnn_sym_requant_mult_i32.mem",
    parameter string REQUANT_SHIFT_INIT_FILE = "small_cnn_sym_requant_shift_u6.mem"
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    input  logic clear_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [4:0] dbg_tile_state_o,
    output logic [15:0] dbg_k_tile_o,
    output logic [31:0] dbg_cycle_count_o,
    output logic [31:0] dbg_error_code_o,

    input logic [1:0] layer_idx_i,
    input logic       use_descriptor_banks_i,
    input logic       read_bank_i,
    input logic       write_bank_i,
    input logic [UB_ADDR_WIDTH-1:0] activation_base_addr_i,
    input logic [UB_ADDR_WIDTH-1:0] output_base_addr_i,
    input logic [15:0] spatial_idx_i,
    input logic [15:0] oc_tile_idx_i,
    input logic [ACC_ADDR_WIDTH-1:0] accumulator_row_addr_i,

    output logic ub_rd_bank_o,

    output logic                         ub_wr_en_o,
    output logic                         ub_wr_bank_o,
    output logic [UB_ADDR_WIDTH-1:0]     ub_wr_addr_o,
    output logic signed [DATA_WIDTH-1:0] ub_wr_data_o,

    output logic                                wgt_req_valid_o,
    input  logic                                wgt_req_ready_i,
    output logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0] wgt_req_addr_flatten_o,
    output logic [SIZE*SIZE-1:0]                wgt_req_valid_mask_o,
    output logic [SIZE*SIZE-1:0]                wgt_req_zero_mask_o,
    output logic [TAG_WIDTH-1:0]                wgt_req_tag_o,
    output logic                                wgt_tile_release_o,
    output logic                                wgt_stream_start_o,
    input  logic                                wgt_tile_valid_i,
    input  logic [SIZE-1:0]                     wgt_load_done_i,

    output logic                           act_req_valid_o,
    input  logic                           act_req_ready_i,
    output logic [SIZE*UB_ADDR_WIDTH-1:0]  act_req_addr_flatten_o,
    output logic [SIZE-1:0]                act_req_lane_valid_o,
    output logic [SIZE-1:0]                act_req_lane_zero_o,
    output logic [TAG_WIDTH-1:0]           act_req_tag_o,

    output logic                      accumulator_clear_all_o,
    output logic                      accumulator_row_clear_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_row_clear_addr_o,
    output logic                      accumulator_write_en_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_write_addr_o,
    output logic                      accumulator_read_en_o,
    output logic [ACC_ADDR_WIDTH-1:0] accumulator_read_addr_o,
    input  logic                      accumulator_read_valid_i,
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
    input logic            psum_packer_busy_i,

    output logic [TILE_COUNT_WIDTH-1:0] num_tiles_o
);

  typedef enum logic [4:0] {
    S_IDLE,
    S_FETCH_PARAM,
    S_WAIT_PARAM,
    S_START_TILE,
    S_RUN_TILE,
    S_WRITE_OUTPUT0,
    S_WRITE_OUTPUT1,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [31:0] ERR_DESC_INVALID = 32'h0004_0001;
  localparam logic [31:0] ERR_PARAM_VALID  = 32'h0004_0002;
  localparam logic [31:0] ERR_OC_TILE      = 32'h0004_0003;
  localparam logic [31:0] ERR_OUTPUT_ADDR  = 32'h0004_0004;
  localparam logic [31:0] ERR_TILE         = 32'h0004_0005;

  state_t state_q;
  state_t state_d;

  logic [1:0] layer_idx_q;
  logic use_descriptor_banks_q;
  logic read_bank_q;
  logic write_bank_q;
  logic [UB_ADDR_WIDTH-1:0] activation_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_q;
  logic [15:0] spatial_idx_q;
  logic [15:0] oc_tile_idx_q;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_addr_q;

  logic desc_valid_w;
  layer_type_t desc_layer_type_w;
  logic [15:0] desc_in_h_w;
  logic [15:0] desc_in_w_w;
  logic [15:0] desc_in_ch_unused_w;
  logic [15:0] desc_out_h_unused_w;
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

  logic [15:0] oc_idx_w[0:SIZE-1];
  logic [SIZE-1:0] oc_valid_w;
  logic [PARAM_ADDR_WIDTH-1:0] bias_addr_w[0:SIZE-1];
  logic [PARAM_ADDR_WIDTH-1:0] requant_addr_w[0:SIZE-1];
  logic signed [BIAS_WIDTH-1:0] bias_data_w[0:SIZE-1];
  logic [SIZE-1:0] bias_valid_w;
  logic signed [REQUANT_MULT_WIDTH-1:0] requant_mult_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_mult_valid_w;
  logic [REQUANT_SHIFT_WIDTH-1:0] requant_shift_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_shift_valid_w;

  logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_q;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_q;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_q;
  logic [1:0] act_mode_q;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_q;

  logic tile_start_w;
  logic tile_done_w;
  logic tile_busy_w;
  logic tile_error_w;
  logic [31:0] tile_error_code_w;
  logic [31:0] tile_cycle_count_w;
  logic [4:0] tile_state_w;
  logic [15:0] tile_k_tile_w;

  logic param_en_w;
  logic param_valid_w;
  logic inner_read_bank_w;
  logic inner_write_bank_w;
  logic [31:0] output_addr0_w;
  logic [31:0] output_addr1_w;
  logic output_addr_valid0_w;
  logic output_addr_valid1_w;

  layer_descriptor_rom u_layer_descriptor_rom (
      .layer_idx_i    (layer_idx_q),
      .valid_o        (desc_valid_w),
      .layer_type_o   (desc_layer_type_w),
      .in_h_o         (desc_in_h_w),
      .in_w_o         (desc_in_w_w),
      .in_ch_o        (desc_in_ch_unused_w),
      .out_h_o        (desc_out_h_unused_w),
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

  generate
    for (genvar lane = 0; lane < SIZE; lane++) begin : GEN_PARAM_ROMS
      assign oc_idx_w[lane] = (oc_tile_idx_q * 16'(SIZE)) + 16'(lane);
      assign oc_valid_w[lane] = (oc_idx_w[lane] < desc_out_ch_w);
      assign bias_addr_w[lane] =
          oc_valid_w[lane] ? PARAM_ADDR_WIDTH'(desc_bias_base_w + oc_idx_w[lane]) : '0;
      assign requant_addr_w[lane] =
          oc_valid_w[lane] ? PARAM_ADDR_WIDTH'(desc_requant_base_w + oc_idx_w[lane]) : '0;

      bias_rom #(
          .DATA_WIDTH(BIAS_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH),
          .INIT_FILE (BIAS_INIT_FILE)
      ) u_bias_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (param_en_w),
          .addr_i (bias_addr_w[lane]),
          .data_o (bias_data_w[lane]),
          .valid_o(bias_valid_w[lane])
      );

      requant_mult_rom #(
          .DATA_WIDTH(REQUANT_MULT_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH),
          .INIT_FILE (REQUANT_MULT_INIT_FILE)
      ) u_requant_mult_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (param_en_w),
          .addr_i (requant_addr_w[lane]),
          .data_o (requant_mult_data_w[lane]),
          .valid_o(requant_mult_valid_w[lane])
      );

      requant_shift_rom #(
          .DATA_WIDTH(REQUANT_SHIFT_WIDTH),
          .DEPTH     (PARAM_DEPTH),
          .ADDR_WIDTH(PARAM_ADDR_WIDTH),
          .INIT_FILE (REQUANT_SHIFT_INIT_FILE)
      ) u_requant_shift_rom (
          .clk    (clk),
          .rst_n  (rst_n),
          .en_i   (param_en_w),
          .addr_i (requant_addr_w[lane]),
          .data_o (requant_shift_data_w[lane]),
          .valid_o(requant_shift_valid_w[lane])
      );
    end
  endgenerate

  tpu_controller_v3_tile #(
      .SIZE               (SIZE),
      .ACT_ADDR_WIDTH     (UB_ADDR_WIDTH),
      .WGT_ADDR_WIDTH     (WGT_ADDR_WIDTH),
      .TAG_WIDTH          (TAG_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH)
  ) u_tile_controller (
      .clk                              (clk),
      .rst_n                            (rst_n),
      .start_i                          (tile_start_w),
      .clear_i                          (clear_i),
      .done_o                           (tile_done_w),
      .busy_o                           (tile_busy_w),
      .error_o                          (tile_error_w),
      .dbg_state_o                      (tile_state_w),
      .dbg_k_tile_o                     (tile_k_tile_w),
      .dbg_cycle_count_o                (tile_cycle_count_w),
      .dbg_error_code_o                 (tile_error_code_w),
      .layer_type_i                     (desc_layer_type_w),
      .activation_base_addr_i           (activation_base_addr_q),
      .weight_base_addr_i               (WGT_ADDR_WIDTH'(desc_weight_base_w)),
      .in_h_i                           (desc_in_h_w),
      .in_w_i                           (desc_in_w_w),
      .out_w_i                          (desc_out_w_w),
      .out_ch_i                         (desc_out_ch_w),
      .kernel_h_i                       (desc_kernel_h_w),
      .kernel_w_i                       (desc_kernel_w_w),
      .k_total_i                        (desc_k_total_w),
      .num_k_tiles_i                    (desc_num_k_tiles_w),
      .spatial_idx_i                    (spatial_idx_q),
      .oc_tile_idx_i                    (oc_tile_idx_q),
      .accumulator_row_addr_i           (accumulator_row_addr_q),
      .wgt_req_valid_o                  (wgt_req_valid_o),
      .wgt_req_ready_i                  (wgt_req_ready_i),
      .wgt_req_addr_flatten_o           (wgt_req_addr_flatten_o),
      .wgt_req_valid_mask_o             (wgt_req_valid_mask_o),
      .wgt_req_zero_mask_o              (wgt_req_zero_mask_o),
      .wgt_req_tag_o                    (wgt_req_tag_o),
      .wgt_tile_release_o               (wgt_tile_release_o),
      .wgt_stream_start_o               (wgt_stream_start_o),
      .wgt_tile_valid_i                 (wgt_tile_valid_i),
      .wgt_load_done_i                  (wgt_load_done_i),
      .act_req_valid_o                  (act_req_valid_o),
      .act_req_ready_i                  (act_req_ready_i),
      .act_req_addr_flatten_o           (act_req_addr_flatten_o),
      .act_req_lane_valid_o             (act_req_lane_valid_o),
      .act_req_lane_zero_o              (act_req_lane_zero_o),
      .act_req_tag_o                    (act_req_tag_o),
      .accumulator_clear_all_o          (accumulator_clear_all_o),
      .accumulator_row_clear_o          (accumulator_row_clear_o),
      .accumulator_row_clear_addr_o     (accumulator_row_clear_addr_o),
      .accumulator_write_en_o           (accumulator_write_en_o),
      .accumulator_write_addr_o         (accumulator_write_addr_o),
      .accumulator_read_en_o            (accumulator_read_en_o),
      .accumulator_read_addr_o          (accumulator_read_addr_o),
      .accumulator_read_valid_i         (accumulator_read_valid_i),
      .accumulator_row_ready_i          (accumulator_row_ready_i),
      .vpu_input_done_o                 (vpu_input_done_o),
      .vpu_act_mode_o                   (vpu_act_mode_o),
      .vpu_bias_flatten_o               (vpu_bias_flatten_o),
      .vpu_requant_multiplier_flatten_o (vpu_requant_multiplier_flatten_o),
      .vpu_requant_shift_flatten_o      (vpu_requant_shift_flatten_o),
      .vpu_output_zero_point_o          (vpu_output_zero_point_o),
      .vpu_data_valid_i                 (vpu_data_valid_i),
      .mxu_psum_valid_i                 (mxu_psum_valid_i),
      .psum_packer_busy_i               (psum_packer_busy_i),
      .vpu_act_mode_i                   (act_mode_q),
      .vpu_bias_flatten_i               (bias_flatten_q),
      .vpu_requant_multiplier_flatten_i (requant_multiplier_flatten_q),
      .vpu_requant_shift_flatten_i      (requant_shift_flatten_q),
      .vpu_output_zero_point_i          ('0)
  );

  assign param_en_w = (state_q == S_FETCH_PARAM);
  assign param_valid_w = (bias_valid_w == {SIZE{1'b1}})
                      && (requant_mult_valid_w == {SIZE{1'b1}})
                      && (requant_shift_valid_w == {SIZE{1'b1}});
  assign inner_read_bank_w = use_descriptor_banks_q ? desc_read_bank_w : read_bank_q;
  assign inner_write_bank_w = use_descriptor_banks_q ? desc_write_bank_w : write_bank_q;
  assign output_addr0_w = 32'(output_base_addr_q)
                        + (32'(oc_idx_w[0]) * 32'(desc_num_spatial_w))
                        + 32'(spatial_idx_q);
  assign output_addr1_w = 32'(output_base_addr_q)
                        + (32'(oc_idx_w[1]) * 32'(desc_num_spatial_w))
                        + 32'(spatial_idx_q);
  assign output_addr_valid0_w = oc_valid_w[0] && (output_addr0_w < 32'(BANK_DEPTH));
  assign output_addr_valid1_w = oc_valid_w[1] && (output_addr1_w < 32'(BANK_DEPTH));
  assign tile_start_w = (state_q == S_START_TILE);
  assign num_tiles_o = TILE_COUNT_WIDTH'(desc_num_k_tiles_w);
  assign ub_rd_bank_o = inner_read_bank_w;

  always_comb begin
    state_d = state_q;

    unique case (state_q)
      S_IDLE: begin
        if (start_i) begin
          state_d = S_FETCH_PARAM;
        end
      end

      S_FETCH_PARAM: begin
        if (!desc_valid_w) begin
          state_d = S_ERROR;
        end else if (oc_tile_idx_q >= desc_num_oc_tiles_w) begin
          state_d = S_ERROR;
        end else begin
          state_d = S_WAIT_PARAM;
        end
      end

      S_WAIT_PARAM: begin
        if (param_valid_w) begin
          state_d = S_START_TILE;
        end
      end

      S_START_TILE: begin
        state_d = S_RUN_TILE;
      end

      S_RUN_TILE: begin
        if (tile_error_w) begin
          state_d = S_ERROR;
        end else if (vpu_data_valid_i) begin
          if (output_addr_valid0_w) begin
            state_d = S_WRITE_OUTPUT0;
          end else if (output_addr_valid1_w) begin
            state_d = S_WRITE_OUTPUT1;
          end else begin
            state_d = S_DONE;
          end
        end
      end

      S_WRITE_OUTPUT0: begin
        if (output_addr_valid1_w) begin
          state_d = S_WRITE_OUTPUT1;
        end else begin
          state_d = S_DONE;
        end
      end

      S_WRITE_OUTPUT1: begin
        state_d = S_DONE;
      end

      S_DONE: begin
        state_d = S_IDLE;
      end

      S_ERROR: begin
        if (clear_i) begin
          state_d = S_IDLE;
        end
      end

      default: begin
        state_d = S_ERROR;
      end
    endcase

    if (clear_i) begin
      state_d = S_IDLE;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      done_o <= 1'b0;
      error_o <= 1'b0;
      dbg_cycle_count_o <= '0;
      dbg_error_code_o <= '0;
      layer_idx_q <= '0;
      use_descriptor_banks_q <= 1'b0;
      read_bank_q <= 1'b0;
      write_bank_q <= 1'b1;
      activation_base_addr_q <= '0;
      output_base_addr_q <= '0;
      spatial_idx_q <= '0;
      oc_tile_idx_q <= '0;
      accumulator_row_addr_q <= '0;
      bias_flatten_q <= '0;
      requant_multiplier_flatten_q <= '0;
      requant_shift_flatten_q <= '0;
      act_mode_q <= ACT_BYPASS;
      vpu_data_q <= '0;
    end else begin
      state_q <= state_d;
      done_o <= 1'b0;

      if (clear_i) begin
        error_o <= 1'b0;
        dbg_cycle_count_o <= '0;
        dbg_error_code_o <= '0;
        vpu_data_q <= '0;
      end else begin
        if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
          dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
        end

        if (state_q == S_IDLE && start_i) begin
          error_o <= 1'b0;
          dbg_cycle_count_o <= '0;
          dbg_error_code_o <= '0;
          layer_idx_q <= layer_idx_i;
          use_descriptor_banks_q <= use_descriptor_banks_i;
          read_bank_q <= read_bank_i;
          write_bank_q <= write_bank_i;
          activation_base_addr_q <= activation_base_addr_i;
          output_base_addr_q <= output_base_addr_i;
          spatial_idx_q <= spatial_idx_i;
          oc_tile_idx_q <= oc_tile_idx_i;
          accumulator_row_addr_q <= accumulator_row_addr_i;
          vpu_data_q <= '0;
        end

        if (state_q == S_FETCH_PARAM) begin
          if (!desc_valid_w) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_DESC_INVALID;
          end else if (oc_tile_idx_q >= desc_num_oc_tiles_w) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_OC_TILE;
          end
        end

        if (state_q == S_WAIT_PARAM && param_valid_w) begin
          for (int lane = 0; lane < SIZE; lane++) begin
            bias_flatten_q[(lane*BIAS_WIDTH)+:BIAS_WIDTH] <= oc_valid_w[lane] ? bias_data_w[lane] : '0;
            requant_multiplier_flatten_q[(lane*REQUANT_MULT_WIDTH)+:REQUANT_MULT_WIDTH] <=
                oc_valid_w[lane] ? requant_mult_data_w[lane] : '0;
            requant_shift_flatten_q[(lane*REQUANT_SHIFT_WIDTH)+:REQUANT_SHIFT_WIDTH] <=
                oc_valid_w[lane] ? requant_shift_data_w[lane] : '0;
          end
          act_mode_q <= desc_act_mode_w;
        end else if (state_q == S_WAIT_PARAM && !param_valid_w) begin
          dbg_error_code_o <= ERR_PARAM_VALID;
        end

        if (state_q == S_RUN_TILE && tile_error_w) begin
          error_o <= 1'b1;
          dbg_error_code_o <= ERR_TILE | tile_error_code_w;
        end

        if (state_q == S_RUN_TILE && vpu_data_valid_i) begin
          vpu_data_q <= vpu_data_flatten_i;
          if (!output_addr_valid0_w && !output_addr_valid1_w) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_OUTPUT_ADDR;
          end
        end

        if (state_q == S_DONE) begin
          done_o <= 1'b1;
        end
      end
    end
  end

  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_tile_state_o = tile_state_w;
  assign dbg_k_tile_o = tile_k_tile_w;

  assign ub_wr_en_o = (state_q == S_WRITE_OUTPUT0) || (state_q == S_WRITE_OUTPUT1);
  assign ub_wr_bank_o = inner_write_bank_w;
  assign ub_wr_addr_o = (state_q == S_WRITE_OUTPUT1)
                      ? UB_ADDR_WIDTH'(output_addr1_w)
                      : UB_ADDR_WIDTH'(output_addr0_w);
  assign ub_wr_data_o = (state_q == S_WRITE_OUTPUT1)
                      ? vpu_data_q[(1*OUT_WIDTH)+:OUT_WIDTH]
                      : vpu_data_q[(0*OUT_WIDTH)+:OUT_WIDTH];

endmodule : tpu_controller_v3_rom_tile

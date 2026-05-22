`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// ROM-backed wrapper for one 2x2 compute tile.
module tpu_controller_rom_tile #(
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
    parameter int BANK_DEPTH          = 8192,
    parameter int ROM_ADDR_WIDTH      = 16,
    parameter int WEIGHT_DEPTH        = 4952,
    parameter int WEIGHT_ADDR_WIDTH   = (WEIGHT_DEPTH > 1) ? $clog2(WEIGHT_DEPTH) : 1,
    parameter int PARAM_DEPTH         = 44,
    parameter int PARAM_ADDR_WIDTH    = (PARAM_DEPTH > 1) ? $clog2(PARAM_DEPTH) : 1
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [4:0] dbg_inner_state_o,
    output logic [15:0] dbg_cycle_count_o,
    output logic [31:0] dbg_error_code_o,

    input logic [1:0] layer_idx_i,
    input logic       use_descriptor_banks_i,
    input logic       read_bank_i,
    input logic       write_bank_i,
    input logic [UB_ADDR_WIDTH-1:0] activation_base_addr_i,
    input logic [UB_ADDR_WIDTH-1:0] output_base_addr_i,
    input logic [ACC_ADDR_WIDTH:0]  block_size_i,
    input logic [15:0] spatial_idx_i,
    input logic [15:0] k_tile_idx_i,
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
    S_FETCH_ROM,
    S_WAIT_ROM,
    S_START_INNER,
    S_RUN_INNER,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [31:0] ERR_DESC_INVALID          = 32'h0001_0001;
  localparam logic [31:0] ERR_BLOCK_SIZE            = 32'h0001_0002;
  localparam logic [31:0] ERR_K_TILE                = 32'h0001_0003;
  localparam logic [31:0] ERR_OC_TILE               = 32'h0001_0004;
  localparam logic [31:0] ERR_PADDED_K_UNSUPPORTED  = 32'h0001_0005;
  localparam logic [31:0] ERR_NONCONTIG_ACT         = 32'h0001_0006;
  localparam logic [31:0] ERR_PADDED_OC_UNSUPPORTED = 32'h0001_0007;
  localparam logic [31:0] ERR_ROM_VALID             = 32'h0001_0008;
  localparam logic [31:0] ERR_INNER_CONTROLLER      = 32'h0001_0009;

  state_t state_q;

  logic [1:0] layer_idx_q;
  logic use_descriptor_banks_q;
  logic read_bank_q;
  logic write_bank_q;
  logic [UB_ADDR_WIDTH-1:0] activation_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_q;
  logic [ACC_ADDR_WIDTH:0] block_size_q;
  logic [15:0] spatial_idx_q;
  logic [15:0] k_tile_idx_q;
  logic [15:0] oc_tile_idx_q;

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

  logic [ROM_ADDR_WIDTH*SIZE-1:0]      act_addr_flatten_w;
  logic [SIZE-1:0]                     act_valid_w;
  logic [SIZE-1:0]                     act_zero_w;
  logic [ROM_ADDR_WIDTH*SIZE*SIZE-1:0] weight_addr_flatten_w;
  logic [SIZE*SIZE-1:0]                weight_valid_w;
  logic [SIZE*SIZE-1:0]                weight_zero_w;
  logic [15:0]                         oc_idx_w[0:SIZE-1];
  logic [16*SIZE-1:0]                  k_index_flatten_bus_w;
  logic [16*SIZE-1:0]                  oc_index_flatten_bus_w;

  logic rom_en_w;
  logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_w[0:SIZE*SIZE-1];
  logic [PARAM_ADDR_WIDTH-1:0] bias_addr_w[0:SIZE-1];
  logic [PARAM_ADDR_WIDTH-1:0] requant_addr_w[0:SIZE-1];

  logic signed [DATA_WIDTH-1:0] weight_data_w[0:SIZE*SIZE-1];
  logic [SIZE*SIZE-1:0] weight_data_valid_w;
  logic signed [BIAS_WIDTH-1:0] bias_data_w[0:SIZE-1];
  logic [SIZE-1:0] bias_data_valid_w;
  logic signed [REQUANT_MULT_WIDTH-1:0] requant_mult_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_mult_valid_w;
  logic [REQUANT_SHIFT_WIDTH-1:0] requant_shift_data_w[0:SIZE-1];
  logic [SIZE-1:0] requant_shift_valid_w;

  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_top_row_q;
  logic signed [(DATA_WIDTH*SIZE)-1:0] weight_bottom_row_q;
  logic [1:0] act_mode_q;
  logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_q;
  logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_q;
  logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_q;
  logic [UB_ADDR_WIDTH-1:0] inner_input_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] inner_output_base_addr_q;
  logic inner_start_q;
  logic inner_done_w;
  logic inner_busy_w;
  logic inner_error_w;
  logic [4:0] inner_state_w;
  logic [15:0] inner_cycle_count_w;
  logic [31:0] inner_error_code_w;
  logic [TILE_COUNT_WIDTH-1:0] inner_num_tiles_w;
  logic inner_read_bank_w;
  logic inner_write_bank_w;

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

  conv_fc_address_generator #(
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
      .spatial_idx_i         (spatial_idx_q),
      .k_tile_idx_i          (k_tile_idx_q),
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

  // The K-index bus is consumed by future multi-K controller work.
  // Keep it connected so address-generator lint covers both output buses.

  generate
    for (genvar idx = 0; idx < SIZE * SIZE; idx++) begin : GEN_WEIGHT_ROMS
      assign weight_addr_w[idx] =
          WEIGHT_ADDR_WIDTH'(weight_addr_flatten_w[(idx*ROM_ADDR_WIDTH)+:ROM_ADDR_WIDTH]);

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
      assign bias_addr_w[lane] = PARAM_ADDR_WIDTH'(desc_bias_base_w + oc_idx_w[lane]);
      assign requant_addr_w[lane] = PARAM_ADDR_WIDTH'(desc_requant_base_w + oc_idx_w[lane]);

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
  assign inner_num_tiles_w = TILE_COUNT_WIDTH'(1);
  assign inner_read_bank_w = use_descriptor_banks_q ? desc_read_bank_w : read_bank_q;
  assign inner_write_bank_w = use_descriptor_banks_q ? desc_write_bank_w : write_bank_q;

  tpu_controller #(
      .SIZE               (SIZE),
      .DATA_WIDTH         (DATA_WIDTH),
      .ACC_WIDTH          (ACC_WIDTH),
      .OUT_WIDTH          (OUT_WIDTH),
      .ACC_DEPTH          (ACC_DEPTH),
      .ACC_ADDR_WIDTH     (ACC_ADDR_WIDTH),
      .UB_ADDR_WIDTH      (UB_ADDR_WIDTH),
      .BIAS_WIDTH         (BIAS_WIDTH),
      .REQUANT_MULT_WIDTH (REQUANT_MULT_WIDTH),
      .REQUANT_SHIFT_WIDTH(REQUANT_SHIFT_WIDTH),
      .MAX_NUM_TILES      (MAX_NUM_TILES),
      .TILE_COUNT_WIDTH   (TILE_COUNT_WIDTH),
      .BANK_DEPTH         (BANK_DEPTH)
  ) u_inner_controller (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .start_i                         (inner_start_q),
      .done_o                          (inner_done_w),
      .busy_o                          (inner_busy_w),
      .error_o                         (inner_error_w),
      .dbg_state_o                     (inner_state_w),
      .dbg_cycle_count_o               (inner_cycle_count_w),
      .dbg_error_code_o                (inner_error_code_w),
      .read_bank_i                     (inner_read_bank_w),
      .write_bank_i                    (inner_write_bank_w),
      .input_base_addr_i               (inner_input_base_addr_q),
      .output_base_addr_i              (inner_output_base_addr_q),
      .block_size_i                    (block_size_q),
      .num_tiles_i                     (inner_num_tiles_w),
      .weight_bottom_row_i             (weight_bottom_row_q),
      .weight_top_row_i                (weight_top_row_q),
      .act_mode_i                      (act_mode_q),
      .bias_flatten_i                  (bias_flatten_q),
      .requant_multiplier_flatten_i    (requant_multiplier_flatten_q),
      .requant_shift_flatten_i         (requant_shift_flatten_q),
      .ub_rd_en_o                      (ub_rd_en_o),
      .ub_rd_bank_o                    (ub_rd_bank_o),
      .ub_rd_addr_o                    (ub_rd_addr_o),
      .ub_rd_data_i                    (ub_rd_data_i),
      .ub_rd_valid_i                   (ub_rd_valid_i),
      .ub_wr_en_o                      (ub_wr_en_o),
      .ub_wr_bank_o                    (ub_wr_bank_o),
      .ub_wr_addr_o                    (ub_wr_addr_o),
      .ub_wr_data_o                    (ub_wr_data_o),
      .work_o                          (work_o),
      .num_tiles_o                     (num_tiles_o),
      .start_wgt_load_o                (start_wgt_load_o),
      .wgt_fifo_wdata_o                (wgt_fifo_wdata_o),
      .wgt_fifo_wr_en_o                (wgt_fifo_wr_en_o),
      .wgt_fifo_full_i                 (wgt_fifo_full_i),
      .wgt_fetcher_ready_i             (wgt_fetcher_ready_i),
      .wgt_load_done_i                 (wgt_load_done_i),
      .act_flat_raw_o                  (act_flat_raw_o),
      .act_valid_raw_o                 (act_valid_raw_o),
      .accumulator_clear_all_o         (accumulator_clear_all_o),
      .accumulator_row_clear_o         (accumulator_row_clear_o),
      .accumulator_row_clear_addr_o    (accumulator_row_clear_addr_o),
      .accumulator_write_en_o          (accumulator_write_en_o),
      .accumulator_write_addr_o        (accumulator_write_addr_o),
      .accumulator_read_en_o           (accumulator_read_en_o),
      .accumulator_read_addr_o         (accumulator_read_addr_o),
      .accumulator_row_ready_i         (accumulator_row_ready_i),
      .vpu_input_done_o                (vpu_input_done_o),
      .vpu_act_mode_o                  (vpu_act_mode_o),
      .vpu_bias_flatten_o              (vpu_bias_flatten_o),
      .vpu_requant_multiplier_flatten_o(vpu_requant_multiplier_flatten_o),
      .vpu_requant_shift_flatten_o     (vpu_requant_shift_flatten_o),
      .vpu_output_zero_point_o         (vpu_output_zero_point_o),
      .vpu_data_flatten_i              (vpu_data_flatten_i),
      .vpu_data_valid_i                (vpu_data_valid_i),
      .mxu_psum_valid_i                (mxu_psum_valid_i),
      .psum_packer_busy_i              (psum_packer_busy_i)
  );

  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;
  assign dbg_inner_state_o = inner_state_w;

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
      block_size_q <= '0;
      spatial_idx_q <= '0;
      k_tile_idx_q <= '0;
      oc_tile_idx_q <= '0;
      weight_top_row_q <= '0;
      weight_bottom_row_q <= '0;
      act_mode_q <= ACT_BYPASS;
      bias_flatten_q <= '0;
      requant_multiplier_flatten_q <= '0;
      requant_shift_flatten_q <= '0;
      inner_input_base_addr_q <= '0;
      inner_output_base_addr_q <= '0;
      inner_start_q <= 1'b0;
    end else begin
      done_o <= 1'b0;
      inner_start_q <= 1'b0;

      if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 16'd1;
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
            k_tile_idx_q <= k_tile_idx_i;
            oc_tile_idx_q <= oc_tile_idx_i;
            dbg_cycle_count_o <= '0;
            state_q <= S_FETCH_ROM;
          end
        end

        S_FETCH_ROM: begin
          if (!desc_valid_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_DESC_INVALID;
          end else if (block_size_q != (ACC_ADDR_WIDTH+1)'(1)) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_BLOCK_SIZE;
          end else if (k_tile_idx_q >= desc_num_k_tiles_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_K_TILE;
          end else if (oc_tile_idx_q >= desc_num_oc_tiles_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_OC_TILE;
          end else if (act_zero_w != '0) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_PADDED_K_UNSUPPORTED;
          end else if (act_addr_flatten_w[ROM_ADDR_WIDTH+:ROM_ADDR_WIDTH]
                       != (act_addr_flatten_w[0+:ROM_ADDR_WIDTH] + ROM_ADDR_WIDTH'(1))) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_NONCONTIG_ACT;
          end else if (weight_zero_w != '0) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_PADDED_OC_UNSUPPORTED;
          end else begin
            state_q <= S_WAIT_ROM;
          end
        end

        S_WAIT_ROM: begin
          if ((weight_data_valid_w != '1) || (bias_data_valid_w != '1)
              || (requant_mult_valid_w != '1) || (requant_shift_valid_w != '1)) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_ROM_VALID;
          end else begin
            weight_top_row_q <= {
              weight_data_w[(0*SIZE)+1],
              weight_data_w[(0*SIZE)+0]
            };
            weight_bottom_row_q <= {
              weight_data_w[(1*SIZE)+1],
              weight_data_w[(1*SIZE)+0]
            };
            act_mode_q <= desc_act_mode_w;
            bias_flatten_q <= {bias_data_w[1], bias_data_w[0]};
            requant_multiplier_flatten_q <= {requant_mult_data_w[1], requant_mult_data_w[0]};
            requant_shift_flatten_q <= {requant_shift_data_w[1], requant_shift_data_w[0]};
            inner_input_base_addr_q <= UB_ADDR_WIDTH'(act_addr_flatten_w[0+:ROM_ADDR_WIDTH]);
            inner_output_base_addr_q <= output_base_addr_q
                                      + UB_ADDR_WIDTH'(oc_tile_idx_q * 16'(SIZE));
            state_q <= S_START_INNER;
          end
        end

        S_START_INNER: begin
          inner_start_q <= 1'b1;
          state_q <= S_RUN_INNER;
        end

        S_RUN_INNER: begin
          if (inner_error_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_INNER_CONTROLLER | {16'h0000, inner_error_code_w[15:0]};
          end else if (inner_done_w) begin
            state_q <= S_DONE;
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
          dbg_error_code_o <= ERR_INNER_CONTROLLER;
        end
      endcase
    end
  end

endmodule : tpu_controller_rom_tile

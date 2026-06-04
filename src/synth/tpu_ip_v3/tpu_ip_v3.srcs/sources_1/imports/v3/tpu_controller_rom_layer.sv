`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// ROM-driven controller for one complete compute layer over spatial blocks and OC tiles.
module tpu_controller_rom_layer #(
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
    output logic [4:0] dbg_tile_state_o,
    output logic [31:0] dbg_cycle_count_o,
    output logic [15:0] dbg_spatial_idx_o,
    output logic [15:0] dbg_oc_tile_o,
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
    S_START_TILE,
    S_RUN_TILE,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [31:0] ERR_DESC_INVALID = 32'h0003_0001;
  localparam logic [31:0] ERR_CHILD        = 32'h0003_0002;
  localparam logic [31:0] ERR_BLOCK_SIZE   = 32'h0003_0003;
  localparam logic [31:0] ERR_SPATIAL      = 32'h0003_0004;

  localparam int ACC_COUNT_WIDTH = ACC_ADDR_WIDTH + 1;

  state_t state_q;

  logic [1:0] layer_idx_q;
  logic use_descriptor_banks_q;
  logic read_bank_q;
  logic write_bank_q;
  logic [UB_ADDR_WIDTH-1:0] activation_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_q;
  logic [ACC_ADDR_WIDTH:0] block_size_q;
  logic [15:0] spatial_idx_q;
  logic [15:0] oc_tile_q;

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

  logic tile_start_q;
  logic tile_done_w;
  logic tile_busy_w;
  logic tile_error_w;
  logic [4:0] tile_state_w;
  logic [15:0] tile_cycle_count_w;
  logic [15:0] tile_k_tile_w;
  logic [31:0] tile_useful_mac_count_w;
  logic [31:0] tile_error_code_w;
  logic last_oc_tile_w;
  logic last_spatial_block_w;
  logic [15:0] remaining_spatial_w;
  logic [15:0] max_block_size_w;
  logic [15:0] tile_block_size_16_w;
  logic [ACC_ADDR_WIDTH:0] tile_block_size_w;

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

  tpu_controller_rom_kloop #(
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
      .BANK_DEPTH         (BANK_DEPTH),
      .ROM_ADDR_WIDTH     (ROM_ADDR_WIDTH),
      .WEIGHT_DEPTH       (WEIGHT_DEPTH),
      .WEIGHT_ADDR_WIDTH  (WEIGHT_ADDR_WIDTH),
      .PARAM_DEPTH        (PARAM_DEPTH),
      .PARAM_ADDR_WIDTH   (PARAM_ADDR_WIDTH)
  ) u_tile_controller (
      .clk                             (clk),
      .rst_n                           (rst_n),
      .start_i                         (tile_start_q),
      .done_o                          (tile_done_w),
      .busy_o                          (tile_busy_w),
      .error_o                         (tile_error_w),
      .dbg_state_o                     (tile_state_w),
      .dbg_cycle_count_o               (tile_cycle_count_w),
      .dbg_k_tile_o                    (tile_k_tile_w),
      .dbg_useful_mac_count_o          (tile_useful_mac_count_w),
      .dbg_error_code_o                (tile_error_code_w),
      .layer_idx_i                     (layer_idx_q),
      .use_descriptor_banks_i          (use_descriptor_banks_q),
      .read_bank_i                     (read_bank_q),
      .write_bank_i                    (write_bank_q),
      .activation_base_addr_i          (activation_base_addr_q),
      .output_base_addr_i              (output_base_addr_q),
      .block_size_i                    (tile_block_size_w),
      .spatial_idx_i                   (spatial_idx_q),
      .oc_tile_idx_i                   (oc_tile_q),
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
  assign dbg_tile_state_o = tile_state_w;
  assign dbg_spatial_idx_o = spatial_idx_q;
  assign dbg_oc_tile_o = oc_tile_q;
  assign dbg_k_tile_o = tile_k_tile_w;
  assign last_oc_tile_w = ((oc_tile_q + 16'd1) >= desc_num_oc_tiles_w);
  assign max_block_size_w = 16'(block_size_q);
  assign remaining_spatial_w = (spatial_idx_q < desc_num_spatial_w)
                             ? (desc_num_spatial_w - spatial_idx_q)
                             : 16'd0;
  assign tile_block_size_16_w = (remaining_spatial_w > max_block_size_w)
                              ? max_block_size_w
                              : remaining_spatial_w;
  assign tile_block_size_w = ACC_COUNT_WIDTH'(tile_block_size_16_w);
  assign last_spatial_block_w =
      ((spatial_idx_q + tile_block_size_16_w) >= desc_num_spatial_w);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      done_o <= 1'b0;
      error_o <= 1'b0;
      dbg_cycle_count_o <= '0;
      dbg_useful_mac_count_o <= '0;
      dbg_error_code_o <= '0;
      layer_idx_q <= '0;
      use_descriptor_banks_q <= 1'b0;
      read_bank_q <= 1'b0;
      write_bank_q <= 1'b1;
      activation_base_addr_q <= '0;
      output_base_addr_q <= '0;
      block_size_q <= '0;
      spatial_idx_q <= '0;
      oc_tile_q <= '0;
      tile_start_q <= 1'b0;
    end else begin
      done_o <= 1'b0;
      tile_start_q <= 1'b0;

      if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
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
            oc_tile_q <= '0;
            dbg_cycle_count_o <= '0;
            dbg_useful_mac_count_o <= '0;
            state_q <= S_START_TILE;
          end
        end

        S_START_TILE: begin
          if (!desc_valid_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_DESC_INVALID;
          end else if ((block_size_q == '0) || (block_size_q > ACC_COUNT_WIDTH'(ACC_DEPTH))) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_BLOCK_SIZE;
          end else if ((spatial_idx_q >= desc_num_spatial_w) || (tile_block_size_w == '0)) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_SPATIAL;
          end else begin
            tile_start_q <= 1'b1;
            state_q <= S_RUN_TILE;
          end
        end

        S_RUN_TILE: begin
          if (tile_error_w) begin
            state_q <= S_ERROR;
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_CHILD | {16'h0000, tile_error_code_w[15:0]};
          end else if (tile_done_w) begin
            dbg_useful_mac_count_o <= dbg_useful_mac_count_o + tile_useful_mac_count_w;
            if (last_oc_tile_w) begin
              if (last_spatial_block_w) begin
                state_q <= S_DONE;
              end else begin
                spatial_idx_q <= spatial_idx_q + tile_block_size_16_w;
                oc_tile_q <= '0;
                state_q <= S_START_TILE;
              end
            end else begin
              oc_tile_q <= oc_tile_q + 16'd1;
              state_q <= S_START_TILE;
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
          dbg_error_code_o <= ERR_CHILD;
        end
      endcase
    end
  end

endmodule : tpu_controller_rom_layer

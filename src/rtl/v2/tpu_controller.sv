`timescale 1ns / 1ps

// MVP controller for one 2x2 compute tile over a block of activation vectors.
module tpu_controller #(
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
    parameter int BANK_DEPTH          = 8192
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [15:0] dbg_cycle_count_o,
    output logic [31:0] dbg_error_code_o,

    input logic                       read_bank_i,
    input logic                       write_bank_i,
    input logic [UB_ADDR_WIDTH-1:0]   input_base_addr_i,
    input logic [UB_ADDR_WIDTH-1:0]   output_base_addr_i,
    input logic [ACC_ADDR_WIDTH:0]    block_size_i,
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] weight_bottom_row_i,
    input logic signed [(DATA_WIDTH*SIZE)-1:0] weight_top_row_i,

    input logic [1:0] act_mode_i,
    input logic signed [(BIAS_WIDTH*SIZE)-1:0] bias_flatten_i,
    input logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] requant_multiplier_flatten_i,
    input logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0] requant_shift_flatten_i,

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
    S_WRITE_WEIGHT_BOTTOM,
    S_WRITE_WEIGHT_TOP,
    S_START_WEIGHT_LOAD,
    S_WAIT_WEIGHT_LOAD,
    S_READ_ACT0_REQ,
    S_READ_ACT0_WAIT,
    S_READ_ACT1_REQ,
    S_READ_ACT1_WAIT,
    S_LAUNCH_ACT,
    S_DRAIN_MXU,
    S_WAIT_ACC_READY,
    S_READ_ACC_ROW,
    S_WAIT_VPU_OUTPUT,
    S_WRITE_OUTPUT0,
    S_WRITE_OUTPUT1,
    S_DONE,
    S_ERROR
  } ctrl_state_t;

  localparam logic [31:0] ERR_BLOCK_SIZE    = 32'h0000_0001;
  localparam logic [31:0] ERR_TILE_COUNT    = 32'h0000_0002;
  localparam logic [31:0] ERR_INPUT_ADDR    = 32'h0000_0003;
  localparam logic [31:0] ERR_OUTPUT_ADDR   = 32'h0000_0004;
  localparam logic [31:0] ERR_WGT_FIFO_FULL = 32'h0000_0005;
  localparam logic [31:0] ERR_TAG_OVERFLOW  = 32'h0000_0006;
  localparam logic [31:0] ERR_TAG_UNDERFLOW = 32'h0000_0007;
  localparam int ACC_COUNT_WIDTH = ACC_ADDR_WIDTH + 1;
  localparam int UB_CALC_WIDTH = UB_ADDR_WIDTH + 1;

  ctrl_state_t state_q;

  logic read_bank_q;
  logic write_bank_q;
  logic [UB_ADDR_WIDTH-1:0] input_base_addr_q;
  logic [UB_ADDR_WIDTH-1:0] output_base_addr_q;
  logic [ACC_ADDR_WIDTH:0] block_size_q;
  logic [TILE_COUNT_WIDTH-1:0] num_tiles_q;

  logic [ACC_ADDR_WIDTH:0] stream_idx_q;
  logic [ACC_ADDR_WIDTH:0] acc_read_idx_q;
  logic signed [DATA_WIDTH-1:0] act_lane0_q;
  logic signed [DATA_WIDTH-1:0] act_lane1_q;
  logic [SIZE-1:0] wgt_load_seen_q;
  logic signed [(OUT_WIDTH*SIZE)-1:0] vpu_data_q;

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

  logic [UB_ADDR_WIDTH:0] input_addr0_w;
  logic [UB_ADDR_WIDTH:0] input_addr1_w;
  logic [UB_ADDR_WIDTH:0] output_addr0_w;
  logic [UB_ADDR_WIDTH:0] output_addr1_w;

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

  assign input_addr0_w = {1'b0, input_base_addr_q}
                       + (UB_CALC_WIDTH'(stream_idx_q) * UB_CALC_WIDTH'(SIZE));
  assign input_addr1_w = input_addr0_w + UB_CALC_WIDTH'(1);

  assign output_addr0_w = {1'b0, output_base_addr_q}
                        + (UB_CALC_WIDTH'(acc_read_idx_q) * UB_CALC_WIDTH'(SIZE));
  assign output_addr1_w = output_addr0_w + UB_CALC_WIDTH'(1);

  always_comb begin
    all_rows_ready_w = (block_size_q != '0);
    for (int row = 0; row < ACC_DEPTH; row++) begin
      if (row < block_size_q) begin
        all_rows_ready_w &= accumulator_row_ready_i[row];
      end
    end
  end

  assign first_psum_valid_w = (|mxu_psum_valid_i) && !psum_packer_busy_i;
  assign tag_stream_active_w = (state_q == S_READ_ACT0_REQ)
                            || (state_q == S_READ_ACT0_WAIT)
                            || (state_q == S_READ_ACT1_REQ)
                            || (state_q == S_READ_ACT1_WAIT)
                            || (state_q == S_LAUNCH_ACT)
                            || (state_q == S_DRAIN_MXU)
                            || (state_q == S_WAIT_ACC_READY);
  assign tag_push_w      = (state_q == S_LAUNCH_ACT);
  assign tag_pop_w       = tag_stream_active_w && first_psum_valid_w;
  assign tag_overflow_w  = tag_push_w && (tag_count_q == TAG_COUNT_WIDTH'(TAG_DEPTH)) && !tag_pop_w;
  assign tag_underflow_w = tag_pop_w && (tag_count_q == '0);
  assign tag_front_w     = (tag_count_q != '0) ? tag_mem_q[tag_rd_ptr_q] : '0;

  assign accumulator_write_en_o   = tag_stream_active_w && ((tag_count_q != '0) || psum_packer_busy_i);
  assign accumulator_write_addr_o = tag_front_w;

  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE) && (state_q != S_ERROR);
  assign dbg_state_o = state_q;

  assign num_tiles_o                         = num_tiles_q;
  assign vpu_act_mode_o                      = act_mode_i;
  assign vpu_bias_flatten_o                  = bias_flatten_i;
  assign vpu_requant_multiplier_flatten_o    = requant_multiplier_flatten_i;
  assign vpu_requant_shift_flatten_o         = requant_shift_flatten_i;
  assign vpu_output_zero_point_o             = '0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      done_o <= 1'b0;
      error_o <= 1'b0;
      dbg_cycle_count_o <= '0;
      dbg_error_code_o <= '0;

      read_bank_q <= 1'b0;
      write_bank_q <= 1'b1;
      input_base_addr_q <= '0;
      output_base_addr_q <= '0;
      block_size_q <= '0;
      num_tiles_q <= TILE_COUNT_WIDTH'(1);
      stream_idx_q <= '0;
      acc_read_idx_q <= '0;
      act_lane0_q <= '0;
      act_lane1_q <= '0;
      wgt_load_seen_q <= '0;
      vpu_data_q <= '0;

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

      if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
        dbg_cycle_count_o <= dbg_cycle_count_o + 16'd1;
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
            done_o <= 1'b0;
            error_o <= 1'b0;
            dbg_error_code_o <= '0;

            if (start_i) begin
              dbg_cycle_count_o <= '0;

              if ((block_size_i == '0) || (block_size_i > ACC_COUNT_WIDTH'(ACC_DEPTH))) begin
                state_q <= S_ERROR;
                error_o <= 1'b1;
                dbg_error_code_o <= ERR_BLOCK_SIZE;
              end else if (num_tiles_i != TILE_COUNT_WIDTH'(1)) begin
                state_q <= S_ERROR;
                error_o <= 1'b1;
                dbg_error_code_o <= ERR_TILE_COUNT;
              end else begin
                read_bank_q <= read_bank_i;
                write_bank_q <= write_bank_i;
                input_base_addr_q <= input_base_addr_i;
                output_base_addr_q <= output_base_addr_i;
                block_size_q <= block_size_i;
                num_tiles_q <= num_tiles_i;
                stream_idx_q <= '0;
                acc_read_idx_q <= '0;
                wgt_load_seen_q <= '0;
                state_q <= S_CLEAR_ACC_BLOCK;
              end
            end
          end

          S_CLEAR_ACC_BLOCK: begin
            accumulator_clear_all_o <= 1'b1;
            state_q <= S_WRITE_WEIGHT_BOTTOM;
          end

          S_WRITE_WEIGHT_BOTTOM: begin
            if (wgt_fifo_full_i) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_WGT_FIFO_FULL;
            end else begin
              wgt_fifo_wdata_o <= weight_bottom_row_i;
              wgt_fifo_wr_en_o <= 1'b1;
              state_q <= S_WRITE_WEIGHT_TOP;
            end
          end

          S_WRITE_WEIGHT_TOP: begin
            if (wgt_fifo_full_i) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_WGT_FIFO_FULL;
            end else begin
              wgt_fifo_wdata_o <= weight_top_row_i;
              wgt_fifo_wr_en_o <= 1'b1;
              state_q <= S_START_WEIGHT_LOAD;
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
              state_q <= S_READ_ACT0_REQ;
            end
          end

          S_READ_ACT0_REQ: begin
            if (input_addr0_w >= UB_CALC_WIDTH'(BANK_DEPTH)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_INPUT_ADDR;
            end else begin
              ub_rd_en_o <= 1'b1;
              ub_rd_bank_o <= read_bank_q;
              ub_rd_addr_o <= input_addr0_w[UB_ADDR_WIDTH-1:0];
              state_q <= S_READ_ACT0_WAIT;
            end
          end

          S_READ_ACT0_WAIT: begin
            if (ub_rd_valid_i) begin
              act_lane0_q <= ub_rd_data_i;
              state_q <= S_READ_ACT1_REQ;
            end
          end

          S_READ_ACT1_REQ: begin
            if (input_addr1_w >= UB_CALC_WIDTH'(BANK_DEPTH)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_INPUT_ADDR;
            end else begin
              ub_rd_en_o <= 1'b1;
              ub_rd_bank_o <= read_bank_q;
              ub_rd_addr_o <= input_addr1_w[UB_ADDR_WIDTH-1:0];
              state_q <= S_READ_ACT1_WAIT;
            end
          end

          S_READ_ACT1_WAIT: begin
            if (ub_rd_valid_i) begin
              act_lane1_q <= ub_rd_data_i;
              state_q <= S_LAUNCH_ACT;
            end
          end

          S_LAUNCH_ACT: begin
            act_flat_raw_o <= {act_lane1_q, act_lane0_q};
            act_valid_raw_o <= {SIZE{1'b1}};
            work_o <= 1'b1;

            if ((stream_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              state_q <= S_DRAIN_MXU;
            end else begin
              stream_idx_q <= stream_idx_q + ACC_COUNT_WIDTH'(1);
              state_q <= S_READ_ACT0_REQ;
            end
          end

          S_DRAIN_MXU: begin
            if ((tag_count_q == '0) && !psum_packer_busy_i && !(|mxu_psum_valid_i)) begin
              state_q <= S_WAIT_ACC_READY;
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
              state_q <= S_WRITE_OUTPUT0;
            end
          end

          S_WRITE_OUTPUT0: begin
            if (output_addr0_w >= UB_CALC_WIDTH'(BANK_DEPTH)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_OUTPUT_ADDR;
            end else begin
              ub_wr_en_o <= 1'b1;
              ub_wr_bank_o <= write_bank_q;
              ub_wr_addr_o <= output_addr0_w[UB_ADDR_WIDTH-1:0];
              ub_wr_data_o <= vpu_data_q[(0*OUT_WIDTH)+:OUT_WIDTH];
              state_q <= S_WRITE_OUTPUT1;
            end
          end

          S_WRITE_OUTPUT1: begin
            if (output_addr1_w >= UB_CALC_WIDTH'(BANK_DEPTH)) begin
              state_q <= S_ERROR;
              error_o <= 1'b1;
              dbg_error_code_o <= ERR_OUTPUT_ADDR;
            end else begin
              ub_wr_en_o <= 1'b1;
              ub_wr_bank_o <= write_bank_q;
              ub_wr_addr_o <= output_addr1_w[UB_ADDR_WIDTH-1:0];
              ub_wr_data_o <= vpu_data_q[(1*OUT_WIDTH)+:OUT_WIDTH];

              if ((acc_read_idx_q + ACC_COUNT_WIDTH'(1)) >= block_size_q) begin
                state_q <= S_DONE;
              end else begin
                acc_read_idx_q <= acc_read_idx_q + ACC_COUNT_WIDTH'(1);
                state_q <= S_READ_ACC_ROW;
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

endmodule : tpu_controller

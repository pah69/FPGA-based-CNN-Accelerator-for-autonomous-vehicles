`timescale 1ns / 1ps

// V3 request-based controller for one accumulator row and one output-channel tile.
//
// This is the first controller bridge for the V3 datapath. It replaces the
// old FIFO/fetcher sequencing with explicit weight-tile and activation-vector
// requests. The scope is intentionally narrow: one spatial row in the
// accumulator, all K tiles for one OC tile, then one accumulator read into VPU.
module tpu_controller_v3_tile #(
    parameter int SIZE                = 2,
    parameter int ACT_ADDR_WIDTH      = 13,
    parameter int WGT_ADDR_WIDTH      = 16,
    parameter int TAG_WIDTH           = 16,
    parameter int ACC_DEPTH           = 16,
    parameter int ACC_ADDR_WIDTH      = (ACC_DEPTH > 1) ? $clog2(ACC_DEPTH) : 1,
    parameter int BIAS_WIDTH          = 32,
    parameter int REQUANT_MULT_WIDTH  = 32,
    parameter int REQUANT_SHIFT_WIDTH = 6,
    parameter int ACC_WIDTH           = 32,
    parameter int MAX_NUM_TILES       = 128,
    parameter int TILE_COUNT_WIDTH    = (MAX_NUM_TILES > 1) ? $clog2(MAX_NUM_TILES + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input  logic start_i,
    input  logic clear_i,
    output logic done_o,
    output logic busy_o,
    output logic error_o,
    output logic [4:0] dbg_state_o,
    output logic [15:0] dbg_k_tile_o,
    output logic [31:0] dbg_cycle_count_o,
    output logic [31:0] dbg_error_code_o,

    input logic [1:0] layer_type_i,
    input logic [ACT_ADDR_WIDTH-1:0] activation_base_addr_i,
    input logic [WGT_ADDR_WIDTH-1:0] weight_base_addr_i,
    input logic [15:0] in_h_i,
    input logic [15:0] in_w_i,
    input logic [15:0] out_w_i,
    input logic [15:0] out_ch_i,
    input logic [15:0] kernel_h_i,
    input logic [15:0] kernel_w_i,
    input logic [15:0] k_total_i,
    input logic [15:0] num_k_tiles_i,
    input logic [15:0] spatial_idx_i,
    input logic [15:0] oc_tile_idx_i,
    input logic [ACC_ADDR_WIDTH-1:0] accumulator_row_addr_i,

    output logic                                 wgt_req_valid_o,
    input  logic                                 wgt_req_ready_i,
    output logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0]  wgt_req_addr_flatten_o,
    output logic [SIZE*SIZE-1:0]                 wgt_req_valid_mask_o,
    output logic [SIZE*SIZE-1:0]                 wgt_req_zero_mask_o,
    output logic [TAG_WIDTH-1:0]                 wgt_req_tag_o,
    output logic                                 wgt_tile_release_o,
    output logic                                 wgt_stream_start_o,
    input  logic                                 wgt_tile_valid_i,
    input  logic [SIZE-1:0]                      wgt_load_done_i,

    output logic                           act_req_valid_o,
    input  logic                           act_req_ready_i,
    output logic [SIZE*ACT_ADDR_WIDTH-1:0] act_req_addr_flatten_o,
    output logic [SIZE-1:0]                act_req_lane_valid_o,
    output logic [SIZE-1:0]                act_req_lane_zero_o,
    output logic [TAG_WIDTH-1:0]           act_req_tag_o,
    input  logic                           act_launch_ready_i,
    output logic                           act_launch_o,

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
    input  logic                                         vpu_data_valid_i,

    input logic [SIZE-1:0] mxu_psum_valid_i,
    input logic            psum_packer_busy_i,

    input logic [1:0]                                  vpu_act_mode_i,
    input logic signed [(BIAS_WIDTH*SIZE)-1:0]         vpu_bias_flatten_i,
    input logic signed [(REQUANT_MULT_WIDTH*SIZE)-1:0] vpu_requant_multiplier_flatten_i,
    input logic [(REQUANT_SHIFT_WIDTH*SIZE)-1:0]       vpu_requant_shift_flatten_i,
    input logic signed [ACC_WIDTH-1:0]                 vpu_output_zero_point_i
);

  typedef enum logic [4:0] {
    S_IDLE,
    S_CLEAR_ACC,
    S_SEND_WGT_REQ,
    S_WAIT_WGT_TILE,
    S_STREAM_WGT,
    S_WAIT_WGT_LOAD,
    S_PREFETCH_WGT_REQ,
    S_SEND_ACT_REQ,
    S_WAIT_ACT_READY,
    S_LAUNCH_ACT,
    S_WAIT_PSUM,
    S_RELEASE_WGT,
    S_NEXT_K_TILE,
    S_RELEASE_FINAL_WGT,
    S_WAIT_ACC_READY,
    S_READ_ACC,
    S_WAIT_ACC_READ,
    S_WAIT_VPU,
    S_DONE,
    S_ERROR
  } state_t;

  localparam logic [31:0] ERR_SIZE      = 32'h0003_0001;
  localparam logic [31:0] ERR_TILE_CNT  = 32'h0003_0002;
  localparam logic [31:0] ERR_K_TOTAL   = 32'h0003_0003;
  localparam logic [31:0] ERR_OC_TILE   = 32'h0003_0004;
  localparam int AG_ADDR_WIDTH = (WGT_ADDR_WIDTH > ACT_ADDR_WIDTH) ? WGT_ADDR_WIDTH : ACT_ADDR_WIDTH;

  state_t state_q;
  state_t state_d;

  logic [1:0] layer_type_q;
  logic [ACT_ADDR_WIDTH-1:0] activation_base_addr_q;
  logic [WGT_ADDR_WIDTH-1:0] weight_base_addr_q;
  logic [15:0] in_h_q;
  logic [15:0] in_w_q;
  logic [15:0] out_w_q;
  logic [15:0] out_ch_q;
  logic [15:0] kernel_h_q;
  logic [15:0] kernel_w_q;
  logic [15:0] k_total_q;
  logic [15:0] num_k_tiles_q;
  logic [15:0] spatial_idx_q;
  logic [15:0] oc_tile_idx_q;
  logic [ACC_ADDR_WIDTH-1:0] accumulator_row_addr_q;

  logic [15:0] k_tile_q;
  logic prefetch_valid_q;
  logic act_req_issued_q;
  logic next_act_req_issued_q;
  logic [SIZE-1:0] wgt_load_seen_q;
  logic [SIZE-1:0] psum_seen_q;

  logic [AG_ADDR_WIDTH*SIZE-1:0] ag_act_addr_flatten_w;
  logic [SIZE-1:0] ag_act_valid_w;
  logic [SIZE-1:0] ag_act_zero_w;
  logic [AG_ADDR_WIDTH*SIZE*SIZE-1:0] ag_weight_addr_flatten_w;
  logic [SIZE*SIZE-1:0] ag_weight_valid_w;
  logic [SIZE*SIZE-1:0] ag_weight_zero_w;
  logic [16*SIZE-1:0] ag_k_index_flatten_unused_w;
  logic [16*SIZE-1:0] ag_oc_index_flatten_unused_w;

  logic last_k_tile_w;
  logic all_psums_seen_w;
  logic row_ready_w;
  logic [15:0] wgt_req_k_tile_w;
  logic [15:0] act_req_k_tile_w;
  logic [15:0] addrgen_k_tile_w;
  logic prefetch_act_req_w;
  logic [SIZE*ACT_ADDR_WIDTH-1:0] act_req_addr_flatten_w;
  logic [SIZE*SIZE*WGT_ADDR_WIDTH-1:0] wgt_req_addr_flatten_w;

  assign prefetch_act_req_w =
      (state_q == S_WAIT_PSUM) && !last_k_tile_w && !next_act_req_issued_q;
  assign wgt_req_k_tile_w =
      (state_q == S_PREFETCH_WGT_REQ) ? (k_tile_q + 16'd1) : k_tile_q;
  assign act_req_k_tile_w = prefetch_act_req_w ? (k_tile_q + 16'd1) : k_tile_q;
  assign addrgen_k_tile_w =
      (state_q == S_PREFETCH_WGT_REQ) ? (k_tile_q + 16'd1)
                                      : (prefetch_act_req_w ? (k_tile_q + 16'd1) : k_tile_q);

  conv_fc_address_generator #(
      .SIZE      (SIZE),
      .ADDR_WIDTH(AG_ADDR_WIDTH),
      .DIM_WIDTH (16),
      .CALC_WIDTH(32)
  ) u_address_generator (
      .layer_type_i          (layer_type_q),
      .activation_base_addr_i(AG_ADDR_WIDTH'(activation_base_addr_q)),
      .weight_base_addr_i    (AG_ADDR_WIDTH'(weight_base_addr_q)),
      .in_h_i                (in_h_q),
      .in_w_i                (in_w_q),
      .out_w_i               (out_w_q),
      .out_ch_i              (out_ch_q),
      .kernel_h_i            (kernel_h_q),
      .kernel_w_i            (kernel_w_q),
      .k_total_i             (k_total_q),
      .spatial_idx_i         (spatial_idx_q),
      .k_tile_idx_i          (addrgen_k_tile_w),
      .oc_tile_idx_i         (oc_tile_idx_q),
      .act_addr_flatten_o    (ag_act_addr_flatten_w),
      .act_valid_o           (ag_act_valid_w),
      .act_zero_o            (ag_act_zero_w),
      .weight_addr_flatten_o (ag_weight_addr_flatten_w),
      .weight_valid_o        (ag_weight_valid_w),
      .weight_zero_o         (ag_weight_zero_w),
      .k_index_flatten_o     (ag_k_index_flatten_unused_w),
      .oc_index_flatten_o    (ag_oc_index_flatten_unused_w)
  );

  assign last_k_tile_w = ((k_tile_q + 16'd1) >= num_k_tiles_q);
  assign all_psums_seen_w = &psum_seen_q;
  assign row_ready_w = accumulator_row_ready_i[accumulator_row_addr_q];

  always_comb begin
    act_req_addr_flatten_w = '0;
    for (int lane = 0; lane < SIZE; lane++) begin
      act_req_addr_flatten_w[(lane*ACT_ADDR_WIDTH)+:ACT_ADDR_WIDTH] =
          ACT_ADDR_WIDTH'(ag_act_addr_flatten_w[(lane*AG_ADDR_WIDTH)+:AG_ADDR_WIDTH]);
    end
  end

  always_comb begin
    wgt_req_addr_flatten_w = '0;
    for (int elem = 0; elem < SIZE * SIZE; elem++) begin
      wgt_req_addr_flatten_w[(elem*WGT_ADDR_WIDTH)+:WGT_ADDR_WIDTH] =
          WGT_ADDR_WIDTH'(ag_weight_addr_flatten_w[(elem*AG_ADDR_WIDTH)+:AG_ADDR_WIDTH]);
    end
  end

  always_comb begin
    state_d = state_q;

    unique case (state_q)
      S_IDLE: begin
        if (start_i) begin
          state_d = S_CLEAR_ACC;
        end
      end

      S_CLEAR_ACC: begin
        if (SIZE != 2) begin
          state_d = S_ERROR;
        end else if (num_k_tiles_i == 16'd0 || num_k_tiles_i > 16'(MAX_NUM_TILES)) begin
          state_d = S_ERROR;
        end else if (k_total_i == 16'd0) begin
          state_d = S_ERROR;
        end else if ((oc_tile_idx_i * 16'(SIZE)) >= out_ch_i) begin
          state_d = S_ERROR;
        end else begin
          state_d = S_SEND_WGT_REQ;
        end
      end

      S_SEND_WGT_REQ: begin
        if (wgt_req_ready_i) begin
          state_d = S_WAIT_WGT_TILE;
        end
      end

      S_WAIT_WGT_TILE: begin
        if (wgt_tile_valid_i) begin
          state_d = S_STREAM_WGT;
        end
      end

      S_STREAM_WGT: begin
        state_d = S_WAIT_WGT_LOAD;
      end

      S_WAIT_WGT_LOAD: begin
        if (&(wgt_load_seen_q | wgt_load_done_i)) begin
          if (last_k_tile_w) begin
            state_d = act_req_issued_q ? S_WAIT_ACT_READY : S_SEND_ACT_REQ;
          end else begin
            state_d = S_PREFETCH_WGT_REQ;
          end
        end
      end

      S_PREFETCH_WGT_REQ: begin
        if (wgt_req_ready_i) begin
          state_d = act_req_issued_q ? S_WAIT_ACT_READY : S_SEND_ACT_REQ;
        end
      end

      S_SEND_ACT_REQ: begin
        if (act_req_ready_i) begin
          state_d = S_WAIT_ACT_READY;
        end
      end

      S_WAIT_ACT_READY: begin
        if (act_launch_ready_i) begin
          state_d = S_LAUNCH_ACT;
        end
      end

      S_LAUNCH_ACT: begin
        state_d = S_WAIT_PSUM;
      end

      S_WAIT_PSUM: begin
        if (all_psums_seen_w && !psum_packer_busy_i && (mxu_psum_valid_i == '0)) begin
          state_d = last_k_tile_w ? S_RELEASE_FINAL_WGT : S_RELEASE_WGT;
        end
      end

      S_RELEASE_WGT: begin
        state_d = S_NEXT_K_TILE;
      end

      S_NEXT_K_TILE: begin
        state_d = prefetch_valid_q ? S_WAIT_WGT_TILE : S_SEND_WGT_REQ;
      end

      S_RELEASE_FINAL_WGT: begin
        state_d = S_WAIT_ACC_READY;
      end

      S_WAIT_ACC_READY: begin
        if (row_ready_w) begin
          state_d = S_READ_ACC;
        end
      end

      S_READ_ACC: begin
        state_d = S_WAIT_ACC_READ;
      end

      S_WAIT_ACC_READ: begin
        if (accumulator_read_valid_i) begin
          state_d = S_WAIT_VPU;
        end
      end

      S_WAIT_VPU: begin
        if (vpu_data_valid_i) begin
          state_d = S_DONE;
        end
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
      layer_type_q <= '0;
      activation_base_addr_q <= '0;
      weight_base_addr_q <= '0;
      in_h_q <= '0;
      in_w_q <= '0;
      out_w_q <= '0;
      out_ch_q <= '0;
      kernel_h_q <= '0;
      kernel_w_q <= '0;
      k_total_q <= '0;
      num_k_tiles_q <= '0;
      spatial_idx_q <= '0;
      oc_tile_idx_q <= '0;
      accumulator_row_addr_q <= '0;
      k_tile_q <= '0;
      prefetch_valid_q <= 1'b0;
      act_req_issued_q <= 1'b0;
      next_act_req_issued_q <= 1'b0;
      wgt_load_seen_q <= '0;
      psum_seen_q <= '0;
    end else begin
      state_q <= state_d;
      done_o <= 1'b0;

      if (clear_i) begin
        error_o <= 1'b0;
        dbg_cycle_count_o <= '0;
        dbg_error_code_o <= '0;
        k_tile_q <= '0;
        prefetch_valid_q <= 1'b0;
        act_req_issued_q <= 1'b0;
        next_act_req_issued_q <= 1'b0;
        wgt_load_seen_q <= '0;
        psum_seen_q <= '0;
      end else begin
        if (state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR) begin
          dbg_cycle_count_o <= dbg_cycle_count_o + 32'd1;
        end

        if (state_q == S_IDLE && start_i) begin
          error_o <= 1'b0;
          dbg_cycle_count_o <= '0;
          dbg_error_code_o <= '0;
          layer_type_q <= layer_type_i;
          activation_base_addr_q <= activation_base_addr_i;
          weight_base_addr_q <= weight_base_addr_i;
          in_h_q <= in_h_i;
          in_w_q <= in_w_i;
          out_w_q <= out_w_i;
          out_ch_q <= out_ch_i;
          kernel_h_q <= kernel_h_i;
          kernel_w_q <= kernel_w_i;
          k_total_q <= k_total_i;
          num_k_tiles_q <= num_k_tiles_i;
          spatial_idx_q <= spatial_idx_i;
          oc_tile_idx_q <= oc_tile_idx_i;
          accumulator_row_addr_q <= accumulator_row_addr_i;
          k_tile_q <= '0;
          prefetch_valid_q <= 1'b0;
          act_req_issued_q <= 1'b0;
          next_act_req_issued_q <= 1'b0;
          wgt_load_seen_q <= '0;
          psum_seen_q <= '0;
        end

        if (state_q == S_CLEAR_ACC) begin
          if (SIZE != 2) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_SIZE;
          end else if (num_k_tiles_i == 16'd0 || num_k_tiles_i > 16'(MAX_NUM_TILES)) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_TILE_CNT;
          end else if (k_total_i == 16'd0) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_K_TOTAL;
          end else if ((oc_tile_idx_i * 16'(SIZE)) >= out_ch_i) begin
            error_o <= 1'b1;
            dbg_error_code_o <= ERR_OC_TILE;
          end
        end

        if (state_q == S_SEND_WGT_REQ && wgt_req_ready_i) begin
          wgt_load_seen_q <= '0;
        end else if (state_q == S_PREFETCH_WGT_REQ && wgt_req_ready_i) begin
          prefetch_valid_q <= 1'b1;
        end else if (state_q == S_WAIT_WGT_LOAD) begin
          wgt_load_seen_q <= wgt_load_seen_q | wgt_load_done_i;
        end

        if (state_q == S_SEND_ACT_REQ && act_req_ready_i) begin
          act_req_issued_q <= 1'b1;
          psum_seen_q <= '0;
        end else if (prefetch_act_req_w && act_req_ready_i) begin
          next_act_req_issued_q <= 1'b1;
        end else if (state_q == S_WAIT_PSUM) begin
          psum_seen_q <= psum_seen_q | mxu_psum_valid_i;
        end

        if (state_q == S_NEXT_K_TILE) begin
          k_tile_q <= k_tile_q + 16'd1;
          wgt_load_seen_q <= '0;
          psum_seen_q <= '0;
          act_req_issued_q <= next_act_req_issued_q;
          next_act_req_issued_q <= 1'b0;
          if (prefetch_valid_q) begin
            prefetch_valid_q <= 1'b0;
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
  assign dbg_k_tile_o = k_tile_q;

  assign wgt_req_valid_o = (state_q == S_SEND_WGT_REQ) || (state_q == S_PREFETCH_WGT_REQ);
  assign wgt_req_addr_flatten_o = wgt_req_addr_flatten_w;
  assign wgt_req_valid_mask_o = ag_weight_valid_w;
  assign wgt_req_zero_mask_o = ag_weight_zero_w;
  assign wgt_req_tag_o = TAG_WIDTH'(16'h3000 + wgt_req_k_tile_w);
  assign wgt_tile_release_o = (state_q == S_RELEASE_WGT) || (state_q == S_RELEASE_FINAL_WGT);
  assign wgt_stream_start_o = (state_q == S_STREAM_WGT);

  assign act_req_valid_o = (state_q == S_SEND_ACT_REQ) || prefetch_act_req_w;
  assign act_req_addr_flatten_o = act_req_addr_flatten_w;
  assign act_req_lane_valid_o = ag_act_valid_w;
  assign act_req_lane_zero_o = ag_act_zero_w;
  assign act_req_tag_o = TAG_WIDTH'(16'h4000 + act_req_k_tile_w);
  assign act_launch_o = (state_q == S_LAUNCH_ACT);

  assign accumulator_clear_all_o = (state_q == S_CLEAR_ACC);
  assign accumulator_row_clear_o = 1'b0;
  assign accumulator_row_clear_addr_o = accumulator_row_addr_q;
  assign accumulator_write_en_o = (state_q == S_LAUNCH_ACT) || (state_q == S_WAIT_PSUM);
  assign accumulator_write_addr_o = accumulator_row_addr_q;
  assign accumulator_read_en_o = (state_q == S_READ_ACC);
  assign accumulator_read_addr_o = accumulator_row_addr_q;

  assign vpu_input_done_o = (state_q == S_WAIT_ACC_READ);
  assign vpu_act_mode_o = vpu_act_mode_i;
  assign vpu_bias_flatten_o = vpu_bias_flatten_i;
  assign vpu_requant_multiplier_flatten_o = vpu_requant_multiplier_flatten_i;
  assign vpu_requant_shift_flatten_o = vpu_requant_shift_flatten_i;
  assign vpu_output_zero_point_o = vpu_output_zero_point_i;

endmodule : tpu_controller_v3_tile

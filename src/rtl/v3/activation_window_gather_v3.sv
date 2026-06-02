`timescale 1ns / 1ps

// V3 activation prefetch/gather block.
//
// The controller/address generator submits one activation-vector request at a
// time. This block serializes the unified-buffer reads for the vector lanes,
// substitutes zero for padded lanes, and stores completed vectors in a small
// FIFO so the downstream MXU can consume them with ready/valid flow control.
module activation_window_gather_v3 #(
    parameter int ARRAY_K        = 2,
    parameter int DATA_WIDTH     = 8,
    parameter int ADDR_WIDTH     = 13,
    parameter int TAG_WIDTH      = 16,
    parameter int FIFO_DEPTH     = 4,
    parameter int COUNTER_WIDTH  = 32,
    parameter int LANE_IDX_WIDTH = (ARRAY_K > 1) ? $clog2(ARRAY_K + 1) : 1,
    parameter int FIFO_PTR_WIDTH = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH) : 1,
    parameter int FIFO_CNT_WIDTH = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,

    input  logic                             req_valid_i,
    output logic                             req_ready_o,
    input  logic [ARRAY_K*ADDR_WIDTH-1:0]    req_addr_flatten_i,
    input  logic [ARRAY_K-1:0]               req_lane_valid_i,
    input  logic [ARRAY_K-1:0]               req_lane_zero_i,
    input  logic [TAG_WIDTH-1:0]             req_tag_i,

    output logic                             ub_rd_en_o,
    output logic [ADDR_WIDTH-1:0]            ub_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0]     ub_rd_data_i,
    input  logic                             ub_rd_valid_i,

    output logic signed [ARRAY_K*DATA_WIDTH-1:0] act_vec_flatten_o,
    output logic [ARRAY_K-1:0]                    act_valid_o,
    output logic [TAG_WIDTH-1:0]                  act_tag_o,
    output logic                                  act_vec_valid_o,
    input  logic                                  act_vec_ready_i,

    output logic busy_o,
    output logic fifo_full_o,
    output logic fifo_empty_o,

    output logic [COUNTER_WIDTH-1:0] dbg_fetch_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_output_stall_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_vectors_pushed_o,
    output logic [COUNTER_WIDTH-1:0] dbg_lane_reads_o
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_NEXT_LANE,
    S_READ_REQ,
    S_READ_WAIT,
    S_PUSH
  } state_t;

  state_t state_q;

  logic [ARRAY_K*ADDR_WIDTH-1:0] addr_flatten_q;
  logic [ARRAY_K-1:0] lane_valid_q;
  logic [ARRAY_K-1:0] lane_zero_q;
  logic [TAG_WIDTH-1:0] tag_q;
  logic [LANE_IDX_WIDTH-1:0] lane_idx_q;
  logic signed [ARRAY_K*DATA_WIDTH-1:0] vec_flatten_q;
  logic [ARRAY_K-1:0] vec_valid_q;

  logic signed [ARRAY_K*DATA_WIDTH-1:0] fifo_vec_q[0:FIFO_DEPTH-1];
  logic [ARRAY_K-1:0] fifo_valid_q[0:FIFO_DEPTH-1];
  logic [TAG_WIDTH-1:0] fifo_tag_q[0:FIFO_DEPTH-1];
  logic [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr_q;
  logic [FIFO_PTR_WIDTH-1:0] fifo_rd_ptr_q;
  logic [FIFO_CNT_WIDTH-1:0] fifo_count_q;

  logic fifo_push_w;
  logic fifo_pop_w;
  logic fifo_full_w;
  logic fifo_empty_w;
  logic lane_done_w;
  logic lane_needs_read_w;

  function automatic logic [FIFO_PTR_WIDTH-1:0] next_fifo_ptr(
      input logic [FIFO_PTR_WIDTH-1:0] ptr_i);
    if (FIFO_DEPTH == 1) begin
      next_fifo_ptr = '0;
    end else if (ptr_i == FIFO_PTR_WIDTH'(FIFO_DEPTH - 1)) begin
      next_fifo_ptr = '0;
    end else begin
      next_fifo_ptr = ptr_i + FIFO_PTR_WIDTH'(1);
    end
  endfunction

  assign fifo_full_w = (fifo_count_q == FIFO_CNT_WIDTH'(FIFO_DEPTH));
  assign fifo_empty_w = (fifo_count_q == '0);
  assign fifo_full_o = fifo_full_w;
  assign fifo_empty_o = fifo_empty_w;

  assign req_ready_o = (state_q == S_IDLE) && !fifo_full_w;
  assign busy_o = (state_q != S_IDLE) || !fifo_empty_w;

  assign act_vec_valid_o = !fifo_empty_w;
  assign act_vec_flatten_o = fifo_vec_q[fifo_rd_ptr_q];
  assign act_valid_o = fifo_valid_q[fifo_rd_ptr_q];
  assign act_tag_o = fifo_tag_q[fifo_rd_ptr_q];

  assign fifo_push_w = (state_q == S_PUSH) && !fifo_full_w;
  assign fifo_pop_w = act_vec_valid_o && act_vec_ready_i;
  assign lane_done_w = (lane_idx_q >= LANE_IDX_WIDTH'(ARRAY_K));

  always_comb begin
    lane_needs_read_w = 1'b0;
    if (!lane_done_w) begin
      lane_needs_read_w = lane_valid_q[lane_idx_q] && !lane_zero_q[lane_idx_q];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      addr_flatten_q <= '0;
      lane_valid_q <= '0;
      lane_zero_q <= '0;
      tag_q <= '0;
      lane_idx_q <= '0;
      vec_flatten_q <= '0;
      vec_valid_q <= '0;
      fifo_wr_ptr_q <= '0;
      fifo_rd_ptr_q <= '0;
      fifo_count_q <= '0;
      ub_rd_en_o <= 1'b0;
      ub_rd_addr_o <= '0;
      dbg_fetch_cycles_o <= '0;
      dbg_output_stall_cycles_o <= '0;
      dbg_vectors_pushed_o <= '0;
      dbg_lane_reads_o <= '0;

      for (int idx = 0; idx < FIFO_DEPTH; idx++) begin
        fifo_vec_q[idx] <= '0;
        fifo_valid_q[idx] <= '0;
        fifo_tag_q[idx] <= '0;
      end
    end else begin
      ub_rd_en_o <= 1'b0;

      if (clear_i) begin
        state_q <= S_IDLE;
        addr_flatten_q <= '0;
        lane_valid_q <= '0;
        lane_zero_q <= '0;
        tag_q <= '0;
        lane_idx_q <= '0;
        vec_flatten_q <= '0;
        vec_valid_q <= '0;
        fifo_wr_ptr_q <= '0;
        fifo_rd_ptr_q <= '0;
        fifo_count_q <= '0;
        dbg_fetch_cycles_o <= '0;
        dbg_output_stall_cycles_o <= '0;
        dbg_vectors_pushed_o <= '0;
        dbg_lane_reads_o <= '0;
      end else begin
        if ((state_q != S_IDLE) && (state_q != S_PUSH)) begin
          dbg_fetch_cycles_o <= dbg_fetch_cycles_o + COUNTER_WIDTH'(1);
        end

        if ((state_q == S_PUSH) && fifo_full_w) begin
          dbg_output_stall_cycles_o <= dbg_output_stall_cycles_o + COUNTER_WIDTH'(1);
        end

        if (act_vec_valid_o && !act_vec_ready_i) begin
          dbg_output_stall_cycles_o <= dbg_output_stall_cycles_o + COUNTER_WIDTH'(1);
        end

        unique case ({fifo_push_w, fifo_pop_w})
          2'b10: begin
            fifo_vec_q[fifo_wr_ptr_q] <= vec_flatten_q;
            fifo_valid_q[fifo_wr_ptr_q] <= vec_valid_q;
            fifo_tag_q[fifo_wr_ptr_q] <= tag_q;
            fifo_wr_ptr_q <= next_fifo_ptr(fifo_wr_ptr_q);
            fifo_count_q <= fifo_count_q + FIFO_CNT_WIDTH'(1);
            dbg_vectors_pushed_o <= dbg_vectors_pushed_o + COUNTER_WIDTH'(1);
          end

          2'b01: begin
            fifo_rd_ptr_q <= next_fifo_ptr(fifo_rd_ptr_q);
            fifo_count_q <= fifo_count_q - FIFO_CNT_WIDTH'(1);
          end

          2'b11: begin
            fifo_vec_q[fifo_wr_ptr_q] <= vec_flatten_q;
            fifo_valid_q[fifo_wr_ptr_q] <= vec_valid_q;
            fifo_tag_q[fifo_wr_ptr_q] <= tag_q;
            fifo_wr_ptr_q <= next_fifo_ptr(fifo_wr_ptr_q);
            fifo_rd_ptr_q <= next_fifo_ptr(fifo_rd_ptr_q);
            dbg_vectors_pushed_o <= dbg_vectors_pushed_o + COUNTER_WIDTH'(1);
          end

          default: begin
          end
        endcase

        unique case (state_q)
          S_IDLE: begin
            if (req_valid_i && req_ready_o) begin
              addr_flatten_q <= req_addr_flatten_i;
              lane_valid_q <= req_lane_valid_i;
              lane_zero_q <= req_lane_zero_i;
              tag_q <= req_tag_i;
              lane_idx_q <= '0;
              vec_flatten_q <= '0;
              vec_valid_q <= '0;

              vec_valid_q[0] <= req_lane_valid_i[0];
              if (req_lane_valid_i[0] && !req_lane_zero_i[0]) begin
                ub_rd_en_o <= 1'b1;
                ub_rd_addr_o <= req_addr_flatten_i[0+:ADDR_WIDTH];
                dbg_lane_reads_o <= dbg_lane_reads_o + COUNTER_WIDTH'(1);
                state_q <= S_READ_WAIT;
              end else begin
                vec_flatten_q[0+:DATA_WIDTH] <= '0;
                lane_idx_q <= LANE_IDX_WIDTH'(1);
                state_q <= S_NEXT_LANE;
              end
            end
          end

          S_NEXT_LANE: begin
            if (lane_done_w) begin
              state_q <= S_PUSH;
            end else begin
              vec_valid_q[lane_idx_q] <= lane_valid_q[lane_idx_q];
              if (lane_needs_read_w) begin
                ub_rd_en_o <= 1'b1;
                ub_rd_addr_o <= addr_flatten_q[(lane_idx_q*ADDR_WIDTH)+:ADDR_WIDTH];
                dbg_lane_reads_o <= dbg_lane_reads_o + COUNTER_WIDTH'(1);
                state_q <= S_READ_WAIT;
              end else begin
                vec_flatten_q[(lane_idx_q*DATA_WIDTH)+:DATA_WIDTH] <= '0;
                lane_idx_q <= lane_idx_q + LANE_IDX_WIDTH'(1);
              end
            end
          end

          S_READ_REQ: begin
            ub_rd_en_o <= 1'b1;
            ub_rd_addr_o <= addr_flatten_q[(lane_idx_q*ADDR_WIDTH)+:ADDR_WIDTH];
            dbg_lane_reads_o <= dbg_lane_reads_o + COUNTER_WIDTH'(1);
            state_q <= S_READ_WAIT;
          end

          S_READ_WAIT: begin
            if (ub_rd_valid_i) begin
              vec_flatten_q[(lane_idx_q*DATA_WIDTH)+:DATA_WIDTH] <= ub_rd_data_i;
              lane_idx_q <= lane_idx_q + LANE_IDX_WIDTH'(1);
              state_q <= S_NEXT_LANE;
            end
          end

          S_PUSH: begin
            if (!fifo_full_w) begin
              state_q <= S_IDLE;
            end
          end

          default: begin
            state_q <= S_IDLE;
          end
        endcase
      end
    end
  end

endmodule : activation_window_gather_v3

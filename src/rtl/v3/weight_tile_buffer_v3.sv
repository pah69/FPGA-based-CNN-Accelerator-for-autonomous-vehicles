`timescale 1ns / 1ps

// V3 weight tile buffer.
//
// The address generator provides a full K-lane by output-channel-lane tile as
// flattened ROM addresses plus valid/zero masks. This block serially fetches
// the required weights from the ROM, stores complete tiles locally, and can
// stream the active tile rows into the weight-stationary systolic array.
//
// V3 overlap baseline:
//   - one slot is active for streaming into the WS array
//   - the other slot can be filled from ROM for the next K tile
//   - tile_release_i retires only the active slot and promotes a prefetched
//     slot when one is ready
//
// Tiles are stored row-major, but streamed bottom-row first because weights
// move downward through the WS array during load.
module weight_tile_buffer_v3 #(
    parameter int ARRAY_K        = 2,
    parameter int ARRAY_OC       = 2,
    parameter int DATA_WIDTH     = 8,
    parameter int ADDR_WIDTH     = 16,
    parameter int TAG_WIDTH      = 16,
    parameter int COUNTER_WIDTH  = 32,
    parameter int CACHE_DEPTH    = 256,
    parameter int TILE_ELEMS     = ARRAY_K * ARRAY_OC,
    parameter int ELEM_IDX_WIDTH = (TILE_ELEMS > 1) ? $clog2(TILE_ELEMS + 1) : 1,
    parameter int ROW_IDX_WIDTH  = (ARRAY_K > 1) ? $clog2(ARRAY_K + 1) : 1,
    parameter int CACHE_IDX_WIDTH = (CACHE_DEPTH > 1) ? $clog2(CACHE_DEPTH) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic clear_i,
    input logic tile_release_i,

    input  logic                             req_valid_i,
    output logic                             req_ready_o,
    input  logic [TILE_ELEMS*ADDR_WIDTH-1:0] req_addr_flatten_i,
    input  logic [TILE_ELEMS-1:0]            req_weight_valid_i,
    input  logic [TILE_ELEMS-1:0]            req_weight_zero_i,
    input  logic [TAG_WIDTH-1:0]             req_tag_i,

    output logic                         weight_rd_en_o,
    output logic [ADDR_WIDTH-1:0]        weight_rd_addr_o,
    input  logic signed [DATA_WIDTH-1:0] weight_rd_data_i,
    input  logic                         weight_rd_valid_i,

    output logic signed [TILE_ELEMS*DATA_WIDTH-1:0] tile_flatten_o,
    output logic [TILE_ELEMS-1:0]                   tile_valid_mask_o,
    output logic [TAG_WIDTH-1:0]                    tile_tag_o,
    output logic                                    tile_valid_o,

    input  logic                             stream_start_i,
    output logic                             stream_ready_o,
    output logic signed [ARRAY_OC*DATA_WIDTH-1:0] wgt_row_flatten_o,
    output logic [ARRAY_OC-1:0]                    wgt_row_load_o,
    output logic                                  weight_switch_o,
    output logic                                  stream_done_o,

    output logic busy_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_load_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_reuse_count_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_empty_cycles_o,
    output logic [COUNTER_WIDTH-1:0] dbg_weight_buffer_full_cycles_o
);

  typedef enum logic [1:0] {
    F_IDLE,
    F_SCAN,
    F_WAIT
  } fill_state_t;

  typedef enum logic [1:0] {
    S_IDLE,
    S_ROW,
    S_SWITCH
  } stream_state_t;

  fill_state_t fill_state_q;
  stream_state_t stream_state_q;

  logic [TILE_ELEMS*ADDR_WIDTH-1:0] addr_flatten_q;
  logic [TILE_ELEMS-1:0] valid_mask_q[0:1];
  logic [TILE_ELEMS-1:0] zero_mask_q;
  logic [TAG_WIDTH-1:0] tag_q[0:1];
  logic [ELEM_IDX_WIDTH-1:0] elem_idx_q;
  logic [ROW_IDX_WIDTH-1:0] row_idx_q;
  logic [ROW_IDX_WIDTH-1:0] stream_row_idx_w;
  logic [1:0] slot_valid_q;
  logic active_slot_q;
  logic fill_slot_q;
  logic signed [DATA_WIDTH-1:0] tile_mem_q[0:1][0:TILE_ELEMS-1];
  logic [CACHE_DEPTH-1:0] cache_valid_q;
  logic [CACHE_IDX_WIDTH-1:0] cache_wr_idx_q;
  logic [CACHE_IDX_WIDTH-1:0] cache_hit_idx_w;
  logic [TILE_ELEMS*ADDR_WIDTH-1:0] cache_addr_flatten_q[0:CACHE_DEPTH-1];
  logic [TILE_ELEMS-1:0] cache_valid_mask_q[0:CACHE_DEPTH-1];
  logic [TILE_ELEMS-1:0] cache_zero_mask_q[0:CACHE_DEPTH-1];
  logic signed [DATA_WIDTH-1:0] cache_tile_mem_q[0:CACHE_DEPTH-1][0:TILE_ELEMS-1];

  logic elem_in_range_w;
  logic elem_needs_read_w;
  logic cache_hit_w;
  logic fill_busy_w;
  logic stream_busy_w;
  logic accept_req_w;
  logic accept_stream_w;
  logic free_slot_available_w;
  logic selected_fill_slot_w;
  logic other_slot_w;
  logic active_tile_valid_w;
  logic fill_completes_w;

  assign fill_busy_w = (fill_state_q != F_IDLE);
  assign stream_busy_w = (stream_state_q != S_IDLE);
  assign accept_req_w = req_valid_i && req_ready_o;
  assign accept_stream_w = stream_start_i && stream_ready_o;
  assign free_slot_available_w = (slot_valid_q != 2'b11);
  assign selected_fill_slot_w = slot_valid_q[active_slot_q] ? ~active_slot_q : active_slot_q;
  assign other_slot_w = ~active_slot_q;
  assign active_tile_valid_w = slot_valid_q[active_slot_q];
  assign fill_completes_w = (fill_state_q == F_SCAN) && (elem_idx_q == ELEM_IDX_WIDTH'(TILE_ELEMS));

  assign req_ready_o = (fill_state_q == F_IDLE) && free_slot_available_w;
  assign stream_ready_o = active_tile_valid_w && (stream_state_q == S_IDLE);
  assign tile_valid_o = active_tile_valid_w;
  assign tile_valid_mask_o = valid_mask_q[active_slot_q];
  assign tile_tag_o = tag_q[active_slot_q];
  assign busy_o = fill_busy_w || stream_busy_w;

  assign weight_switch_o = (stream_state_q == S_SWITCH);
  assign stream_done_o = (stream_state_q == S_SWITCH);

  always_comb begin
    cache_hit_w = 1'b0;
    cache_hit_idx_w = '0;

    for (int entry = 0; entry < CACHE_DEPTH; entry++) begin
      if (cache_valid_q[entry]
          && (cache_addr_flatten_q[entry] == req_addr_flatten_i)
          && (cache_valid_mask_q[entry] == req_weight_valid_i)
          && (cache_zero_mask_q[entry] == req_weight_zero_i)
          && !cache_hit_w) begin
        cache_hit_w = 1'b1;
        cache_hit_idx_w = CACHE_IDX_WIDTH'(entry);
      end
    end
  end

  always_comb begin
    elem_in_range_w = (elem_idx_q < ELEM_IDX_WIDTH'(TILE_ELEMS));
    elem_needs_read_w = 1'b0;
    if (elem_in_range_w) begin
      elem_needs_read_w = valid_mask_q[fill_slot_q][elem_idx_q] && !zero_mask_q[elem_idx_q];
    end
  end

  always_comb begin
    tile_flatten_o = '0;
    for (int elem = 0; elem < TILE_ELEMS; elem++) begin
      tile_flatten_o[(elem*DATA_WIDTH)+:DATA_WIDTH] = tile_mem_q[active_slot_q][elem];
    end
  end

  always_comb begin
    wgt_row_flatten_o = '0;
    wgt_row_load_o = '0;
    stream_row_idx_w = ROW_IDX_WIDTH'(ARRAY_K - 1) - row_idx_q;

    if (stream_state_q == S_ROW) begin
      wgt_row_load_o = {ARRAY_OC{1'b1}};
      for (int col = 0; col < ARRAY_OC; col++) begin
        wgt_row_flatten_o[(col*DATA_WIDTH)+:DATA_WIDTH] =
            tile_mem_q[active_slot_q][(int'(stream_row_idx_w) * ARRAY_OC) + col];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fill_state_q <= F_IDLE;
      stream_state_q <= S_IDLE;
      addr_flatten_q <= '0;
      valid_mask_q[0] <= '0;
      valid_mask_q[1] <= '0;
      zero_mask_q <= '0;
      tag_q[0] <= '0;
      tag_q[1] <= '0;
      elem_idx_q <= '0;
      row_idx_q <= '0;
      slot_valid_q <= '0;
      active_slot_q <= 1'b0;
      fill_slot_q <= 1'b0;
      cache_valid_q <= '0;
      cache_wr_idx_q <= '0;
      weight_rd_en_o <= 1'b0;
      weight_rd_addr_o <= '0;
      dbg_weight_load_cycles_o <= '0;
      dbg_weight_reuse_count_o <= '0;
      dbg_weight_buffer_empty_cycles_o <= '0;
      dbg_weight_buffer_full_cycles_o <= '0;

      for (int slot = 0; slot < 2; slot++) begin
        for (int elem = 0; elem < TILE_ELEMS; elem++) begin
          tile_mem_q[slot][elem] <= '0;
        end
      end
    end else begin
      weight_rd_en_o <= 1'b0;

      if (clear_i) begin
        fill_state_q <= F_IDLE;
        stream_state_q <= S_IDLE;
        addr_flatten_q <= '0;
        valid_mask_q[0] <= '0;
        valid_mask_q[1] <= '0;
        zero_mask_q <= '0;
        tag_q[0] <= '0;
        tag_q[1] <= '0;
        elem_idx_q <= '0;
        row_idx_q <= '0;
        slot_valid_q <= '0;
        active_slot_q <= 1'b0;
        fill_slot_q <= 1'b0;
        cache_valid_q <= '0;
        cache_wr_idx_q <= '0;
        dbg_weight_load_cycles_o <= '0;
        dbg_weight_reuse_count_o <= '0;
        dbg_weight_buffer_empty_cycles_o <= '0;
        dbg_weight_buffer_full_cycles_o <= '0;

        for (int slot = 0; slot < 2; slot++) begin
          for (int elem = 0; elem < TILE_ELEMS; elem++) begin
            tile_mem_q[slot][elem] <= '0;
          end
        end
      end else begin
        if (fill_state_q != F_IDLE) begin
          dbg_weight_load_cycles_o <= dbg_weight_load_cycles_o + COUNTER_WIDTH'(1);
        end

        if (req_valid_i && !req_ready_o) begin
          dbg_weight_buffer_full_cycles_o <= dbg_weight_buffer_full_cycles_o + COUNTER_WIDTH'(1);
        end

        if (stream_start_i && !stream_ready_o) begin
          dbg_weight_buffer_empty_cycles_o <= dbg_weight_buffer_empty_cycles_o + COUNTER_WIDTH'(1);
        end

        if (tile_release_i && !stream_busy_w && active_tile_valid_w) begin
          slot_valid_q[active_slot_q] <= 1'b0;
          if (slot_valid_q[other_slot_w] || (fill_completes_w && (fill_slot_q == other_slot_w))) begin
            active_slot_q <= other_slot_w;
          end
        end

        unique case (fill_state_q)
          F_IDLE: begin
            if (accept_req_w) begin
              fill_slot_q <= selected_fill_slot_w;
              addr_flatten_q <= req_addr_flatten_i;
              valid_mask_q[selected_fill_slot_w] <= req_weight_valid_i;
              zero_mask_q <= req_weight_zero_i;
              tag_q[selected_fill_slot_w] <= req_tag_i;
              elem_idx_q <= '0;
              slot_valid_q[selected_fill_slot_w] <= 1'b0;

              for (int elem = 0; elem < TILE_ELEMS; elem++) begin
                tile_mem_q[selected_fill_slot_w][elem] <= '0;
              end

              if (cache_hit_w) begin
                slot_valid_q[selected_fill_slot_w] <= 1'b1;
                if (!active_tile_valid_w) begin
                  active_slot_q <= selected_fill_slot_w;
                end

                for (int elem = 0; elem < TILE_ELEMS; elem++) begin
                  tile_mem_q[selected_fill_slot_w][elem] <=
                      cache_tile_mem_q[cache_hit_idx_w][elem];
                end

                fill_state_q <= F_IDLE;
              end else begin
                fill_state_q <= F_SCAN;
              end
            end
          end

          F_SCAN: begin
            if (elem_idx_q == ELEM_IDX_WIDTH'(TILE_ELEMS)) begin
              slot_valid_q[fill_slot_q] <= 1'b1;
              if (!active_tile_valid_w || (tile_release_i && !stream_busy_w && (fill_slot_q == other_slot_w))) begin
                active_slot_q <= fill_slot_q;
              end
              cache_valid_q[cache_wr_idx_q] <= 1'b1;
              cache_addr_flatten_q[cache_wr_idx_q] <= addr_flatten_q;
              cache_valid_mask_q[cache_wr_idx_q] <= valid_mask_q[fill_slot_q];
              cache_zero_mask_q[cache_wr_idx_q] <= zero_mask_q;
              for (int elem = 0; elem < TILE_ELEMS; elem++) begin
                cache_tile_mem_q[cache_wr_idx_q][elem] <= tile_mem_q[fill_slot_q][elem];
              end
              cache_wr_idx_q <= cache_wr_idx_q + CACHE_IDX_WIDTH'(1);
              fill_state_q <= F_IDLE;
            end else if (elem_needs_read_w) begin
              weight_rd_en_o <= 1'b1;
              weight_rd_addr_o <= addr_flatten_q[(int'(elem_idx_q)*ADDR_WIDTH)+:ADDR_WIDTH];
              fill_state_q <= F_WAIT;
            end else begin
              elem_idx_q <= elem_idx_q + ELEM_IDX_WIDTH'(1);
            end
          end

          F_WAIT: begin
            if (weight_rd_valid_i) begin
              tile_mem_q[fill_slot_q][elem_idx_q] <= weight_rd_data_i;
              elem_idx_q <= elem_idx_q + ELEM_IDX_WIDTH'(1);
              fill_state_q <= F_SCAN;
            end
          end

          default: begin
            fill_state_q <= F_IDLE;
          end
        endcase

        unique case (stream_state_q)
          S_IDLE: begin
            if (accept_stream_w) begin
              row_idx_q <= '0;
              dbg_weight_reuse_count_o <= dbg_weight_reuse_count_o + COUNTER_WIDTH'(1);
              stream_state_q <= S_ROW;
            end
          end

          S_ROW: begin
            if (row_idx_q == ROW_IDX_WIDTH'(ARRAY_K - 1)) begin
              stream_state_q <= S_SWITCH;
            end else begin
              row_idx_q <= row_idx_q + ROW_IDX_WIDTH'(1);
            end
          end

          S_SWITCH: begin
            stream_state_q <= S_IDLE;
          end

          default: begin
            stream_state_q <= S_IDLE;
          end
        endcase
      end
    end
  end

endmodule : weight_tile_buffer_v3

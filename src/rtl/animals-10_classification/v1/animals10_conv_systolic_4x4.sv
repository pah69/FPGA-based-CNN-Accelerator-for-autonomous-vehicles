`timescale 1ns / 1ps

// Generic correctness-first 3x3 Conv engine using the SIZE=4 Animals-10
// systolic array.
//
// Storage is compact per layer:
//   input_mem  : CHW input feature map
//   weight_mem : OIHW weights for this layer only
//   param_mem  : per-output-channel bias/requant for this layer only
module animals10_conv_systolic_4x4 #(
    parameter int IN_C = 32,
    parameter int IN_H = 64,
    parameter int IN_W = 64,
    parameter int OUT_C = 32,
    parameter int OUT_H = 64,
    parameter int OUT_W = 64,
    parameter int K_H = 3,
    parameter int K_W = 3,
    parameter int PAD = 1,
    parameter int SIZE = 4,
    parameter int INPUT_ADDR_WIDTH = 17,
    parameter int WEIGHT_ADDR_WIDTH = 14,
    parameter int PARAM_ADDR_WIDTH = 5,
    parameter int OUTPUT_ADDR_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    input logic start_i,
    output logic busy_o,
    output logic done_o,

    input logic input_we_i,
    input logic [INPUT_ADDR_WIDTH-1:0] input_addr_i,
    input logic signed [7:0] input_data_i,

    input logic weight_we_i,
    input logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_i,
    input logic signed [7:0] weight_data_i,

    input logic param_we_i,
    input logic [PARAM_ADDR_WIDTH-1:0] param_addr_i,
    input logic signed [31:0] bias_data_i,
    input logic signed [31:0] requant_mult_data_i,
    input logic signed [7:0] requant_shift_data_i,

    output logic output_valid_o,
    output logic output_last_o,
    output logic [OUTPUT_ADDR_WIDTH-1:0] output_index_o,
    output logic signed [31:0] acc_o,
    output logic signed [7:0] data_o,

    output logic [31:0] debug_cycle_count_o,
    output logic [31:0] debug_tile_count_o,
    output logic [31:0] debug_output_count_o
);

  localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
  localparam int WEIGHT_COUNT = OUT_C * IN_C * K_H * K_W;
  localparam int OUT_SPATIAL = OUT_H * OUT_W;
  localparam int OUT_COUNT = OUT_C * OUT_SPATIAL;
  localparam int K_TOTAL = IN_C * K_H * K_W;
  localparam int K_TILES = (K_TOTAL + SIZE - 1) / SIZE;

  initial begin : parameter_check
    assert (SIZE == 4) else $error("animals10_conv_systolic_4x4 requires SIZE=4");
    assert ((OUT_C % SIZE) == 0) else $error("OUT_C must be divisible by SIZE for V1");
    assert (OUT_H == IN_H && OUT_W == IN_W) else $error("V1 conv engine assumes same-size padded Conv2D");
  end

  typedef enum logic [3:0] {
    S_IDLE,
    S_PREPARE_DOT,
    S_LOAD_WEIGHT,
    S_SWITCH_WEIGHT,
    S_FEED_ACT,
    S_DRAIN_TILE,
    S_OUTPUT_LANE
  } state_t;

  state_t state_q;

  logic signed [7:0] input_mem[0:INPUT_COUNT-1];
  logic signed [7:0] weight_mem[0:WEIGHT_COUNT-1];
  logic signed [31:0] bias_mem[0:OUT_C-1];
  logic signed [31:0] requant_mult_mem[0:OUT_C-1];
  logic signed [7:0] requant_shift_mem[0:OUT_C-1];

  int oc_base_q;
  int spatial_q;
  int tile_q;
  int feed_step_q;
  int output_lane_q;

  logic [SIZE-1:0] capture_mask_q;
  logic next_weight_preloaded_q;
  logic signed [31:0] acc_q[0:SIZE-1];

  logic signed [(8*SIZE)-1:0] sa_weight_flatten_w;
  logic [SIZE-1:0] sa_weight_load_w;
  logic signed [(8*SIZE*SIZE)-1:0] sa_weight_matrix_flatten_w;
  logic sa_weight_matrix_load_w;
  logic sa_weight_switch_w;
  logic signed [(8*SIZE)-1:0] sa_act_flatten_w;
  logic [SIZE-1:0] sa_act_valid_w;
  logic signed [(32*SIZE)-1:0] sa_psum_flatten_w;
  logic [SIZE-1:0] sa_psum_valid_w;
  logic [4:0] sa_valid_mac_count_w;
  logic [SIZE-1:0] sa_weight_load_done_w;

  animals10_systolic_array_4x4 #(
      .DATA_WIDTH(8),
      .PSUM_WIDTH(32)
  ) u_systolic_array (
      .clk(clk),
      .rst_n(rst_n),
      .weight_flatten_i(sa_weight_flatten_w),
      .weight_load_i(sa_weight_load_w),
      .weight_stream_enable_i(1'b0),
      .weight_matrix_flatten_i(sa_weight_matrix_flatten_w),
      .weight_matrix_load_i(sa_weight_matrix_load_w),
      .weight_switch_i(sa_weight_switch_w),
      .act_flatten_i(sa_act_flatten_w),
      .act_valid_i(sa_act_valid_w),
      .psum_flatten_o(sa_psum_flatten_w),
      .psum_valid_o(sa_psum_valid_w),
      .valid_mac_count_o(sa_valid_mac_count_w),
      .weight_load_done_o(sa_weight_load_done_w)
  );

  function automatic int input_idx(input int c, input int y, input int x);
    begin
      input_idx = (c * IN_H * IN_W) + (y * IN_W) + x;
    end
  endfunction

  function automatic int weight_idx(input int oc, input int k_index);
    begin
      weight_idx = (oc * K_TOTAL) + k_index;
    end
  endfunction

  function automatic int output_idx(input int oc, input int spatial);
    begin
      output_idx = (oc * OUT_SPATIAL) + spatial;
    end
  endfunction

  function automatic logic signed [7:0] input_value_for_k(
      input int k_index,
      input int spatial
  );
    int ic;
    int rem;
    int ky;
    int kx;
    int oy;
    int ox;
    int in_y;
    int in_x;
    begin
      if (k_index < 0 || k_index >= K_TOTAL) begin
        input_value_for_k = 8'sd0;
      end else begin
        ic = k_index / (K_H * K_W);
        rem = k_index - (ic * K_H * K_W);
        ky = rem / K_W;
        kx = rem - (ky * K_W);
        oy = spatial / OUT_W;
        ox = spatial - (oy * OUT_W);
        in_y = oy + ky - PAD;
        in_x = ox + kx - PAD;
        if (in_y < 0 || in_y >= IN_H || in_x < 0 || in_x >= IN_W) begin
          input_value_for_k = 8'sd0;
        end else begin
          input_value_for_k = input_mem[input_idx(ic, in_y, in_x)];
        end
      end
    end
  endfunction

  function automatic logic signed [7:0] weight_value_for_k(
      input int oc,
      input int k_index
  );
    begin
      if (oc < 0 || oc >= OUT_C || k_index < 0 || k_index >= K_TOTAL) begin
        weight_value_for_k = 8'sd0;
      end else begin
        weight_value_for_k = weight_mem[weight_idx(oc, k_index)];
      end
    end
  endfunction

  function automatic longint signed round_shift_i64(input longint signed value, input int shift);
    longint signed offset;
    begin
      if (shift == 0) begin
        round_shift_i64 = value;
      end else begin
        offset = 64'sd1 <<< (shift - 1);
        if (value >= 0) begin
          round_shift_i64 = (value + offset) >>> shift;
        end else begin
          round_shift_i64 = (value - offset) >>> shift;
        end
      end
    end
  endfunction

  function automatic int signed clamp_i8(input longint signed value);
    begin
      if (value > 127) begin
        clamp_i8 = 127;
      end else if (value < -128) begin
        clamp_i8 = -128;
      end else begin
        clamp_i8 = int'(value);
      end
    end
  endfunction

  function automatic logic signed [7:0] requant_relu(
      input int oc,
      input longint signed acc
  );
    longint signed biased;
    longint signed product;
    longint signed scaled;
    int signed clipped;
    begin
      biased = acc + longint'(bias_mem[oc]);
      product = biased * longint'(requant_mult_mem[oc]);
      scaled = round_shift_i64(product, int'(requant_shift_mem[oc]));
      clipped = clamp_i8(scaled);
      if (clipped < 0) begin
        requant_relu = 8'sd0;
      end else begin
        requant_relu = clipped[7:0];
      end
    end
  endfunction

  function automatic logic signed [31:0] unpack_psum_col(input int col);
    begin
      unpack_psum_col = sa_psum_flatten_w[(col*32)+:32];
    end
  endfunction

  always_comb begin
    int k_index;
    int row;
    logic [SIZE-1:0] capture_mask_probe;

    sa_weight_flatten_w = '0;
    sa_weight_load_w = '0;
    sa_weight_matrix_flatten_w = '0;
    sa_weight_matrix_load_w = 1'b0;
    sa_weight_switch_w = 1'b0;
    sa_act_flatten_w = '0;
    sa_act_valid_w = '0;
    capture_mask_probe = capture_mask_q;

    for (int col = 0; col < SIZE; col++) begin
      if (sa_psum_valid_w[col]) begin
        capture_mask_probe[col] = 1'b1;
      end
    end

    if (state_q == S_LOAD_WEIGHT) begin
      sa_weight_matrix_load_w = 1'b1;
      for (row = 0; row < SIZE; row++) begin
        k_index = (tile_q * SIZE) + row;
        for (int col = 0; col < SIZE; col++) begin
          sa_weight_matrix_flatten_w[((row*SIZE + col)*8)+:8] =
              weight_value_for_k(oc_base_q + col, k_index);
        end
      end
    end else if (state_q == S_SWITCH_WEIGHT) begin
      sa_weight_switch_w = 1'b1;
    end else if (state_q == S_FEED_ACT) begin
      row = feed_step_q;
      k_index = (tile_q * SIZE) + row;
      sa_act_flatten_w[(row*8)+:8] = input_value_for_k(k_index, spatial_q);
      sa_act_valid_w[row] = 1'b1;
    end else if (state_q == S_DRAIN_TILE) begin
      if ((tile_q != K_TILES - 1) && !next_weight_preloaded_q) begin
        sa_weight_matrix_load_w = 1'b1;
        for (row = 0; row < SIZE; row++) begin
          k_index = ((tile_q + 1) * SIZE) + row;
          for (int col = 0; col < SIZE; col++) begin
            sa_weight_matrix_flatten_w[((row*SIZE + col)*8)+:8] =
                weight_value_for_k(oc_base_q + col, k_index);
          end
        end
      end

      if ((tile_q != K_TILES - 1) && next_weight_preloaded_q && (&capture_mask_probe)) begin
        sa_weight_switch_w = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    logic [SIZE-1:0] capture_mask_next;
    if (!rst_n) begin
      state_q <= S_IDLE;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;
      output_index_o <= '0;
      acc_o <= '0;
      data_o <= '0;
      oc_base_q <= 0;
      spatial_q <= 0;
      tile_q <= 0;
      feed_step_q <= 0;
      output_lane_q <= 0;
      capture_mask_q <= '0;
      next_weight_preloaded_q <= 1'b0;
      debug_cycle_count_o <= '0;
      debug_tile_count_o <= '0;
      debug_output_count_o <= '0;
      for (int lane = 0; lane < SIZE; lane++) begin
        acc_q[lane] <= '0;
      end
    end else begin
      done_o <= 1'b0;
      output_valid_o <= 1'b0;
      output_last_o <= 1'b0;

      if (busy_o) begin
        debug_cycle_count_o <= debug_cycle_count_o + 32'd1;
      end

      if (input_we_i) begin
        input_mem[input_addr_i] <= input_data_i;
      end
      if (weight_we_i) begin
        weight_mem[weight_addr_i] <= weight_data_i;
      end
      if (param_we_i) begin
        bias_mem[param_addr_i] <= bias_data_i;
        requant_mult_mem[param_addr_i] <= requant_mult_data_i;
        requant_shift_mem[param_addr_i] <= requant_shift_data_i;
      end

      case (state_q)
        S_IDLE: begin
          if (start_i && !busy_o) begin
            busy_o <= 1'b1;
            oc_base_q <= 0;
            spatial_q <= 0;
            tile_q <= 0;
            feed_step_q <= 0;
            output_lane_q <= 0;
            capture_mask_q <= '0;
            next_weight_preloaded_q <= 1'b0;
            debug_cycle_count_o <= '0;
            debug_tile_count_o <= '0;
            debug_output_count_o <= '0;
            state_q <= S_PREPARE_DOT;
          end
        end

        S_PREPARE_DOT: begin
          tile_q <= 0;
          feed_step_q <= 0;
          output_lane_q <= 0;
          capture_mask_q <= '0;
          next_weight_preloaded_q <= 1'b0;
          for (int lane = 0; lane < SIZE; lane++) begin
            acc_q[lane] <= '0;
          end
          state_q <= S_LOAD_WEIGHT;
        end

        S_LOAD_WEIGHT: begin
          feed_step_q <= 0;
          capture_mask_q <= '0;
          next_weight_preloaded_q <= 1'b0;
          state_q <= S_SWITCH_WEIGHT;
        end

        S_SWITCH_WEIGHT: begin
          next_weight_preloaded_q <= 1'b0;
          state_q <= S_FEED_ACT;
        end

        S_FEED_ACT: begin
          if (feed_step_q == SIZE - 1) begin
            feed_step_q <= 0;
            state_q <= S_DRAIN_TILE;
          end else begin
            feed_step_q <= feed_step_q + 1;
          end
        end

        S_DRAIN_TILE: begin
          capture_mask_next = capture_mask_q;
          for (int col = 0; col < SIZE; col++) begin
            if (sa_psum_valid_w[col] && !capture_mask_q[col]) begin
              acc_q[col] <= acc_q[col] + unpack_psum_col(col);
              capture_mask_next[col] = 1'b1;
            end
          end
          capture_mask_q <= capture_mask_next;

          if ((tile_q != K_TILES - 1) && !next_weight_preloaded_q) begin
            next_weight_preloaded_q <= 1'b1;
          end

          if (&capture_mask_next) begin
            debug_tile_count_o <= debug_tile_count_o + 32'd1;
            capture_mask_q <= '0;
            if (tile_q == K_TILES - 1) begin
              output_lane_q <= 0;
              next_weight_preloaded_q <= 1'b0;
              state_q <= S_OUTPUT_LANE;
            end else begin
              tile_q <= tile_q + 1;
              feed_step_q <= 0;
              next_weight_preloaded_q <= 1'b0;
              if (next_weight_preloaded_q) begin
                state_q <= S_FEED_ACT;
              end else begin
                state_q <= S_SWITCH_WEIGHT;
              end
            end
          end
        end

        S_OUTPUT_LANE: begin
          int oc;
          int out_index;

          oc = oc_base_q + output_lane_q;
          out_index = output_idx(oc, spatial_q);

          output_valid_o <= 1'b1;
          output_index_o <= OUTPUT_ADDR_WIDTH'(out_index);
          acc_o <= acc_q[output_lane_q];
          data_o <= requant_relu(oc, longint'(acc_q[output_lane_q]));
          debug_output_count_o <= debug_output_count_o + 32'd1;

          if (out_index == OUT_COUNT - 1) begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            output_last_o <= 1'b1;
            state_q <= S_IDLE;
          end else if (output_lane_q == SIZE - 1) begin
            output_lane_q <= 0;
            if (spatial_q == OUT_SPATIAL - 1) begin
              spatial_q <= 0;
              oc_base_q <= oc_base_q + SIZE;
            end else begin
              spatial_q <= spatial_q + 1;
            end
            state_q <= S_PREPARE_DOT;
          end else begin
            output_lane_q <= output_lane_q + 1;
          end
        end

        default: begin
          state_q <= S_IDLE;
          busy_o <= 1'b0;
        end
      endcase
    end
  end

endmodule : animals10_conv_systolic_4x4

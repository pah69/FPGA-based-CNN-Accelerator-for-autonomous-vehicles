`timescale 1ns / 1ps

// Address generator for 2-lane conv/FC activation and weight reads.
module conv_fc_address_generator #(
    parameter int SIZE       = 2,
    parameter int ADDR_WIDTH = 16,
    parameter int DIM_WIDTH  = 16,
    parameter int CALC_WIDTH = 32
) (
    input logic [1:0] layer_type_i,

    input logic [ADDR_WIDTH-1:0] activation_base_addr_i,
    input logic [ADDR_WIDTH-1:0] weight_base_addr_i,

    input logic [DIM_WIDTH-1:0] in_h_i,
    input logic [DIM_WIDTH-1:0] in_w_i,
    input logic [DIM_WIDTH-1:0] out_w_i,
    input logic [DIM_WIDTH-1:0] out_ch_i,
    input logic [DIM_WIDTH-1:0] kernel_h_i,
    input logic [DIM_WIDTH-1:0] kernel_w_i,
    input logic [DIM_WIDTH-1:0] k_total_i,

    input logic [DIM_WIDTH-1:0] spatial_idx_i,
    input logic [DIM_WIDTH-1:0] k_tile_idx_i,
    input logic [DIM_WIDTH-1:0] oc_tile_idx_i,

    output logic [ADDR_WIDTH*SIZE-1:0]      act_addr_flatten_o,
    output logic [SIZE-1:0]                 act_valid_o,
    output logic [SIZE-1:0]                 act_zero_o,
    output logic [ADDR_WIDTH*SIZE*SIZE-1:0] weight_addr_flatten_o,
    output logic [SIZE*SIZE-1:0]            weight_valid_o,
    output logic [SIZE*SIZE-1:0]            weight_zero_o,
    output logic [DIM_WIDTH*SIZE-1:0]       k_index_flatten_o,
    output logic [DIM_WIDTH*SIZE-1:0]       oc_index_flatten_o
);

  localparam logic [1:0] LAYER_CONV = 2'd0;

  logic [CALC_WIDTH-1:0] oh_w;
  logic [CALC_WIDTH-1:0] ow_w;
  logic [CALC_WIDTH-1:0] kernel_area_w;
  logic [CALC_WIDTH-1:0] k_lane_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] oc_col_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] act_addr_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] weight_addr_w[0:SIZE-1][0:SIZE-1];
  logic [SIZE-1:0]       k_valid_w;
  logic [SIZE-1:0]       oc_valid_w;

  always_comb begin
    oh_w = '0;
    ow_w = '0;
    kernel_area_w = CALC_WIDTH'(kernel_h_i) * CALC_WIDTH'(kernel_w_i);

    if (out_w_i != '0) begin
      oh_w = CALC_WIDTH'(spatial_idx_i) / CALC_WIDTH'(out_w_i);
      ow_w = CALC_WIDTH'(spatial_idx_i) % CALC_WIDTH'(out_w_i);
    end

    act_addr_flatten_o = '0;
    act_valid_o = {SIZE{1'b1}};
    act_zero_o = '0;
    weight_addr_flatten_o = '0;
    weight_valid_o = '0;
    weight_zero_o = '0;
    k_index_flatten_o = '0;
    oc_index_flatten_o = '0;

    for (int lane = 0; lane < SIZE; lane++) begin
      logic [CALC_WIDTH-1:0] ic_w;
      logic [CALC_WIDTH-1:0] rem_w;
      logic [CALC_WIDTH-1:0] ky_w;
      logic [CALC_WIDTH-1:0] kx_w;

      k_lane_w[lane] = (CALC_WIDTH'(k_tile_idx_i) * CALC_WIDTH'(SIZE)) + CALC_WIDTH'(lane);
      k_valid_w[lane] = (k_lane_w[lane] < CALC_WIDTH'(k_total_i));
      act_zero_o[lane] = !k_valid_w[lane];
      k_index_flatten_o[(lane*DIM_WIDTH)+:DIM_WIDTH] = DIM_WIDTH'(k_lane_w[lane]);

      ic_w = '0;
      rem_w = '0;
      ky_w = '0;
      kx_w = '0;

      if (k_valid_w[lane]) begin
        if (layer_type_i == LAYER_CONV) begin
          if (kernel_area_w != '0) begin
            ic_w = k_lane_w[lane] / kernel_area_w;
            rem_w = k_lane_w[lane] % kernel_area_w;
          end

          if (kernel_w_i != '0) begin
            ky_w = rem_w / CALC_WIDTH'(kernel_w_i);
            kx_w = rem_w % CALC_WIDTH'(kernel_w_i);
          end

          act_addr_w[lane] = CALC_WIDTH'(activation_base_addr_i)
                           + (ic_w * CALC_WIDTH'(in_h_i) * CALC_WIDTH'(in_w_i))
                           + ((oh_w + ky_w) * CALC_WIDTH'(in_w_i))
                           + (ow_w + kx_w);
        end else begin
          act_addr_w[lane] = CALC_WIDTH'(activation_base_addr_i) + k_lane_w[lane];
        end
      end else begin
        act_addr_w[lane] = '0;
      end

      act_addr_flatten_o[(lane*ADDR_WIDTH)+:ADDR_WIDTH] = ADDR_WIDTH'(act_addr_w[lane]);
    end

    for (int col = 0; col < SIZE; col++) begin
      oc_col_w[col] = (CALC_WIDTH'(oc_tile_idx_i) * CALC_WIDTH'(SIZE)) + CALC_WIDTH'(col);
      oc_valid_w[col] = (oc_col_w[col] < CALC_WIDTH'(out_ch_i));
      oc_index_flatten_o[(col*DIM_WIDTH)+:DIM_WIDTH] = DIM_WIDTH'(oc_col_w[col]);
    end

    for (int lane = 0; lane < SIZE; lane++) begin
      for (int col = 0; col < SIZE; col++) begin
        weight_valid_o[(lane*SIZE)+col] = k_valid_w[lane] && oc_valid_w[col];
        weight_zero_o[(lane*SIZE)+col] = !weight_valid_o[(lane*SIZE)+col];

        if (weight_valid_o[(lane*SIZE)+col]) begin
          if (layer_type_i == LAYER_CONV) begin
            weight_addr_w[lane][col] = CALC_WIDTH'(weight_base_addr_i)
                                     + (oc_col_w[col] * CALC_WIDTH'(k_total_i))
                                     + k_lane_w[lane];
          end else begin
            weight_addr_w[lane][col] = CALC_WIDTH'(weight_base_addr_i)
                                     + (k_lane_w[lane] * CALC_WIDTH'(out_ch_i))
                                     + oc_col_w[col];
          end
        end else begin
          weight_addr_w[lane][col] = '0;
        end

        weight_addr_flatten_o[(((lane*SIZE)+col)*ADDR_WIDTH)+:ADDR_WIDTH] =
            ADDR_WIDTH'(weight_addr_w[lane][col]);
      end
    end
  end

endmodule : conv_fc_address_generator

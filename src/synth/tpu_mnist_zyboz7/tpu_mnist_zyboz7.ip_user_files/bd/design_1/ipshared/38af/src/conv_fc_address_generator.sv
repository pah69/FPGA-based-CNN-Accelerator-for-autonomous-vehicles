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
  logic [CALC_WIDTH-1:0] k_lane_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] oc_col_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] act_addr_w[0:SIZE-1];
  logic [CALC_WIDTH-1:0] weight_addr_w[0:SIZE-1][0:SIZE-1];

  function automatic logic [CALC_WIDTH-1:0] mul9(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul9 = (value_i << 3) + value_i;
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul10(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul10 = (value_i << 3) + (value_i << 1);
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul13(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul13 = (value_i << 3) + (value_i << 2) + value_i;
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul16(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul16 = value_i << 4;
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul26(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul26 = (value_i << 4) + (value_i << 3) + (value_i << 1);
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul28(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul28 = (value_i << 5) - (value_i << 2);
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul72(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul72 = (value_i << 6) + (value_i << 3);
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] mul169(input logic [CALC_WIDTH-1:0] value_i);
    begin
      mul169 = (value_i << 7) + (value_i << 5) + (value_i << 3) + value_i;
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] div26(input logic [CALC_WIDTH-1:0] value_i);
    begin
      div26 = '0;
      for (int quotient = 0; quotient < 26; quotient++) begin
        if (value_i >= CALC_WIDTH'(quotient * 26)) begin
          div26 = CALC_WIDTH'(quotient);
        end
      end
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] div11(input logic [CALC_WIDTH-1:0] value_i);
    begin
      div11 = '0;
      for (int quotient = 0; quotient < 11; quotient++) begin
        if (value_i >= CALC_WIDTH'(quotient * 11)) begin
          div11 = CALC_WIDTH'(quotient);
        end
      end
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] div9(input logic [CALC_WIDTH-1:0] value_i);
    begin
      div9 = '0;
      for (int quotient = 0; quotient < 8; quotient++) begin
        if (value_i >= CALC_WIDTH'(quotient * 9)) begin
          div9 = CALC_WIDTH'(quotient);
        end
      end
    end
  endfunction

  function automatic logic [CALC_WIDTH-1:0] fc_weight_stride(
      input logic [DIM_WIDTH-1:0] out_ch_i, input logic [CALC_WIDTH-1:0] k_i);
    begin
      unique case (out_ch_i)
        DIM_WIDTH'(16): fc_weight_stride = mul16(k_i);
        DIM_WIDTH'(10): fc_weight_stride = mul10(k_i);
        DIM_WIDTH'(9):  fc_weight_stride = mul9(k_i);
        default:        fc_weight_stride = '0;
      endcase
    end
  endfunction

  always_comb begin
    oh_w = '0;
    ow_w = '0;

    if (layer_type_i == LAYER_CONV) begin
      unique case (out_w_i)
        DIM_WIDTH'(26): begin
          oh_w = div26(CALC_WIDTH'(spatial_idx_i));
          ow_w = CALC_WIDTH'(spatial_idx_i) - mul26(oh_w);
        end
        DIM_WIDTH'(11): begin
          oh_w = div11(CALC_WIDTH'(spatial_idx_i));
          ow_w = CALC_WIDTH'(spatial_idx_i) - ((oh_w << 3) + (oh_w << 1) + oh_w);
        end
        default: begin
          oh_w = '0;
          ow_w = '0;
        end
      endcase
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
      logic [CALC_WIDTH-1:0] row_plus_ky_w;
      logic                  k_valid_lane_w;

      k_lane_w[lane] = (CALC_WIDTH'(k_tile_idx_i) * CALC_WIDTH'(SIZE)) + CALC_WIDTH'(lane);
      k_valid_lane_w = (k_lane_w[lane] < CALC_WIDTH'(k_total_i));
      act_zero_o[lane] = !k_valid_lane_w;
      k_index_flatten_o[(lane*DIM_WIDTH)+:DIM_WIDTH] = DIM_WIDTH'(k_lane_w[lane]);

      ic_w = '0;
      rem_w = '0;
      ky_w = '0;
      kx_w = '0;

      if (k_valid_lane_w) begin
        if (layer_type_i == LAYER_CONV) begin
          ic_w = div9(k_lane_w[lane]);
          rem_w = k_lane_w[lane] - mul9(ic_w);

          if (rem_w >= CALC_WIDTH'(6)) begin
            ky_w = CALC_WIDTH'(2);
            kx_w = rem_w - CALC_WIDTH'(6);
          end else if (rem_w >= CALC_WIDTH'(3)) begin
            ky_w = CALC_WIDTH'(1);
            kx_w = rem_w - CALC_WIDTH'(3);
          end else begin
            ky_w = '0;
            kx_w = rem_w;
          end

          row_plus_ky_w = oh_w + ky_w;

          unique case (out_w_i)
            DIM_WIDTH'(26): begin
              act_addr_w[lane] = CALC_WIDTH'(activation_base_addr_i)
                               + mul28(row_plus_ky_w)
                               + ow_w
                               + kx_w;
            end
            DIM_WIDTH'(11): begin
              act_addr_w[lane] = CALC_WIDTH'(activation_base_addr_i)
                               + mul169(ic_w)
                               + mul13(row_plus_ky_w)
                               + ow_w
                               + kx_w;
            end
            default: begin
              act_addr_w[lane] = '0;
            end
          endcase
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
      oc_index_flatten_o[(col*DIM_WIDTH)+:DIM_WIDTH] = DIM_WIDTH'(oc_col_w[col]);
    end

    for (int lane = 0; lane < SIZE; lane++) begin
      for (int col = 0; col < SIZE; col++) begin
        weight_valid_o[(lane*SIZE)+col] = (k_lane_w[lane] < CALC_WIDTH'(k_total_i)) &&
            (oc_col_w[col] < CALC_WIDTH'(out_ch_i));
        weight_zero_o[(lane*SIZE)+col] = !weight_valid_o[(lane*SIZE)+col];

        if (weight_valid_o[(lane*SIZE)+col]) begin
          if (layer_type_i == LAYER_CONV) begin
            unique case (k_total_i)
              DIM_WIDTH'(9): begin
                weight_addr_w[lane][col] =
                    CALC_WIDTH'(weight_base_addr_i) + mul9(oc_col_w[col]) + k_lane_w[lane];
              end
              DIM_WIDTH'(72): begin
                weight_addr_w[lane][col] =
                    CALC_WIDTH'(weight_base_addr_i) + mul72(oc_col_w[col]) + k_lane_w[lane];
              end
              default: begin
                weight_addr_w[lane][col] = '0;
              end
            endcase
          end else begin
            weight_addr_w[lane][col] = CALC_WIDTH'(weight_base_addr_i)
                                     + fc_weight_stride(out_ch_i, k_lane_w[lane])
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

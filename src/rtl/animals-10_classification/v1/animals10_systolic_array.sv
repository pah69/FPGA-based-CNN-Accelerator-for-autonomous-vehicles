`timescale 1ns / 1ps

// Animals-10 V1 weight-stationary systolic array.
//
// First accelerator target uses SIZE=4. Keep SIZE parameterized so 8x8 can be
// evaluated later after UB bandwidth and activation prefetch are upgraded.
module animals10_systolic_array #(
    parameter int SIZE = 4,
    parameter int DATA_WIDTH = 8,
    parameter int PSUM_WIDTH = 32,
    parameter int MAC_COUNT_WIDTH = (SIZE * SIZE > 1) ? $clog2((SIZE * SIZE) + 1) : 1
) (
    input logic clk,
    input logic rst_n,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] weight_flatten_i,
    input logic [SIZE-1:0] weight_load_i,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i,
    input logic [SIZE-1:0] act_valid_i,

    output logic signed [(PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,
    output logic [SIZE-1:0] psum_valid_o,
    output logic [MAC_COUNT_WIDTH-1:0] valid_mac_count_o,
    output logic [SIZE-1:0] weight_load_done_o
);

  initial begin : parameter_check
    assert (SIZE > 0) else $error("animals10_systolic_array SIZE must be greater than zero");
    assert (PSUM_WIDTH >= (2 * DATA_WIDTH))
    else $error("animals10_systolic_array PSUM_WIDTH is too small");
  end

  logic signed [DATA_WIDTH-1:0] act_row_w[0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] weight_col_w[0:SIZE-1];

  logic signed [DATA_WIDTH-1:0] act_fwd_w[0:SIZE-1][0:SIZE-1];
  logic act_valid_fwd_w[0:SIZE-1][0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] weight_fwd_w[0:SIZE-1][0:SIZE-1];
  logic weight_valid_fwd_w[0:SIZE-1][0:SIZE-1];
  logic signed [PSUM_WIDTH-1:0] psum_fwd_w[0:SIZE-1][0:SIZE-1];
  logic psum_valid_fwd_w[0:SIZE-1][0:SIZE-1];

  generate
    for (genvar row = 0; row < SIZE; row++) begin : GEN_UNPACK_ACT
      assign act_row_w[row] = act_flatten_i[(row*DATA_WIDTH)+:DATA_WIDTH];
    end

    for (genvar col = 0; col < SIZE; col++) begin : GEN_UNPACK_WEIGHT
      assign weight_col_w[col] = weight_flatten_i[(col*DATA_WIDTH)+:DATA_WIDTH];
    end

    for (genvar row = 0; row < SIZE; row++) begin : GEN_ROW
      for (genvar col = 0; col < SIZE; col++) begin : GEN_COL
        logic signed [DATA_WIDTH-1:0] pe_act_i_w;
        logic pe_act_valid_i_w;
        logic signed [DATA_WIDTH-1:0] pe_weight_i_w;
        logic pe_weight_load_i_w;
        logic signed [PSUM_WIDTH-1:0] pe_psum_i_w;
        logic pe_psum_valid_i_w;

        if (col == 0) begin : GEN_LEFT_EDGE
          assign pe_act_i_w = act_row_w[row];
          assign pe_act_valid_i_w = act_valid_i[row];
        end else begin : GEN_ACT_FROM_LEFT
          assign pe_act_i_w = act_fwd_w[row][col-1];
          assign pe_act_valid_i_w = act_valid_fwd_w[row][col-1];
        end

        if (row == 0) begin : GEN_TOP_EDGE_WEIGHT
          assign pe_weight_i_w = weight_col_w[col];
          assign pe_weight_load_i_w = weight_load_i[col];
        end else begin : GEN_WEIGHT_FROM_ABOVE
          assign pe_weight_i_w = weight_fwd_w[row-1][col];
          assign pe_weight_load_i_w = weight_valid_fwd_w[row-1][col];
        end

        if (row == 0) begin : GEN_TOP_EDGE_PSUM
          assign pe_psum_i_w = '0;
          assign pe_psum_valid_i_w = pe_act_valid_i_w;
        end else begin : GEN_PSUM_FROM_ABOVE
          assign pe_psum_i_w = psum_fwd_w[row-1][col];
          assign pe_psum_valid_i_w = psum_valid_fwd_w[row-1][col];
        end

        animals10_pe #(
            .DATA_WIDTH(DATA_WIDTH),
            .PSUM_WIDTH(PSUM_WIDTH)
        ) u_pe (
            .clk(clk),
            .rst_n(rst_n),
            .act_i(pe_act_i_w),
            .act_valid_i(pe_act_valid_i_w),
            .act_o(act_fwd_w[row][col]),
            .act_valid_o(act_valid_fwd_w[row][col]),
            .psum_i(pe_psum_i_w),
            .psum_valid_i(pe_psum_valid_i_w),
            .psum_o(psum_fwd_w[row][col]),
            .psum_valid_o(psum_valid_fwd_w[row][col]),
            .weight_i(pe_weight_i_w),
            .weight_load_i(pe_weight_load_i_w),
            .weight_o(weight_fwd_w[row][col]),
            .weight_valid_o(weight_valid_fwd_w[row][col])
        );
      end
    end

    for (genvar col = 0; col < SIZE; col++) begin : GEN_PACK_OUTPUT
      assign psum_flatten_o[(col*PSUM_WIDTH)+:PSUM_WIDTH] = psum_fwd_w[SIZE-1][col];
      assign psum_valid_o[col] = psum_valid_fwd_w[SIZE-1][col];
      assign weight_load_done_o[col] = weight_valid_fwd_w[SIZE-1][col];
    end
  endgenerate

  always_comb begin
    valid_mac_count_o = '0;
    for (int row = 0; row < SIZE; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        if (col == 0) begin
          valid_mac_count_o = valid_mac_count_o + MAC_COUNT_WIDTH'(act_valid_i[row]);
        end else begin
          valid_mac_count_o = valid_mac_count_o + MAC_COUNT_WIDTH'(act_valid_fwd_w[row][col-1]);
        end
      end
    end
  end

endmodule : animals10_systolic_array


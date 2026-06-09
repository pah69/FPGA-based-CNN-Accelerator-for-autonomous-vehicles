`timescale 1ns / 1ps

// Weight-stationary systolic array.
//
// Historical module name is kept for compatibility with the v2 wrapper, but
// the PE grid is now generated from SIZE so V3 can experiment with SIZE=4.
module systolic_array #(
    parameter int SIZE               = 2,
    parameter int DATA_WIDTH         = 8,
    parameter int LOCAL_PSUM_WIDTH   = (2 * DATA_WIDTH) + $clog2(SIZE),
    parameter int NUM_TILES          = SIZE,
    parameter int ACC_WIDTH          = 32,
    parameter bit ENABLE_LOCAL_ACCUM = 1'b0,
    parameter int TILE_COUNT_WIDTH   = (NUM_TILES > 1) ? $clog2(NUM_TILES + 1) : 1,
    parameter int MAC_COUNT_WIDTH    = (SIZE*SIZE > 1) ? $clog2((SIZE*SIZE) + 1) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic work_i,
    input logic [TILE_COUNT_WIDTH-1:0] num_tiles_i,
    input logic                        local_accum_enable_i,
    input logic                        local_accum_clear_i,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i,
    input logic        [             SIZE-1:0] wgt_load_i,
    input logic                                weight_switch_i,

    input logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i,
    input logic        [             SIZE-1:0] act_valid_i,

    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,
    output logic        [                   SIZE-1:0] psum_valid_o,
    output logic        [        MAC_COUNT_WIDTH-1:0] valid_mac_count_o,

    output logic signed [(ACC_WIDTH*SIZE)-1:0] result_flatten_o,
    output logic                               done_o,

    output logic [SIZE-1:0]      wgt_load_done_o,
    input  logic                 overflow_clr_i,
    output logic [SIZE*SIZE-1:0] overflow_flatten_o
);

  initial begin : parameter_check
    assert (SIZE > 0)
    else $error("systolic_array SIZE must be greater than zero");
  end

  logic signed [DATA_WIDTH-1:0] act_row_w[0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] wgt_col_w[0:SIZE-1];

  logic signed [DATA_WIDTH-1:0] act_fwd_w[0:SIZE-1][0:SIZE-1];
  logic                         act_valid_fwd_w[0:SIZE-1][0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] wgt_fwd_w[0:SIZE-1][0:SIZE-1];
  logic                         wgt_valid_fwd_w[0:SIZE-1][0:SIZE-1];
  logic signed [LOCAL_PSUM_WIDTH-1:0] psum_fwd_w[0:SIZE-1][0:SIZE-1];
  logic                               psum_valid_fwd_w[0:SIZE-1][0:SIZE-1];

  logic signed [ACC_WIDTH-1:0] result_acc_w[0:SIZE-1];
  logic [SIZE-1:0]             acc_done_w;
  logic                        local_accum_enable_w;
  logic                        local_accum_clear_w;

  assign local_accum_enable_w = (local_accum_enable_i === 1'b1);
  assign local_accum_clear_w  = (local_accum_clear_i === 1'b1) || !local_accum_enable_w;

  generate
    for (genvar row = 0; row < SIZE; row++) begin : GEN_INPUT_UNPACK_ACT
      assign act_row_w[row] = act_flatten_i[(row*DATA_WIDTH)+:DATA_WIDTH];
    end

    for (genvar col = 0; col < SIZE; col++) begin : GEN_INPUT_UNPACK_WGT
      assign wgt_col_w[col] = wgt_flatten_i[(col*DATA_WIDTH)+:DATA_WIDTH];
    end

    for (genvar row = 0; row < SIZE; row++) begin : GEN_PE_ROW
      for (genvar col = 0; col < SIZE; col++) begin : GEN_PE_COL
        logic signed [DATA_WIDTH-1:0] pe_act_i_w;
        logic                         pe_act_valid_i_w;
        logic signed [DATA_WIDTH-1:0] pe_wgt_i_w;
        logic                         pe_wgt_load_i_w;
        logic signed [LOCAL_PSUM_WIDTH-1:0] pe_psum_i_w;
        logic                               pe_psum_valid_i_w;

        if (col == 0) begin : GEN_LEFT_EDGE
          assign pe_act_i_w       = act_row_w[row];
          assign pe_act_valid_i_w = act_valid_i[row];
        end else begin : GEN_ACT_FROM_LEFT
          assign pe_act_i_w       = act_fwd_w[row][col-1];
          assign pe_act_valid_i_w = act_valid_fwd_w[row][col-1];
        end

        if (row == 0) begin : GEN_TOP_EDGE_WEIGHT
          assign pe_wgt_i_w      = wgt_col_w[col];
          assign pe_wgt_load_i_w = wgt_load_i[col];
        end else begin : GEN_WEIGHT_FROM_ABOVE
          assign pe_wgt_i_w      = wgt_fwd_w[row-1][col];
          assign pe_wgt_load_i_w = wgt_valid_fwd_w[row-1][col];
        end

        if (row == 0) begin : GEN_TOP_EDGE_PSUM
          assign pe_psum_i_w       = '0;
          assign pe_psum_valid_i_w = pe_act_valid_i_w;
        end else begin : GEN_PSUM_FROM_ABOVE
          assign pe_psum_i_w       = psum_fwd_w[row-1][col];
          assign pe_psum_valid_i_w = psum_valid_fwd_w[row-1][col];
        end

        pe #(
            .DATA_WIDTH      (DATA_WIDTH),
            .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)
        ) u_pe (
            .clk            (clk),
            .rst_n          (rst_n),
            .act_i          (pe_act_i_w),
            .act_valid_i    (pe_act_valid_i_w),
            .act_o          (act_fwd_w[row][col]),
            .act_valid_o    (act_valid_fwd_w[row][col]),
            .psum_i         (pe_psum_i_w),
            .psum_valid_i   (pe_psum_valid_i_w),
            .psum_o         (psum_fwd_w[row][col]),
            .psum_valid_o   (psum_valid_fwd_w[row][col]),
            .weight_i       (pe_wgt_i_w),
            .weight_load_i  (pe_wgt_load_i_w),
            .weight_switch_i(weight_switch_i),
            .weight_o       (wgt_fwd_w[row][col]),
            .weight_valid_o (wgt_valid_fwd_w[row][col]),
            .overflow_clr_i (overflow_clr_i),
            .overflow_o     (overflow_flatten_o[(row*SIZE)+col])
        );
      end
    end

    for (genvar col = 0; col < SIZE; col++) begin : GEN_OUTPUT_PACK
      assign psum_flatten_o[(col*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] =
          psum_fwd_w[SIZE-1][col];
      assign psum_valid_o[col] = psum_valid_fwd_w[SIZE-1][col];
      assign wgt_load_done_o[col] = wgt_valid_fwd_w[SIZE-1][col];
      assign result_flatten_o[(col*ACC_WIDTH)+:ACC_WIDTH] =
          local_accum_enable_w ? result_acc_w[col] : '0;
    end

    if (ENABLE_LOCAL_ACCUM) begin : GEN_LOCAL_ACCUM
      localparam int WORK_PROP_DELAY = 4;

      logic [(WORK_PROP_DELAY*SIZE)-1:0] work_pipe;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          work_pipe <= '0;
        end else begin
          work_pipe[0] <= work_i;
          for (int idx = 1; idx < (WORK_PROP_DELAY * SIZE); idx++) begin
            work_pipe[idx] <= work_pipe[idx-1];
          end
        end
      end

      for (genvar col = 0; col < SIZE; col++) begin : GEN_OUTPUT_ACCUM
        output_accumulator_v2 #(
            .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH),
            .ACC_WIDTH       (ACC_WIDTH),
            .NUM_TILES       (NUM_TILES)
        ) u_output_accumulator (
            .clk         (clk),
            .rst_n       (rst_n),
            .clear_i     (local_accum_clear_w),
            .work_i      (work_pipe[((col+1)*WORK_PROP_DELAY)-1] && local_accum_enable_w),
            .num_tiles_i (num_tiles_i),
            .psum_i      (psum_fwd_w[SIZE-1][col]),
            .psum_valid_i(psum_valid_fwd_w[SIZE-1][col]),
            .result_o    (result_acc_w[col]),
            .done_o      (acc_done_w[col])
        );
      end
    end else begin : GEN_NO_LOCAL_ACCUM
      for (genvar col = 0; col < SIZE; col++) begin : GEN_ZERO_ACCUM
        assign result_acc_w[col] = '0;
        assign acc_done_w[col] = 1'b0;
      end
    end
  endgenerate

  always_comb begin
    valid_mac_count_o = '0;
    for (int row = 0; row < SIZE; row++) begin
      for (int col = 0; col < SIZE; col++) begin
        if (col == 0) begin
          valid_mac_count_o = valid_mac_count_o + MAC_COUNT_WIDTH'(act_valid_i[row]);
        end else begin
          valid_mac_count_o =
              valid_mac_count_o + MAC_COUNT_WIDTH'(act_valid_fwd_w[row][col-1]);
        end
      end
    end
  end

  assign done_o = ENABLE_LOCAL_ACCUM ? ((&acc_done_w) && local_accum_enable_w) : 1'b0;

endmodule : systolic_array

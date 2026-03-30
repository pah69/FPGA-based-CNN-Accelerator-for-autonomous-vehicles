`timescale 1ns / 1ps

module systolic_array #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 17
) (
    input  logic clk,
    input  logic rst_n,

    // One activation per row (broadcast across each row)
    input  logic signed [DATA_WIDTH-1:0] act_in [0:ROWS-1],
    input  logic                         valid_in,
    input  logic                         start_in,
    input  logic                         clear_in,

    // One weight per column (loaded into all PEs of that column)
    input  logic signed [DATA_WIDTH-1:0] weight_in   [0:COLS-1],
    input  logic                         weight_load [0:COLS-1],

    // Outputs
    output logic signed [2*DATA_WIDTH:0] result_out [0:ROWS-1][0:COLS-1],
    output logic                         valid_out  [0:ROWS-1][0:COLS-1],
    output logic signed [DATA_WIDTH-1:0] weight_dbg [0:ROWS-1][0:COLS-1]
);

  genvar r, c;
  generate
    for (r = 0; r < ROWS; r++) begin : GEN_ROW
      for (c = 0; c < COLS; c++) begin : GEN_COL
        pe #(
            .DATA_WIDTH(DATA_WIDTH)
        ) pe_inst (
            .clk          (clk),
            .rst_n        (rst_n),
            .activation_i (act_in[r]),
            .valid_i      (valid_in),
            .weight_i     (weight_in[c]),
            .weight_load_i(weight_load[c]),
            .start_i      (start_in),
            .clear_i      (clear_in),
            .result_o     (result_out[r][c]),
            .valid_o      (valid_out[r][c]),
            .weight_o     (weight_dbg[r][c])
        );
      end
    end
  endgenerate

endmodule : systolic_array
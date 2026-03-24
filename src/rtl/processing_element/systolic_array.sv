////////////////////////////////////////////////////////////////////////////////
// Company: SoC.one
// Engineer: Anh Ho Pham
//
// Create Date: 03/23/2026
// Design Name: CNN_Accelerator
// Module Name: systolic_array
// Target Device: ZCU104
// Tool versions: Vivado 2025.2
// Description:
//    Parameterized 2D Systolic Array of Processing Elements (PEs). 
//    Features weight-stationary dataflow, horizontal activation forwarding,
//    and automatic control signal wavefront synchronization.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module systolic_array #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 17,
    parameter ADDR_WIDTH = 16,
    parameter MAC_PIPELINE_DEPTH = 4
) (
    input logic clk,
    input logic rst_n,

    // Activation Dataflow (Inputs per row)
    input logic signed [DATA_WIDTH-1:0] act_in[0:ROWS-1],

    // Weight Loading Network
    input logic signed [DATA_WIDTH-1:0] weight_in,
    input logic        [ADDR_WIDTH-1:0] weight_addr,
    input logic                         weight_we  [0:ROWS-1][0:COLS-1],

    // Control Signals
    input logic valid_in[0:ROWS-1],
    input logic start_in[0:ROWS-1],
    input logic clear_in[0:ROWS-1],

    // Output
    output logic signed [2*DATA_WIDTH:0] result_out[0:ROWS-1][0:COLS-1],
    output logic                         valid_o   [0:ROWS-1][0:COLS-1]
);
  // Wire array to daisy-chain activations horizontally across columns.
  // Sized [COLS+1] to account for the input to column 0, and the output of column N.
  logic signed [DATA_WIDTH-1:0] act_wire[0:ROWS-1][0:COLS];

  // Arrays to hold the correctly delayed control signals for each PE
  logic valid_ctrl[0:ROWS-1][0:COLS-1];
  logic start_ctrl[0:ROWS-1][0:COLS-1];
  logic clear_ctrl[0:ROWS-1][0:COLS-1];

  // ARRAY GENERATION
  genvar r, c;
  generate
    for (r = 0; r < ROWS; r++) begin : GEN_ROW

      // Assign the external inputs to the 0th column of this row
      assign act_wire[r][0]   = act_in[r];
      assign valid_ctrl[r][0] = valid_in[r];
      assign start_ctrl[r][0] = start_in[r];
      assign clear_ctrl[r][0] = clear_in[r];

      for (c = 0; c < COLS; c++) begin : GEN_COL
        // 2. Control Signal Wavefront Delay (For columns 1 and beyond)
        // We must delay the control signals by MAC_PIPELINE_DEPTH so they 
        // arrive at the exact same time as the forwarded activation.
        if (c > 0) begin : GEN_CTRL_DELAY
          logic [MAC_PIPELINE_DEPTH-1:0] v_pipe, s_pipe, c_pipe;

          always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
              v_pipe <= '0;
              s_pipe <= '0;
              c_pipe <= '0;
            end else begin
              // Shift registers for the control signals
              v_pipe <= {v_pipe[MAC_PIPELINE_DEPTH-2:0], valid_ctrl[r][c-1]};
              s_pipe <= {s_pipe[MAC_PIPELINE_DEPTH-2:0], start_ctrl[r][c-1]};
              c_pipe <= {c_pipe[MAC_PIPELINE_DEPTH-2:0], clear_ctrl[r][c-1]};
            end
          end

          // The output of the shift register feeds the current column
          assign valid_ctrl[r][c] = v_pipe[MAC_PIPELINE_DEPTH-1];
          assign start_ctrl[r][c] = s_pipe[MAC_PIPELINE_DEPTH-1];
          assign clear_ctrl[r][c] = c_pipe[MAC_PIPELINE_DEPTH-1];
        end

        // Instantiate
        pe #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH),
            .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
        ) pe_inst (
            .clk  (clk),
            .rst_n(rst_n),

            // Activations daisy-chained from [c] to [c+1]
            .activation_i(act_wire[r][c]),
            .activation_o(act_wire[r][c+1]),

            // Weight
            .weight_i   (weight_in),
            .weight_addr(weight_addr),
            .weight_we  (weight_we[r][c]), // Unique Write Enable per PE

            // Synchronized Control Signals
            .valid_i (valid_ctrl[r][c]),
            .start    (start_ctrl[r][c]),
            .acc_clear(clear_ctrl[r][c]),

            // PE Outputs
            .valid_o (valid_o[r][c]),
            .result_o(result_out[r][c])
        );
      end
    end
  endgenerate

endmodule

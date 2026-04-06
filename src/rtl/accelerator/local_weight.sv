`timescale 1ns / 1ps

module local_weight #(
    parameter DATA_WIDTH = 17,
    parameter COLS       = 4
)(
    input  logic clk,
    input  logic rst,

    // phase 1: load local staging register from weight_buffer
    input  logic local_load_i,
    input  logic [COLS*DATA_WIDTH-1:0] weight_vec_in,

    // phase 2: pulse PE weight-register loads
    input  logic pe_weight_load_i,

    output logic signed [DATA_WIDTH-1:0] weight_out [0:COLS-1],
    output logic                  weight_load [0:COLS-1]
);

    logic [COLS*DATA_WIDTH-1:0] weight_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            weight_reg <= '0;
        end else begin
            if (local_load_i)
                weight_reg <= weight_vec_in;
        end
    end

    generate
        genvar c;
        for (c = 0; c < COLS; c++) begin : GEN_WEIGHT_UNPACK
            assign weight_out[c]  = weight_reg[c*DATA_WIDTH +: DATA_WIDTH];
            assign weight_load[c] = pe_weight_load_i;
        end
    endgenerate

endmodule
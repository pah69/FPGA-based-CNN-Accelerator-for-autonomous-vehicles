// // `timescale 1ns / 1ps
// module local_activation #(
//     parameter DATA_WIDTH = 8,
//     parameter ROWS       = 4
// ) (
//     input logic clk,
//     input logic rst,

//     input logic valid_in,
//     input logic start_in,
//     input logic clear_in,

//     input logic [ROWS*DATA_WIDTH-1:0] act_vec_in,

//     output logic [DATA_WIDTH-1:0] act_out[ROWS],
//     output logic valid_out,
//     output logic start_out,
//     output logic clear_out
// );

//   logic [ROWS*DATA_WIDTH-1:0] act_reg;

//   always_ff @(posedge clk) begin
//     if (rst) begin
//       act_reg   <= '0;
//       valid_out <= 0;
//       start_out <= 0;
//       clear_out <= 0;
//     end else begin
//       if (valid_in) act_reg <= act_vec_in;

//       valid_out <= valid_in;
//       start_out <= start_in;
//       clear_out <= clear_in;
//     end
//   end

//   genvar i;

//   generate
//     for (i = 0; i < ROWS; i++) begin
//       assign act_out[i] = act_reg[i*DATA_WIDTH+:DATA_WIDTH];
//     end
//   endgenerate

// endmodule
`timescale 1ns / 1ps

module local_activation #(
    parameter DATA_WIDTH = 17,
    parameter ROWS       = 4
)(
    input  logic clk,
    input  logic rst,

    // phase 1: load local staging registers
    input  logic local_load_i,
    input  logic [ROWS*DATA_WIDTH-1:0] act_vec_in,

    // phase 2: fire staged activations into the array
    input  logic act_fire_i,
    input  logic start_fire_i,
    input  logic clear_fire_i,

    output logic signed [DATA_WIDTH-1:0] act_out [0:ROWS-1],
    output logic                  valid_out,
    output logic                  start_out,
    output logic                  clear_out
);

    logic [ROWS*DATA_WIDTH-1:0] act_reg;

    integer i;

    always_ff @(posedge clk) begin
        if (rst) begin
            act_reg    <= '0;
            valid_out  <= 1'b0;
            start_out  <= 1'b0;
            clear_out  <= 1'b0;
        end else begin
            if (local_load_i)
                act_reg <= act_vec_in;

            // pulses generated only when explicitly fired
            valid_out <= act_fire_i;
            start_out <= start_fire_i;
            clear_out <= clear_fire_i;
        end
    end

    generate
        genvar r;
        for (r = 0; r < ROWS; r++) begin : GEN_ACT_UNPACK
            assign act_out[r] = act_reg[r*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate

endmodule
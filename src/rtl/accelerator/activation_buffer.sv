`timescale 1ns / 1ps

module activation_buffer #(
    parameter DATA_WIDTH = 17,
    parameter ROWS       = 4,
    parameter DEPTH      = 256,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic clk,

    // Write side
    input  logic                      wr_en,
    input  logic [ADDR_WIDTH-1:0]     wr_addr,
    input  logic [ROWS*DATA_WIDTH-1:0] wr_data,

    // Read side
    input  logic                      rd_en,
    input  logic [ADDR_WIDTH-1:0]     rd_addr,
    output logic [ROWS*DATA_WIDTH-1:0] rd_data
);

    logic [ROWS*DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end

        if (rd_en) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule : activation_buffer
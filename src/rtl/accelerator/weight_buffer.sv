module weight_buffer #(
    parameter DATA_WIDTH = 8,
    parameter COLS       = 8,
    parameter DEPTH      = 256
)(
    input  logic clk,

    // load side
    input  logic wr_en,
    input  logic [$clog2(DEPTH)-1:0] wr_addr,
    input  logic [COLS*DATA_WIDTH-1:0] wr_data,

    // read side
    input  logic rd_en,
    input  logic [$clog2(DEPTH)-1:0] rd_addr,
    output logic [COLS*DATA_WIDTH-1:0] rd_data
);


endmodule : weight_buffer
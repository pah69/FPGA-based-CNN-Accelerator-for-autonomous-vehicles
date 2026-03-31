
module activation_buffer #(
    parameter DATA_WIDTH = 8,
    parameter ROWS       = 8,
    parameter DEPTH      = 256
) (
    input logic clk,

    // load side
    input logic wr_en,
    input logic [$clog2(DEPTH)-1:0] wr_addr,
    input logic [ROWS*DATA_WIDTH-1:0] wr_data,

    // read side
    input logic rd_en,
    input logic [$clog2(DEPTH)-1:0] rd_addr,
    output logic [ROWS*DATA_WIDTH-1:0] rd_data
);

logic signed [DATA_WIDTH-1:0] mem [DEPTH:0];

always_ff @(posedge clk) begin


end
endmodule : activation_buffer

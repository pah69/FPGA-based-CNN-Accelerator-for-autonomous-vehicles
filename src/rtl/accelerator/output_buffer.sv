module output_buffer #(
    parameter DATA_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    // Data inputs
    input logic signed [DATA_WIDTH-1:0] data,
    output logic signed [DATA_WIDTH-1:0] result
    
);
    
endmodule
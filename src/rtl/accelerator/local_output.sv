module local_output #(
    parameter DATA_WIDTH = 8,
    parameter ROWS       = 4,
    parameter COLS       = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic result_valid_i,

    input  logic signed [DATA_WIDTH-1:0] result_in [ROWS][COLS],

    output logic result_valid_o,
    output logic [ROWS*COLS*DATA_WIDTH-1:0] result_vec_o
);

logic [ROWS*COLS*DATA_WIDTH-1:0] result_reg;

integer r,c;

always_ff @(posedge clk) begin
    if (rst) begin
        result_reg <= '0;
        result_valid_o <= 0;
    end
    else begin
        result_valid_o <= result_valid_i;

        if (result_valid_i) begin
            for (r = 0; r < ROWS; r++) begin
                for (c = 0; c < COLS; c++) begin
                    result_reg[(r*COLS + c)*DATA_WIDTH +: DATA_WIDTH] <= result_in[r][c];
                end
            end
        end
    end
end

assign result_vec_o = result_reg;

endmodule
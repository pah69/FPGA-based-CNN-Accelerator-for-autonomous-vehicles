`timescale 1ns / 1ps

module act_skew_buffer_2x2 #(
    parameter int SIZE               = 2,
    parameter int DATA_WIDTH         = 8,
    parameter int ROW_STAGGER_CYCLES = 4
) (
    input  logic                               clk,
    input  logic                               rst_n,

    // Dữ liệu pixel thô đọc ra từ SRAM/Unified Buffer (đến cùng 1 lúc)
    input  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flat_raw_i,
    input  logic        [SIZE-1:0]              act_valid_raw_i,

    // Dữ liệu đã được tạo độ trễ bậc thang (nối vào ws_sa_2x2)
    output logic signed [(DATA_WIDTH*SIZE)-1:0] act_skewed_o,
    output logic        [SIZE-1:0]              act_valid_skewed_o
);

    initial begin : parameter_check
        assert (SIZE > 0) else $error("act_skew_buffer_2x2 SIZE must be greater than zero");
        assert (ROW_STAGGER_CYCLES >= 0) else $error("ROW_STAGGER_CYCLES must be non-negative");
    end

    logic signed [DATA_WIDTH-1:0] in_row  [0:SIZE-1];
    logic signed [DATA_WIDTH-1:0] out_row [0:SIZE-1];

    generate
        for (genvar row = 0; row < SIZE; row++) begin : GEN_ROW_SKEW
            localparam int DELAY_CYCLES = row * ROW_STAGGER_CYCLES;

            assign in_row[row] = act_flat_raw_i[(row*DATA_WIDTH)+:DATA_WIDTH];
            assign act_skewed_o[(row*DATA_WIDTH)+:DATA_WIDTH] = out_row[row];

            if (DELAY_CYCLES == 0) begin : GEN_NO_DELAY
                assign out_row[row] = in_row[row];
                assign act_valid_skewed_o[row] = act_valid_raw_i[row];
            end else begin : GEN_DELAY
                logic signed [DATA_WIDTH-1:0] data_pipe [0:DELAY_CYCLES-1];
                logic                         valid_pipe[0:DELAY_CYCLES-1];

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (int idx = 0; idx < DELAY_CYCLES; idx++) begin
                            data_pipe[idx]  <= '0;
                            valid_pipe[idx] <= 1'b0;
                        end
                    end else begin
                        data_pipe[0]  <= in_row[row];
                        valid_pipe[0] <= act_valid_raw_i[row];

                        for (int idx = 1; idx < DELAY_CYCLES; idx++) begin
                            data_pipe[idx]  <= data_pipe[idx-1];
                            valid_pipe[idx] <= valid_pipe[idx-1];
                        end
                    end
                end

                assign out_row[row] = data_pipe[DELAY_CYCLES-1];
                assign act_valid_skewed_o[row] = valid_pipe[DELAY_CYCLES-1];
            end
        end
    endgenerate

endmodule

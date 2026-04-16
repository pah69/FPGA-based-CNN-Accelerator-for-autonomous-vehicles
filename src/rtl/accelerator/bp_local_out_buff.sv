`timescale 1ns / 1ps

module bp_local_out_buff #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 64,
    parameter int DEPTH      = 16 // Sức chứa 16 hàng (Mỗi hàng 1088-bit)
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // ========================================
    // Ngõ vào (Từ Post-Processing)
    // ========================================
    input  logic [(DATA_WIDTH*SIZE)-1:0] post_data_i,
    input  logic [SIZE-1:0]              post_valid_i, // Dùng bit 0 làm Write Enable

    // ========================================
    // Ngõ ra (Giao tiếp với Global SRAM & Controller)
    // ========================================
    input  logic                         sram_read_en_i, // Controller cho phép đọc
    output logic [(DATA_WIDTH*SIZE)-1:0] sram_data_o,
    output logic                         fifo_full_o,
    output logic                         fifo_empty_o
);

    // Kích thước thật của 1 hàng dữ liệu
    localparam int ROW_WIDTH = DATA_WIDTH * SIZE;

    // Bộ nhớ RAM nội bộ của FIFO
    logic [ROW_WIDTH-1:0] mem [DEPTH-1:0];

    // Con trỏ đọc, ghi và biến đếm
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] rd_ptr;
    logic [$clog2(DEPTH):0]   count;

    // Lấy đại diện bit 0 của mảng valid làm tín hiệu Write Enable (vì cả hàng ra cùng lúc)
    logic wr_en;
    assign wr_en = post_valid_i[0] & ~fifo_full_o;

    logic rd_en;
    assign rd_en = sram_read_en_i & ~fifo_empty_o;

    // Logic Con trỏ và Đếm số lượng
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            case ({wr_en, rd_en})
                2'b10: begin // Chỉ ghi
                    wr_ptr <= wr_ptr + 1'b1;
                    count  <= count + 1'b1;
                end
                2'b01: begin // Chỉ đọc
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end
                2'b11: begin // Vừa ghi vừa đọc
                    wr_ptr <= wr_ptr + 1'b1;
                    rd_ptr <= rd_ptr + 1'b1;
                    // Count không đổi
                end
            endcase
        end
    end

    // Logic Ghi dữ liệu vào RAM
    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_ptr] <= post_data_i;
        end
    end

    // Gán tín hiệu ngõ ra
    assign sram_data_o  = mem[rd_ptr];
    assign fifo_empty_o = (count == 0);
    assign fifo_full_o  = (count == DEPTH);

endmodule
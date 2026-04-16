`timescale 1ns / 1ps

module bp_post_proc #(
    parameter int DATA_WIDTH  = 17,
    parameter int PSUM_WIDTH  = (2 * DATA_WIDTH) + 8, // 42-bit
    parameter int SIZE        = 64,
    parameter int QUANT_SHIFT = 8   // Số bit dịch phải để ép kiểu về 17-bit
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // ========================================
    // Ngõ vào từ Systolic Array (Dữ liệu thô to bự)
    // ========================================
    input  logic [(PSUM_WIDTH*SIZE)-1:0] psum_flatten_i,
    input  logic [SIZE-1:0]              psum_valid_i,

    // ========================================
    // Ngõ ra đã gọt dũa (Đẩy sang FIFO)
    // ========================================
    output logic [(DATA_WIDTH*SIZE)-1:0] data_flatten_o,
    output logic [SIZE-1:0]              data_valid_o
);

    // Unpack từ 1D thành 2D để dễ xử lý
    logic signed [PSUM_WIDTH-1:0] psum_2d   [SIZE-1:0];
    logic signed [PSUM_WIDTH-1:0] relu_out  [SIZE-1:0];
    logic signed [DATA_WIDTH-1:0] quant_out [SIZE-1:0];

    always_comb begin
        for (int i = 0; i < SIZE; i++) begin
            psum_2d[i] = psum_flatten_i[(i*PSUM_WIDTH) +: PSUM_WIDTH];
            
            // 1. Logic ReLU (Nếu số âm -> cho bằng 0)
            if (psum_2d[i] < 0) begin
                relu_out[i] = '0;
            end else begin
                relu_out[i] = psum_2d[i];
            end

            // 2. Logic Quantization (Dịch phải để chia, sau đó cắt lấy DATA_WIDTH bit)
            // Lưu ý: Trong thực tế phức tạp hơn có thể cần logic chống tràn (saturation), 
            // ở đây ta dùng cắt bit đơn giản.
            quant_out[i] = relu_out[i][QUANT_SHIFT +: DATA_WIDTH];
        end
    end

    // 3. Pipeline Register (Tạo 1 nhịp trễ để giảm áp lực timing cho phép toán)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_flatten_o <= '0;
            data_valid_o   <= '0;
        end else begin
            for (int i = 0; i < SIZE; i++) begin
                data_flatten_o[(i*DATA_WIDTH) +: DATA_WIDTH] <= quant_out[i];
                data_valid_o[i]                              <= psum_valid_i[i];
            end
        end
    end

endmodule
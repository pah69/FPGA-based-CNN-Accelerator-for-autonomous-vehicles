`timescale 1ns / 1ps

module act_skew_buffer_2x2 #(
    parameter int SIZE       = 2,
    parameter int DATA_WIDTH = 8
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

    // ==========================================
    // Mảng 2D tạm thời để dễ thao tác
    // ==========================================
    logic signed [DATA_WIDTH-1:0] in_row  [0:SIZE-1];
    logic signed [DATA_WIDTH-1:0] out_row [0:SIZE-1];

    // Giải nén dữ liệu đầu vào từ mảng 1D (Flatten) thành các hàng riêng biệt
    assign in_row[0] = act_flat_raw_i[(0*DATA_WIDTH)+:DATA_WIDTH];
    assign in_row[1] = act_flat_raw_i[(1*DATA_WIDTH)+:DATA_WIDTH];

    // ==========================================
    // Hàng 0: Không trễ (Truyền thẳng qua dây)
    // ==========================================
    assign out_row[0]            = in_row[0];
    assign act_valid_skewed_o[0] = act_valid_raw_i[0];

    // ==========================================
    // Hàng 1: Trễ 4 chu kỳ (Phù hợp với PE latency của bạn)
    // ==========================================
    // Khai báo mảng 4 thanh ghi cho dữ liệu và tín hiệu hợp lệ (valid)
    logic signed [DATA_WIDTH-1:0] delay_r1 [0:3]; 
    logic                         valid_r1 [0:3];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                delay_r1[i] <= '0;
                valid_r1[i] <= 1'b0;
            end
        end else begin
            // Chuỗi thanh ghi dịch 4 bước
            // Bước 1: Nhận dữ liệu đầu vào
            delay_r1[0] <= in_row[1];
            valid_r1[0] <= act_valid_raw_i[1];
            
            // Bước 2, 3, 4: Dịch dữ liệu qua các thanh ghi tiếp theo
            delay_r1[1] <= delay_r1[0];
            valid_r1[1] <= valid_r1[0];
            
            delay_r1[2] <= delay_r1[1];
            valid_r1[2] <= valid_r1[1];
            
            delay_r1[3] <= delay_r1[2];
            valid_r1[3] <= valid_r1[2];
        end
    end
    
    // Gán đầu ra của hàng 1 bằng giá trị ở thanh ghi cuối cùng (đã trễ 4 chu kỳ)
    assign out_row[1]            = delay_r1[3];
    assign act_valid_skewed_o[1] = valid_r1[3];

    // ==========================================
    // Đóng gói lại thành mảng 1D để đưa vào Systolic Array
    // ==========================================
    assign act_skewed_o = {out_row[1], out_row[0]};

endmodule
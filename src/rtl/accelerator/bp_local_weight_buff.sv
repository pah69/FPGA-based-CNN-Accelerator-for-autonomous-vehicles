`timescale 1ns / 1ps

// ==============================================================================
// Module: npu_weight_buffer (Local Weight Buffer)
// Type: Serial-In, Parallel-Out (SIPO) Shift Register
// ==============================================================================
module bp_local_weight_buff #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 64
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Giao tiếp với Global SRAM / FSM Controller
    // ========================================
    input logic [DATA_WIDTH-1:0] sram_wgt_i,  // Dữ liệu 1 weight từ SRAM
    input logic sram_wgt_valid_i,  // Tín hiệu báo SRAM đang gửi data hợp lệ

    // ========================================
    // Giao tiếp với Systolic Array (npu_sa_64x64)
    // ========================================
    output logic [(DATA_WIDTH*SIZE)-1:0] sa_wgt_flatten_o, // Bó dây 1088-bit nối thẳng vào SA
    output logic sa_wgt_load_o  // Tín hiệu kích hoạt nạp (Pulse)
);

  // ========================================
  // Khai báo nội bộ
  // ========================================
  // Khai báo mảng 2D cho dễ quản lý, tự động flatten ở output
  logic [      SIZE-1:0][DATA_WIDTH-1:0] shift_reg;
  logic [$clog2(SIZE):0]                 count;  // Bộ đếm (đếm từ 0 đến SIZE)

  // ========================================
  // Logic Thanh ghi dịch và Bắn tín hiệu Load
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shift_reg     <= '0;
      count         <= '0;
      sa_wgt_load_o <= 1'b0;
    end else begin
      // Mặc định hạ cờ load xuống (chỉ giật lên 1 chu kỳ khi đủ dữ liệu)
      sa_wgt_load_o <= 1'b0;

      if (sram_wgt_valid_i) begin
        // Dịch dữ liệu: Đẩy dữ liệu cũ sang trái, nhét dữ liệu mới vào bên phải (Index 0)
        // Lưu ý cho FSM: Weight của Cột 63 phải được SRAM gửi vào ĐẦU TIÊN.
        shift_reg <= {shift_reg[SIZE-2:0], sram_wgt_i};

        if (count == SIZE - 1) begin
          // Đã gom đủ 64 weights
          count <= '0;  // Reset bộ đếm để chuẩn bị cho đợt nạp Layer tiếp theo
          sa_wgt_load_o <= 1'b1;  // Bắn tín hiệu Load vào Systolic Array!
        end else begin
          count <= count + 1'b1;
        end
      end
    end
  end

  // ========================================
  // Chuyển mảng 2D thành dây 1D (Flattening)
  // ========================================
  assign sa_wgt_flatten_o = shift_reg;

endmodule

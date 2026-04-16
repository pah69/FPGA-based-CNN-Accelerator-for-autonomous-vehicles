`timescale 1ns / 1ps

// ==============================================================================
// Module: npu_act_buff (Local Activation Buffer / Skewing Buffer)
// Tác dụng: Nhận mảng dữ liệu song song từ SRAM và tạo độ trễ lệch nhịp (Staggering)
//           theo đường chéo trước khi nạp vào Systolic Array.
// ==============================================================================
module bp_local_act_buff #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 64
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Giao tiếp với Global SRAM / FSM
    // ========================================
    // SRAM bơm thẳng 64 giá trị (1088-bit) mỗi clock
    input logic [(DATA_WIDTH*SIZE)-1:0] sram_act_flatten_i,
    input logic [             SIZE-1:0] sram_act_valid_i,

    // ========================================
    // Giao tiếp với Systolic Array 
    // ========================================
    output logic [(DATA_WIDTH*SIZE)-1:0] sa_act_flatten_o,
    output logic [             SIZE-1:0] sa_act_valid_o
);

  // ========================================
  // Unpack dữ liệu đầu vào (từ 1D thành 2D)
  // ========================================
  logic [DATA_WIDTH-1:0] act_in_2d[SIZE-1:0];

  always_comb begin
    for (int i = 0; i < SIZE; i++) begin
      act_in_2d[i] = sram_act_flatten_i[(i*DATA_WIDTH)+:DATA_WIDTH];
    end
  end

  // ========================================
  // Triangular Delay Lines (Mạch trễ hình tam giác)
  // ========================================
  genvar r, d;
  generate
    for (r = 0; r < SIZE; r++) begin : row_delay
      if (r == 0) begin
        // Hàng 0: Đi thẳng không trễ (Delay = 0)
        assign sa_act_flatten_o[(r*DATA_WIDTH)+:DATA_WIDTH] = act_in_2d[r];
        assign sa_act_valid_o[r]                            = sram_act_valid_i[r];

      end else begin
        // Hàng R: Cần R thanh ghi dịch (Delay = R)
        logic [DATA_WIDTH-1:0] act_shift_reg[r:1];
        logic                  val_shift_reg[r:1];

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            for (int i = 1; i <= r; i++) begin
              act_shift_reg[i] <= '0;
              val_shift_reg[i] <= 1'b0;
            end
          end else begin
            // Tầng đầu tiên hứng dữ liệu từ SRAM
            act_shift_reg[1] <= act_in_2d[r];
            val_shift_reg[1] <= sram_act_valid_i[r];

            // Các tầng tiếp theo dịch dữ liệu sang phải
            for (int i = 2; i <= r; i++) begin
              act_shift_reg[i] <= act_shift_reg[i-1];
              val_shift_reg[i] <= val_shift_reg[i-1];
            end
          end
        end

        // Ngõ ra của hàng R lấy từ tầng thanh ghi cuối cùng (tầng R)
        assign sa_act_flatten_o[(r*DATA_WIDTH)+:DATA_WIDTH] = act_shift_reg[r];
        assign sa_act_valid_o[r]                            = val_shift_reg[r];
      end
    end
  endgenerate

endmodule

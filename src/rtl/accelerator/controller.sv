`timescale 1ns / 1ps

module controller #(
    parameter int SIZE       = 32,
    parameter int ADDR_WIDTH = 10
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Cấu hình từ CPU (Memory-Mapped Registers)
    // ========================================
    input  logic                  start_i,
    output logic                  done_o,
    input  logic [ADDR_WIDTH-1:0] wgt_base_addr,  // Địa chỉ chứa Trọng số
    input  logic [ADDR_WIDTH-1:0] act_base_addr,  // Địa chỉ chứa Ảnh đầu vào
    input  logic [ADDR_WIDTH-1:0] out_base_addr,  // <--- MỚI: Địa chỉ ghi Kết quả
    input  logic [ADDR_WIDTH-1:0] act_length,

    // ========================================
    // Tín hiệu điều khiển bp_compute_engine
    // ========================================
    output logic sa_wgt_valid_o,
    output logic sa_act_valid_o,
    output logic sa_out_read_en_o,

    // ========================================
    // Tín hiệu tạo địa chỉ cho Global RAM
    // ========================================
    output logic                  ram_in_en,
    output logic [ADDR_WIDTH-1:0] ram_in_addr,

    output logic                  ram_out_en,
    output logic                  ram_out_we,
    output logic [ADDR_WIDTH-1:0] ram_out_addr,

    input logic fifo_empty_i
);

  typedef enum logic [1:0] {
    IDLE     = 2'b00,
    LOAD_WGT = 2'b01,
    COMPUTE  = 2'b10,
    DRAIN    = 2'b11
  } state_t;

  state_t state, next_state;

  logic [ADDR_WIDTH-1:0] counter;
  logic [ADDR_WIDTH-1:0] out_addr_cnt;  // Đếm số offset của output

  // 1. Máy trạng thái
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= next_state;
  end

  // 2. Chuyển trạng thái
  always_comb begin
    next_state = state;
    case (state)
      IDLE:     if (start_i) next_state = LOAD_WGT;
      LOAD_WGT: if (counter == SIZE - 1) next_state = COMPUTE;
      COMPUTE:  if (counter == act_length - 1) next_state = DRAIN;
      DRAIN:    if (out_addr_cnt == act_length) next_state = IDLE;
      // if (fifo_empty_i) next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      counter      <= '0;
      out_addr_cnt <= '0;
    end else begin
      if (state == IDLE) begin
        counter      <= '0;
        out_addr_cnt <= '0;
      end else begin
        // CHÌA KHÓA Ở ĐÂY: Reset counter khi chuẩn bị sang trạng thái mới
        if (state == LOAD_WGT && next_state == COMPUTE) begin
          counter <= '0;
        end else if (state == COMPUTE && next_state == DRAIN) begin
          counter <= '0;
        end  // Bình thường thì đếm tiến
        else if (state == LOAD_WGT || state == COMPUTE) begin
          counter <= counter + 1'b1;
        end

        // Đếm địa chỉ ngõ ra
        if (sa_out_read_en_o) begin
          out_addr_cnt <= out_addr_cnt + 1'b1;
        end
      end
    end
  end
  // // 3. Logic Đếm
  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     counter      <= '0;
  //     out_addr_cnt <= '0;
  //   end else begin
  //     if (state == IDLE) begin
  //       counter      <= '0;
  //       out_addr_cnt <= '0;
  //     end else if (state == LOAD_WGT || state == COMPUTE) begin
  //       counter <= counter + 1'b1;
  //     end

  //     if (state == COMPUTE && next_state == DRAIN) begin
  //       counter <= '0;
  //     end

  //     // Tăng offset ngõ ra mỗi khi lấy 1 hàng từ FIFO
  //     if (sa_out_read_en_o) begin
  //       out_addr_cnt <= out_addr_cnt + 1'b1;
  //     end
  //   end
  // end

  // 4. Giải mã Tín hiệu
  always_comb begin
    // sa_wgt_valid_o   = 1'b0;
    // sa_act_valid_o   = 1'b0;
    sa_out_read_en_o = 1'b0;
    done_o           = 1'b0;

    ram_in_en        = 1'b0;
    ram_in_addr      = '0;

    ram_out_en       = 1'b0;
    ram_out_we       = 1'b0;
    ram_out_addr     = '0;

    case (state)
      IDLE: begin
        if (start_i) done_o = 1'b0;
      end
      LOAD_WGT: begin
        ram_in_en   = 1'b1;
        ram_in_addr = wgt_base_addr + counter;
        // sa_wgt_valid_o = 1'b1;
      end
      COMPUTE: begin
        ram_in_en   = 1'b1;
        ram_in_addr = act_base_addr + counter;
        // sa_act_valid_o = 1'b1;

        if (!fifo_empty_i) begin
          sa_out_read_en_o = 1'b1;
          ram_out_en       = 1'b1;
          ram_out_we       = 1'b1;
          // <--- MỚI: Cộng offset vào địa chỉ cơ sở
          ram_out_addr     = out_base_addr + out_addr_cnt;
        end
      end
      DRAIN: begin
        // if (!fifo_empty_i) begin
        //   sa_out_read_en_o = 1'b1;
        //   ram_out_en       = 1'b1;
        //   ram_out_we       = 1'b1;
        //   // <--- MỚI: Cộng offset vào địa chỉ cơ sở
        //   ram_out_addr     = out_base_addr + out_addr_cnt;
        // end else begin
        //   done_o = 1'b1;
        // end
        ram_in_en   = 1'b1;
        ram_in_addr = 10'd99;
        if (!fifo_empty_i && out_addr_cnt < act_length) begin
          sa_out_read_en_o = 1'b1;
          ram_out_en       = 1'b1;
          ram_out_we       = 1'b1;
          ram_out_addr     = out_base_addr + out_addr_cnt;
        end

        // [SỬA Ở ĐÂY]: Chỉ báo DONE khi đã lấy trọn vẹn số lượng Act
        if (out_addr_cnt == act_length) begin
          done_o = 1'b1;
        end
      end
    endcase
  end

  // ========================================
  // 5. Pipeline Tín hiệu Valid (Khớp trễ 1 nhịp với RAM)
  // ========================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sa_wgt_valid_o <= 1'b0;
      sa_act_valid_o <= 1'b0;
    end else begin
      // Tín hiệu valid sẽ tự động giật lên 1 nhịp SAU KHI state chuyển trạng thái
      sa_wgt_valid_o <= (state == LOAD_WGT);
      sa_act_valid_o <= (state == COMPUTE) || (state == DRAIN);
    end
  end
endmodule

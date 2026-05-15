`timescale 1ns / 1ps

module bp_accel_core #(
    parameter int DATA_WIDTH = 17,
    parameter int SIZE       = 32,
    parameter int ADDR_WIDTH = 10
) (
    input logic clk,
    input logic rst_n,

    // ========================================
    // Giao diện Điều khiển từ CPU (Memory-Mapped)
    // ========================================
    input  logic                  start_i,
    output logic                  done_o,
    input  logic [ADDR_WIDTH-1:0] wgt_base_addr,
    input  logic [ADDR_WIDTH-1:0] act_base_addr,
    input  logic [ADDR_WIDTH-1:0] out_base_addr,  // <--- Cấu hình vùng nhớ Output
    input  logic [ADDR_WIDTH-1:0] act_length,

    // ========================================
    // Giao diện Truy cập Unified RAM của CPU
    // ========================================
    // CPU chỉ dùng được RAM khi start_i = 0 và done_o = 1
    input  logic                         cpu_ram_en,
    input  logic                         cpu_ram_we,
    input  logic [       ADDR_WIDTH-1:0] cpu_ram_addr,
    input  logic [(DATA_WIDTH*SIZE)-1:0] cpu_ram_data_i,
    output logic [(DATA_WIDTH*SIZE)-1:0] cpu_ram_data_o
);

  localparam int ROW_WIDTH = DATA_WIDTH * SIZE;  // 544 bits

  // Tín hiệu nội bộ
  logic sa_wgt_valid, sa_act_valid, sa_out_read_en;
  logic fifo_full, fifo_empty;
  logic [ ROW_WIDTH-1:0] sa_out_data;

  logic                  sa_ram_in_en;
  logic [ADDR_WIDTH-1:0] sa_ram_in_addr;
  logic                  sa_ram_out_en;
  logic                  sa_ram_out_we;
  logic [ADDR_WIDTH-1:0] sa_ram_out_addr;

  logic [ ROW_WIDTH-1:0] ram_douta;
  logic [ ROW_WIDTH-1:0] ram_doutb;

  // =========================================================================
  // BỘ PHÂN GIẢI TRUY CẬP RAM (Arbiter / Mux)
  // =========================================================================
  logic                  npu_busy;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) npu_busy <= 1'b0;
    else if (start_i) npu_busy <= 1'b1;
    else if (done_o) npu_busy <= 1'b0;
  end

  // --- CỔNG A: GHI OUTPUT (Nếu NPU chạy) / CPU ĐỌC GHI (Nếu NPU rảnh) ---
  logic                  ram_ena;
  logic                  ram_wea;
  logic [ADDR_WIDTH-1:0] ram_addra;
  logic [ ROW_WIDTH-1:0] ram_dina;

  assign ram_ena        = npu_busy ? sa_ram_out_en : cpu_ram_en;
  assign ram_wea        = npu_busy ? sa_ram_out_we : cpu_ram_we;
  assign ram_addra      = npu_busy ? sa_ram_out_addr : cpu_ram_addr;
  assign ram_dina       = npu_busy ? sa_out_data : cpu_ram_data_i;
  assign cpu_ram_data_o = ram_douta;

  // --- CỔNG B: ĐỌC INPUT CHO NPU (Chỉ dùng khi NPU chạy) ---
  logic                  ram_enb;
  logic                  ram_web;
  logic [ADDR_WIDTH-1:0] ram_addrb;
  logic [ ROW_WIDTH-1:0] ram_dinb;

  assign ram_enb   = npu_busy ? sa_ram_in_en : 1'b0;
  assign ram_web   = 1'b0;  // NPU không bao giờ ghi bằng cổng B
  assign ram_addrb = npu_busy ? sa_ram_in_addr : '0;
  assign ram_dinb  = '0;


  // =========================================================================
  // KHỞI TẠO CÁC MODULE (Instantiations)
  // =========================================================================
  bp_controller #(
      .SIZE(SIZE),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_controller (
      .clk          (clk),
      .rst_n        (rst_n),
      .start_i      (start_i),
      .wgt_base_addr(wgt_base_addr),
      .act_base_addr(act_base_addr),
      .out_base_addr(out_base_addr),  // Truyền địa chỉ ngõ ra
      .act_length   (act_length),
      .done_o       (done_o),

      .sa_wgt_valid_o  (sa_wgt_valid),
      .sa_act_valid_o  (sa_act_valid),
      .sa_out_read_en_o(sa_out_read_en),

      .ram_in_en  (sa_ram_in_en),
      .ram_in_addr(sa_ram_in_addr),

      .ram_out_en  (sa_ram_out_en),
      .ram_out_we  (sa_ram_out_we),
      .ram_out_addr(sa_ram_out_addr),

      .fifo_empty_i(fifo_empty)
  );

  bp_compute_engine #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE),
      .PSUM_WIDTH((2 * DATA_WIDTH) + 8)

  ) u_compute_engine (
      .clk  (clk),
      .rst_n(rst_n),

      .sram_wgt_i      (ram_doutb),
      .sram_wgt_valid_i(sa_wgt_valid),

      .sram_act_flatten_i(ram_doutb),
      .sram_act_valid_i  ({SIZE{sa_act_valid}}),

      .sram_read_en_i(sa_out_read_en),
      .sram_data_o   (sa_out_data),
      .fifo_full_o   (fifo_full),
      .fifo_empty_o  (fifo_empty)
  );

  bp_global_ram #(
      .DATA_WIDTH(ROW_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
      
  ) u_global_ram (
      .clk  (clk),
      .ena  (ram_ena),
      .wea  (ram_wea),
      .addra(ram_addra),
      .dina (ram_dina),
      .douta(ram_douta),
      .enb  (ram_enb),
      .web  (ram_web),
      .addrb(ram_addrb),
      .dinb (ram_dinb),
      .doutb(ram_doutb)
  );

endmodule : bp_accel_core

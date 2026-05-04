`timescale 1ns / 1ps

module tb_load_weight ();

  parameter int DATA_WIDTH = 17;
  parameter int SIZE = 32;
  parameter int ADDR_WIDTH = 10;
  localparam int ROW_WIDTH = DATA_WIDTH * SIZE;

  logic                  clk;
  logic                  rst_n;
  logic                  start_i;
  logic                  done_o;
  logic [ADDR_WIDTH-1:0] wgt_base_addr;
  logic [ADDR_WIDTH-1:0] act_base_addr, out_base_addr, act_length;

  logic cpu_ram_en, cpu_ram_we;
  logic [ADDR_WIDTH-1:0] cpu_ram_addr;
  logic [ROW_WIDTH-1:0] cpu_ram_data_i, cpu_ram_data_o;

  // =========================================================================
  // Khởi tạo Clock
  // =========================================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // =========================================================================
  // Khởi tạo DUT
  // =========================================================================
  bp_accel_core #(
      .DATA_WIDTH(DATA_WIDTH),
      .SIZE(SIZE),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) dut (
      .*
  );

  // =========================================================================
  // Task Ghi RAM
  // =========================================================================
  task write_ram(input [ADDR_WIDTH-1:0] addr, input [ROW_WIDTH-1:0] data);
    @(posedge clk);
    cpu_ram_en = 1'b1;
    cpu_ram_we = 1'b1;
    cpu_ram_addr = addr;
    cpu_ram_data_i = data;
    @(posedge clk);
    cpu_ram_en = 1'b0;
    cpu_ram_we = 1'b0;
  endtask

  // =========================================================================
  // Hàm tạo 1 hàng 544-bit với giá trị ĐỘC NHẤT cho từng cột
  // Công thức: Giá trị = (Hàng * 100) + Cột
  // =========================================================================
  function [ROW_WIDTH-1:0] pack_row(input [DATA_WIDTH-1:0] row_idx);
    logic [ROW_WIDTH-1:0] row_data;  
    for (int col = 0; col < SIZE; col++) begin
      row_data[(col*DATA_WIDTH)+:DATA_WIDTH] = (row_idx * 100) + col;
    end
    return row_data;
  endfunction

  // =========================================================================
  // Kịch bản Test Chính (Main Stimulus)
  // =========================================================================
  initial begin
    // Reset các giá trị ban đầu
    rst_n = 0;
    start_i = 0;
    cpu_ram_en = 0;
    cpu_ram_we = 0;
    wgt_base_addr = 0;
    act_base_addr = 0;
    out_base_addr = 0;
    act_length = 0;

    $display("==================================================");
    $display("[WGT-TEST] Resetting system...");
    #20 rst_n = 1;
    #10;

    // 1. NẠP 32 HÀNG TRỌNG SỐ VÀO RAM
    $display("[WGT-TEST] Nap 32 hang trong so vao RAM...");
    for (int i = 0; i < SIZE; i++) begin
      // Hàng 0 nạp 0, 1, 2... Hàng 1 nạp 100, 101, 102...
      write_ram(i, pack_row(i));
    end

    // 2. KÍCH HOẠT CONTROLLER (Chỉ quan tâm Load Weight)
    @(posedge clk);
    wgt_base_addr = 10'd0;
    start_i       = 1'b1;
    @(posedge clk);
    start_i = 1'b0;

    $display("[WGT-TEST] Controller da Start! Cho FSM nap du 32 nhip...");

    // 3. GIÁM SÁT ĐƯỜNG ỐNG (Snoop the bus)
    // Dùng vòng lặp để theo dõi 32 nhịp Load
    for (int i = 0; i < SIZE; i++) begin
      // Đợi cờ sa_wgt_load_o giật lên (Nằm sâu trong compute_engine)
      wait (dut.u_bp_compute_engine.wgt_load_to_sa == 1'b1);

      @(negedge clk);
      // Trích xuất 17-bit của từng cột tương ứng từ bus 544-bit
      $display("   -> Nhịp %0d: Cột 0 = %0d | Cột 1 = %0d | ... | Cột 31 = %0d", i,
               dut.u_bp_compute_engine.wgt_flatten_to_sa[0 +: 17],         // Cột 0
               dut.u_bp_compute_engine.wgt_flatten_to_sa[(1*17) +: 17],    // Cột 1
               dut.u_bp_compute_engine.wgt_flatten_to_sa[(31*17) +: 17]);  // Cột 31

      @(posedge clk);  // Đợi qua nhịp clock kế tiếp
    end
    
    // Đợi thêm vài nhịp để đảm bảo PE00 chốt dữ liệu an toàn trước khi kết thúc
    repeat (20) @(posedge clk);
    $display("[WGT-TEST] Da nap du 32 hang vao Systolic Array!");
    $display("==================================================");
    $finish;
  end

endmodule
`timescale 1ns / 1ps

module tb_bp_accel_core ();

  parameter int DATA_WIDTH = 17;
  parameter int SIZE = 32;
  parameter int ADDR_WIDTH = 10;
  localparam int ROW_WIDTH = DATA_WIDTH * SIZE;

  logic                  clk;
  logic                  rst_n;
  logic                  start_i;
  logic                  done_o;
  logic [ADDR_WIDTH-1:0] wgt_base_addr, act_base_addr, out_base_addr, act_length;

  logic cpu_ram_en, cpu_ram_we;
  logic [ADDR_WIDTH-1:0] cpu_ram_addr;
  logic [ROW_WIDTH-1:0] cpu_ram_data_i, cpu_ram_data_o;

  initial begin
    clk = 0; forever #5 clk = ~clk;
  end



  initial begin
    $dumpfile("test.vcd");
    $dumpvars(0, tb_bp_accel_core);
  end



  bp_accel_core #(
      .DATA_WIDTH(DATA_WIDTH), .SIZE(SIZE), .ADDR_WIDTH(ADDR_WIDTH)
  ) dut (.*);

  task write_ram(input [ADDR_WIDTH-1:0] addr, input [ROW_WIDTH-1:0] data);
    @(posedge clk);
    cpu_ram_en = 1'b1; cpu_ram_we = 1'b1; cpu_ram_addr = addr; cpu_ram_data_i = data;
    @(posedge clk);
    cpu_ram_en = 1'b0; cpu_ram_we = 1'b0;
  endtask

  // Hàm nhồi 1 giá trị giống nhau cho cả 32 cột (Dùng cho Ảnh)
  function [ROW_WIDTH-1:0] pack_row(input [DATA_WIDTH-1:0] val);
    logic [ROW_WIDTH-1:0] row_data;  
    for (int col = 0; col < SIZE; col++) begin
      row_data[(col*DATA_WIDTH)+:DATA_WIDTH] = val;
    end
    return row_data;
  endfunction

  initial begin
    rst_n = 0; start_i = 0; cpu_ram_en = 0; cpu_ram_we = 0;
    wgt_base_addr = 0; act_base_addr = 0; out_base_addr = 0; act_length = 0;

    $display("==================================================");
    #20 rst_n = 1; #10;

    // 1. XÓA RÁC RAM (Quan trọng để tránh X)
    $display("[TEST] Khởi tạo RAM (Zero-out)...");
    for (int i = 0; i < 100; i++) write_ram(i, '0);

    // 2. NẠP 32 HÀNG TRỌNG SỐ (Addr 0 -> 31)
    $display("[TEST] Nạp 32 hàng Trọng số (Tất cả = 1 để dễ tính)...");
    for (int i = 0; i < SIZE; i++) write_ram(i, pack_row(17'd1)); 

    // 3. NẠP 4 HÀNG ẢNH ĐẦU VÀO (Addr 32 -> 35)
    $display("[TEST] Nạp 4 hàng Ảnh (Giá trị: 2, 3, 4, 5)...");
    write_ram(32, pack_row(17'd2));
    write_ram(33, pack_row(17'd3));
    write_ram(34, pack_row(17'd4));
    write_ram(35, pack_row(17'd5));

    // 4. BẤM NÚT START
    $display("[TEST] FSM Start! Bắt đầu Tính toán...");
    @(posedge clk);
    wgt_base_addr = 10'd0;
    act_base_addr = 10'd32;
    out_base_addr = 10'd64; // Ghi kết quả ra từ địa chỉ 64
    act_length    = 10'd4;  // Có 4 hàng ảnh
    start_i       = 1'b1;
    
    @(posedge clk);
    start_i       = 1'b0;

    // 5. CHỜ NPU CHẠY VÀ VẮT KIỆT ĐƯỜNG ỐNG (DRAIN)
    wait (done_o == 1'b1);
    $display("[TEST] NPU đã giật cờ DONE_O ! Tính toán hoàn tất.");
    @(posedge clk);

    // 6. ĐỌC KẾT QUẢ TỪ RAM (Addr 64+)
    $display("[TEST] Đọc Kết quả Psum từ RAM:");
    for (int i = 0; i < 4; i++) begin
      @(posedge clk);
      cpu_ram_en   = 1'b1;
      cpu_ram_we   = 1'b0;
      cpu_ram_addr = 64 + i;
      
      @(posedge clk); 

      @(posedge clk);
      @(negedge clk); // Chờ nửa nhịp cho RAM nhả data
      $display("   -> Địa chỉ %0d: Cột 0 = %0d", cpu_ram_addr, cpu_ram_data_o[0 +: 17]);
    end


    repeat (30) @(posedge clk);
    $display("==================================================");
    $finish;
  end

endmodule
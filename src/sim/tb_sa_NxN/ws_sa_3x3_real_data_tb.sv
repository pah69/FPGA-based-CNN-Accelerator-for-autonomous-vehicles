`timescale 1ns / 1ps

/**
 * Systolic Array 3x3 Testbench - Real Data Version
 * * Features:
 * - Đọc dữ liệu số thực từ file txt (Weights & Normalized Images)
 * - Lượng hóa (Quantization) Float sang Fixed-point (Q8.8)
 * - Cấp dữ liệu vào Systolic Array và so sánh kết quả
 */
module ws_sa_3x3_real_data_tb ();

  // ==========================================
  // Parameters
  // ==========================================
  localparam int DATA_WIDTH = 17;
  localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;
  localparam int CLK_PERIOD = 10;
  localparam int N = 3;
  
  // Thông số Lượng hóa (Fixed-point Q8.8: 1 bit dấu, 8 bit nguyên, 8 bit thập phân)
  localparam int FRAC_BITS = 8; 

  // ==========================================
  // Signals
  // ==========================================
  logic clk;
  logic rst_n;

  logic [(DATA_WIDTH*3)-1:0] wgt_flatten_i;
  logic                      wgt_load_i;
  logic [(DATA_WIDTH*3)-1:0] act_flatten_i;
  logic [2:0]                act_valid_i;
  logic [(PSUM_WIDTH*3)-1:0] psum_flatten_o;
  logic [2:0]                psum_valid_o;

  // ==========================================
  // Test Matrices (Fixed-point hardware format)
  // ==========================================
  logic signed [DATA_WIDTH-1:0] matrix_W [N][N]; 
  logic signed [DATA_WIDTH-1:0] matrix_A [N][N]; 
  logic signed [PSUM_WIDTH-1:0] expected_Y [N][N]; 
  logic signed [PSUM_WIDTH-1:0] actual_Y [N][N]; 
  
  int out_count [N] = '{0, 0, 0}; 
  int pass_count = 0;
  int fail_count = 0;

  // ==========================================
  // File Descriptors
  // ==========================================
  int fd_weights, fd_images;

  // ==========================================
  // DUT Instantiation
  // ==========================================
  ws_sa_3x3 #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .wgt_flatten_i  (wgt_flatten_i),
      .wgt_load_i     (wgt_load_i),
      .act_flatten_i  (act_flatten_i),
      .act_valid_i    (act_valid_i),
      .psum_flatten_o (psum_flatten_o),
      .psum_valid_o   (psum_valid_o)
  );

  // ==========================================
  // Clock Generation & Output Monitor
  // ==========================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  always_ff @(posedge clk) begin
    for (int col = 0; col < N; col++) begin
      if (psum_valid_o[col]) begin
        if (out_count[col] < N) begin
          actual_Y[out_count[col]][col] = psum_flatten_o[(col*PSUM_WIDTH) +: PSUM_WIDTH];
          out_count[col]++;
        end
      end
    end
  end


  initial begin
    $dumpfile("ws_sa_3x3_real_data_tb.vcd");
    $dumpvars(0, ws_sa_3x3_real_data_tb);
  end
  // ==========================================
  // Main Sequence
  // ==========================================
  initial begin
    init_signals();
    reset_dut();

    $display("=== 1. Đọc và Lượng Hóa Dữ Liệu Thật ===");
    read_real_data();
    calculate_expected_results();

    $display("=== 2. Nạp Trọng Số (Weights) ===");
    load_weights();

    $display("=== 3. Bơm Dữ Liệu Ảnh (Activations) ===");
    feed_activations();

    $display("=== 4. Chờ đường ống xử lý ===");
    wait_for_completion();

    $display("=== 5. Kiểm tra Kết quả ===");
    check_results();
    
    repeat (50) @(posedge clk);
    $finish;
  end

  // ==========================================
  // Tasks (Các hàm xử lý)
  // ==========================================
  task init_signals();
    rst_n         = 1'b1;
    wgt_flatten_i = '0;
    wgt_load_i    = 1'b0;
    act_flatten_i = '0;
    act_valid_i   = '0;
  endtask

  task reset_dut();
    @(negedge clk);
    rst_n = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  // // Hàm đọc dữ liệu từ File
  // task read_real_data();
  //   real temp_val;
  //   int read_status;

  //   // 1. Đọc Weights
  //   fd_weights = $fopen("Float_Weights.txt", "r");
  //   if (fd_weights == 0) begin
  //       $display("LỖI: Không thể mở file Float_Weights.txt");
  //       $finish;
  //   end

  //   $display("  -> Đọc 9 params đầu tiên làm ma trận W (Q8.8)...");
  //   for (int r = 0; r < N; r++) begin
  //     for (int c = 0; c < N; c++) begin
  //       read_status = $fscanf(fd_weights, "%f", temp_val);
  //       // Lượng hóa: Float * 2^FRAC_BITS, sau đó ép kiểu sang số nguyên
  //       matrix_W[r][c] = DATA_WIDTH'($rtoi(temp_val * (1 << FRAC_BITS)));
  //     end
  //   end
  //   $fclose(fd_weights);

  //   // 2. Đọc Image (Dùng bản normalized cho độ chuẩn xác cao)
  //   fd_images = $fopen("mnist_image_normalized.txt", "r");
  //   if (fd_images == 0) begin
  //       $display("LỖI: Không thể mở file mnist_image_normalized.txt");
  //       $finish;
  //   end

  //   $display("  -> Đọc 9 pixels đầu tiên làm ma trận A (Q8.8)...");
  //   for (int r = 0; r < N; r++) begin
  //     for (int c = 0; c < N; c++) begin
  //       read_status = $fscanf(fd_images, "%f", temp_val);
  //       matrix_A[r][c] = DATA_WIDTH'($rtoi(temp_val * (1 << FRAC_BITS)));
  //     end
  //   end
  //   $fclose(fd_images);


  //   // ====================================================
  //   // THÊM ĐOẠN NÀY ĐỂ DEBUG: In ma trận A và W ra Console
  //   // ====================================================
  //   $display("----------------------------------------");
  //   $display("DEBUG MA TRẬN A (Sau khi lượng hóa Q8.8):");
  //   for (int r = 0; r < N; r++) begin
  //     $display("  Hàng %0d: %5d | %5d | %5d", r, 
  //              $signed(matrix_A[r][0]), 
  //              $signed(matrix_A[r][1]), 
  //              $signed(matrix_A[r][2]));
  //   end
  //   $display("----------------------------------------");
  // endtask

  

  task calculate_expected_results();
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        expected_Y[r][c] = '0;
        for (int k = 0; k < N; k++) begin
          expected_Y[r][c] += $signed(matrix_A[r][k]) * $signed(matrix_W[k][c]);
        end
      end
    end
  endtask

  // Logic nạp dữ liệu giữ nguyên như bản cũ
  task load_weights();
    wgt_load_i <= 1'b1;
    wgt_flatten_i <= {matrix_W[2][2], matrix_W[2][1], matrix_W[2][0]}; @(posedge clk);
    wgt_flatten_i <= {matrix_W[1][2], matrix_W[1][1], matrix_W[1][0]}; @(posedge clk);
    wgt_flatten_i <= {matrix_W[0][2], matrix_W[0][1], matrix_W[0][0]}; @(posedge clk);
    wgt_load_i <= 1'b0; wgt_flatten_i <= '0; @(posedge clk);
  endtask

  task feed_activations();
    for (int t = 0; t < 12; t++) begin
      // Kênh Hàng 0
      if (t >= 0 && t < 3) begin
        act_flatten_i[0 +: DATA_WIDTH] <= matrix_A[t][0]; act_valid_i[0] <= 1'b1;
      end else act_valid_i[0] <= 1'b0;

      // Kênh Hàng 1 (trễ 4 nhịp)
      if (t >= 4 && t < 7) begin
        act_flatten_i[DATA_WIDTH +: DATA_WIDTH] <= matrix_A[t-4][1]; act_valid_i[1] <= 1'b1;
      end else act_valid_i[1] <= 1'b0;

      // Kênh Hàng 2 (trễ 8 nhịp)
      if (t >= 8 && t < 11) begin
        act_flatten_i[DATA_WIDTH*2 +: DATA_WIDTH] <= matrix_A[t-8][2]; act_valid_i[2] <= 1'b1;
      end else act_valid_i[2] <= 1'b0;

      @(posedge clk);
    end
    act_valid_i <= 3'b0; act_flatten_i <= '0;
  endtask

  task wait_for_completion();
    repeat(100) @(posedge clk);
  endtask

  task check_results();
    $display("-------------------------------------------------");
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        if (actual_Y[r][c] === expected_Y[r][c]) begin
          $display("  ✓ PASS [Row %0d][Col %0d]: Got %d", r, c, $signed(actual_Y[r][c]));
          pass_count++;
        end else begin
          $display("  ✗ FAIL [Row %0d][Col %0d]: Got %d | Expected %d", 
                   r, c, $signed(actual_Y[r][c]), $signed(expected_Y[r][c]));
          fail_count++;
        end
      end
    end
    $display("-------------------------------------------------");
    
    if (fail_count == 0) $display(">>> ALL TESTS PASSED (REAL DATA)! <<<");
    else                 $display(">>> %0d TESTS FAILED! <<<", fail_count);
  endtask

endmodule
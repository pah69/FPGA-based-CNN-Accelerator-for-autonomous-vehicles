`timescale 1ns / 1ps

module ws_sa_3x3_full_image_tb ();

  // ==========================================
  // Parameters
  // ==========================================
  localparam int DATA_WIDTH = 17;
  localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;
  localparam int CLK_PERIOD = 10;

  localparam int N = 3;  // Cột của ma trận (3x3)

  localparam int NUM_IMAGES = 100;

  localparam int TOTAL_PIXELS = 784 * NUM_IMAGES;  // Tổng số pixel của ảnh MNIST
  localparam int NUM_ROWS = (TOTAL_PIXELS + 2) / 3;  // 784 / 3 (làm tròn lên) = 262 hàng
  localparam int FRAC_BITS = 8;  // Q8.8 Quantization
  // ==========================================
  // Signals
  // ==========================================
  logic                             clk;
  logic                             rst_n;

  logic        [(DATA_WIDTH*3)-1:0] wgt_flatten_i;
  logic                             wgt_load_i;
  logic        [(DATA_WIDTH*3)-1:0] act_flatten_i;
  logic        [               2:0] act_valid_i;
  logic        [(PSUM_WIDTH*3)-1:0] psum_flatten_o;
  logic        [               2:0] psum_valid_o;

  // ==========================================
  // Test Matrices (Mở rộng số hàng của A lên 262)
  // ==========================================
  logic signed [    DATA_WIDTH-1:0] matrix_W       [       N]              [N];
  logic signed [    DATA_WIDTH-1:0] matrix_A       [NUM_ROWS]              [N];
  logic signed [    PSUM_WIDTH-1:0] expected_Y     [NUM_ROWS]              [N];
  logic signed [    PSUM_WIDTH-1:0] actual_Y       [NUM_ROWS]              [N];

  int                               out_count      [       N] = '{0, 0, 0};
  int                               pass_count = 0;
  int                               fail_count = 0;

  // ==========================================
  // DUT Instantiation
  // ==========================================
  ws_sa_3x3 #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) dut (
      .clk           (clk),
      .rst_n         (rst_n),
      .wgt_flatten_i (wgt_flatten_i),
      .wgt_load_i    (wgt_load_i),
      .act_flatten_i (act_flatten_i),
      .act_valid_i   (act_valid_i),
      .psum_flatten_o(psum_flatten_o),
      .psum_valid_o  (psum_valid_o)
  );

  // ==========================================
  // Clock Generation & Monitor (Theo dõi luồng data)
  // ==========================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Thu thập kết quả: Giờ đây out_count sẽ chạy đến NUM_ROWS (262)
  always_ff @(posedge clk) begin
    for (int col = 0; col < N; col++) begin
      if (psum_valid_o[col]) begin
        if (out_count[col] < NUM_ROWS) begin
          actual_Y[out_count[col]][col] = psum_flatten_o[(col*PSUM_WIDTH)+:PSUM_WIDTH];
          out_count[col]++;
        end
      end
    end
  end


  initial begin
    $dumpfile("ws_sa_3x3_full_image_tb.vcd");
    $dumpvars(0, ws_sa_3x3_full_image_tb);
  end
  // ==========================================
  // Main Sequence
  // ==========================================
  initial begin
    init_signals();
    reset_dut();

    $display("=== 1. Đọc TOÀN BỘ 784 pixels ===");
    read_real_data();
    calculate_expected_results();

    $display("=== 2. Nạp Trọng Số (Weights) ===");
    load_weights();

    $display("=== 3. Bơm Dữ Liệu Ảnh (%0d Cycles) ===", NUM_ROWS);
    feed_activations();

    $display("=== 4. Chờ đường ống xử lý ===");
    wait_for_completion();

    $display("=== 5. Kiểm tra Kết quả ===");
    check_results();

    repeat (50) @(posedge clk);
    $finish;
  end

  // ==========================================
  // Tasks
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

  task read_real_data();
    real temp_val;
    int  read_status;
    int fd_weights, fd_images;
    int pixel_idx = 0;

    // 1. Đọc Weights (Giữ nguyên)
    fd_weights = $fopen("Float_Weights.txt", "r");
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        read_status = $fscanf(fd_weights, "%f", temp_val);
        matrix_W[r][c] = DATA_WIDTH'($rtoi(temp_val * (1 << FRAC_BITS)));
      end
    end
    $fclose(fd_weights);

    // 2. Đọc toàn bộ ảnh (784 pixels) vào ma trận A (262 x 3)
    fd_images = $fopen("mnist_image_normalized.txt", "r");
    for (int r = 0; r < NUM_ROWS; r++) begin
      for (int c = 0; c < N; c++) begin
        if (pixel_idx < TOTAL_PIXELS) begin
          read_status = $fscanf(fd_images, "%f", temp_val);
          matrix_A[r][c] = DATA_WIDTH'($rtoi(temp_val * (1 << FRAC_BITS)));
        end else begin
          matrix_A[r][c] = '0;  // Padding bằng số 0 cho 2 ô cuối cùng
        end
        pixel_idx++;
      end
    end
    $fclose(fd_images);
  endtask

  task calculate_expected_results();
    for (int r = 0; r < NUM_ROWS; r++) begin
      for (int c = 0; c < N; c++) begin
        expected_Y[r][c] = '0;
        for (int k = 0; k < N; k++) begin
          expected_Y[r][c] += $signed(matrix_A[r][k]) * $signed(matrix_W[k][c]);
        end
      end
    end
  endtask

  task load_weights();
    wgt_load_i <= 1'b1;
    wgt_flatten_i <= {matrix_W[2][2], matrix_W[2][1], matrix_W[2][0]};
    @(posedge clk);
    wgt_flatten_i <= {matrix_W[1][2], matrix_W[1][1], matrix_W[1][0]};
    @(posedge clk);
    wgt_flatten_i <= {matrix_W[0][2], matrix_W[0][1], matrix_W[0][0]};
    @(posedge clk);
    wgt_load_i <= 1'b0;
    wgt_flatten_i <= '0;
    @(posedge clk);
  endtask

  // Bơm dữ liệu liên tục cho đến khi hết 262 hàng
  task feed_activations();
    // Tổng thời gian = NUM_ROWS + độ trễ của Hàng cuối cùng (8 cycles) + 2 cycle đệm
    int max_time = NUM_ROWS + 10;

    for (int t = 0; t < max_time; t++) begin

      // Hàng 0
      if (t >= 0 && t < NUM_ROWS) begin
        act_flatten_i[0+:DATA_WIDTH] <= matrix_A[t][0];
        act_valid_i[0] <= 1'b1;
      end else act_valid_i[0] <= 1'b0;

      // Hàng 1 (trễ 4 nhịp)
      if (t >= 4 && t < NUM_ROWS + 4) begin
        act_flatten_i[DATA_WIDTH+:DATA_WIDTH] <= matrix_A[t-4][1];
        act_valid_i[1] <= 1'b1;
      end else act_valid_i[1] <= 1'b0;

      // Hàng 2 (trễ 8 nhịp)
      if (t >= 8 && t < NUM_ROWS + 8) begin
        act_flatten_i[DATA_WIDTH*2+:DATA_WIDTH] <= matrix_A[t-8][2];
        act_valid_i[2] <= 1'b1;
      end else act_valid_i[2] <= 1'b0;

      @(posedge clk);
    end
    act_valid_i   <= 3'b0;
    act_flatten_i <= '0;
  endtask

  task wait_for_completion();
    repeat (150) @(posedge clk);  // Cho thêm thời gian để kết quả trôi ra hết
  endtask

  task check_results();
    $display("-------------------------------------------------");

    // Lưu ý: Dùng NUM_ROWS (thay vì N) để quét toàn bộ ảnh
    for (int r = 0; r < NUM_ROWS; r++) begin
      for (int c = 0; c < N; c++) begin

        // Trạng thái PASS
        if (actual_Y[r][c] === expected_Y[r][c]) begin
          pass_count++;

          // IN THÔNG MINH: Chỉ in vùng bụng của ảnh (từ hàng 130 đến 145)
          // để bạn tận mắt thấy các giá trị khác 0 của nét chữ
          // 1. In vùng bụng của Ảnh 1 (Hàng 130 - 145)
          if (r >= 130 && r <= 145) begin
            $display("  ✓ PASS [Ảnh 1][Row %0d][Col %0d]: Got %8d", r, c, $signed(
                                                                                  actual_Y[r][c]));
          end  // 2. In vùng bụng của Ảnh 2 (Hàng 130 + 262 = 392 đến 407)
          else if (r >= 392 && r <= 407) begin
            $display("  ✓ PASS [Ảnh 2][Row %0d][Col %0d]: Got %8d", r, c, $signed(
                                                                                  actual_Y[r][c]));
          end  // 3. Ẩn phần còn lại
          else if (r == 408 && c == 0) begin
            $display("  ... (Đã ẩn các ảnh còn lại để tránh giật lag) ...");
          end

          // Trạng thái FAIL
        end else begin
          // Rất QUAN TRỌNG: Nếu có lỗi (FAIL), LUÔN LUÔN in ra để debug (không bao giờ ẩn)
          $display("  ✗ FAIL [Row %0d][Col %0d]: Got %8d | Expected %8d", r, c,
                   $signed(actual_Y[r][c]), $signed(expected_Y[r][c]));
          fail_count++;
        end

      end
    end

    // In bảng tổng kết cuối cùng
    $display("-------------------------------------------------");
    $display("  Tổng số phép tính: %0d", NUM_ROWS * N);

    if (fail_count == 0) begin
      $display(">>> ALL %0d TESTS PASSED (FULL %0d IMAGES)! <<<", pass_count, NUM_IMAGES);
    end else begin
      $display(">>> %0d TESTS FAILED! <<<", fail_count);
    end
    $display("-------------------------------------------------");
  endtask

endmodule

`timescale 1ns / 1ps

/**
 * Systolic Array 3x3 Testbench
 * * Features tested:
 * - Weight pre-loading (shifting down vertically)
 * - Skewed/Staggered activation streaming (left to right)
 * - Matrix Multiplication accuracy (A x W = Y)
 * - Output validity and data alignment
 */
module ws_sa_3x3_tb ();

  // ==========================================
  // Parameters
  // ==========================================
  localparam int DATA_WIDTH = 17;
  localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;
  localparam int CLK_PERIOD = 10;
  localparam int N = 3; // 3x3 Array

  // ==========================================
  // Signals
  // ==========================================
  logic clk;
  logic rst_n;

  // Trọng số (Weights)
  logic [(DATA_WIDTH*3)-1:0] wgt_flatten_i;
  logic                      wgt_load_i;

  // Dữ liệu đầu vào (Activations)
  logic [(DATA_WIDTH*3)-1:0] act_flatten_i;
  logic [2:0]                act_valid_i;

  // Kết quả tổng (Partial Sums)
  logic [(PSUM_WIDTH*3)-1:0] psum_flatten_o;
  logic [2:0]                psum_valid_o;

  // ==========================================
  // Test Matrices
  // ==========================================
  logic signed [DATA_WIDTH-1:0] matrix_W [N][N]; // Ma trận Trọng số (Weight)
  logic signed [DATA_WIDTH-1:0] matrix_A [N][N]; // Ma trận Dữ liệu (Activation)
  logic signed [PSUM_WIDTH-1:0] expected_Y [N][N]; // Ma trận Kết quả kỳ vọng (A x W)
  
  // Mảng lưu kết quả thực tế thu được từ thiết kế
  logic signed [PSUM_WIDTH-1:0] actual_Y [N][N]; 
  int out_count [N] = '{0, 0, 0}; // Theo dõi số lượng kết quả xuất ra trên từng cột

  int pass_count = 0;
  int fail_count = 0;

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
  // Clock Generation
  // ==========================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end
  
  initial begin
    $dumpfile("ws_sa_3x3_tb.vcd");
    $dumpvars(0, ws_sa_3x3_tb);
  end

  // ================== ========================
  // Main Test Sequence
  // ==========================================
  initial begin
    init_signals();
    reset_dut();

    $display("=== 1. Generating Test Data ===");
    generate_matrices();
    calculate_expected_results();

    $display("=== 2. Loading Weights ===");
    load_weights();

    $display("=== 3. Streaming Activations ===");
    feed_activations();

    $display("=== 4. Waiting for Output Pipeline ===");
    wait_for_completion();

    $display("=== 5. Checking Results ===");
    check_results();
    repeat (50) @(posedge clk);
    $finish;
  end

  // ==========================================
  // Output Monitor (Bắt kết quả tự động)
  // ==========================================
  // Liên tục kiểm tra tín hiệu valid ở 3 cột để bắt kết quả
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

  // ==========================================
  // Tasks (Các hàm hỗ trợ kiểm thử)
  // ==========================================

  // 1. Khởi tạo tín hiệu
  task init_signals();
    rst_n         = 1'b0;
    wgt_flatten_i = '0;
    wgt_load_i    = 1'b0;
    act_flatten_i = '0;
    act_valid_i   = '0;
  endtask

  // 2. Reset module
  task reset_dut();
    @(posedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  // 3. Tạo dữ liệu giả lập cho Ma trận A và W
  task generate_matrices();
    for (int r = 0; r < N; r++) begin
      for (int c = 0; c < N; c++) begin
        matrix_A[r][c] = (r + 1) * 2 + c;      // Ví dụ: giá trị nhỏ để dễ tính nhẩm
        matrix_W[r][c] = (c + 1) * 10 - r; 
      end
    end
  endtask

  // 4. Tính toán kết quả kỳ vọng (Phần mềm)
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

  // 5. Nạp Trọng số (Shift down)
  // Systolic Array yêu cầu nạp từ dưới lên trên. Hàng cuối (2) vào trước, rồi trôi dần xuống.
  task load_weights();
    wgt_load_i <= 1'b1;
    
    // Cycle 1: Bơm hàng cuối cùng của Ma trận W (Hàng 2)
    wgt_flatten_i <= {matrix_W[2][2], matrix_W[2][1], matrix_W[2][0]};
    @(posedge clk);
    
    // Cycle 2: Bơm hàng giữa (Hàng 1)
    wgt_flatten_i <= {matrix_W[1][2], matrix_W[1][1], matrix_W[1][0]};
    @(posedge clk);
    
    // Cycle 3: Bơm hàng đầu tiên (Hàng 0)
    wgt_flatten_i <= {matrix_W[0][2], matrix_W[0][1], matrix_W[0][0]};
    @(posedge clk);

    // Dừng nạp
    wgt_load_i <= 1'b0;
    wgt_flatten_i <= '0;
    @(posedge clk);
  endtask

  // 6. Bơm dữ liệu (Skewed/Staggered Activations)
  // Hàng 0 bắt đầu ở T=0. Hàng 1 bắt đầu ở T=1. Hàng 2 bắt đầu ở T=2.
  // Tổng thời gian bơm cho ma trận 3x3 là 5 cycles (N + N - 1)
  task feed_activations();
    for (int t = 0; t < 12; t++) begin
      
      // Kênh dữ liệu Hàng 0
      if (t >= 0 && t < 3) begin
        act_flatten_i[0 +: DATA_WIDTH] <= matrix_A[t][0];
        act_valid_i[0] <= 1'b1;
      end else begin
        act_valid_i[0] <= 1'b0;
      end

      // Kênh dữ liệu Hàng 1 (Bắt đầu trễ 1 cycle)
      if (t >= 4 && t < 7) begin
        act_flatten_i[DATA_WIDTH +: DATA_WIDTH] <= matrix_A[t-4][1];
        act_valid_i[1] <= 1'b1;
      end else begin
        act_valid_i[1] <= 1'b0;
      end

      // Kênh dữ liệu Hàng 2 (Bắt đầu trễ 2 cycles)
      if (t >= 8 && t < 11) begin
        act_flatten_i[DATA_WIDTH*2 +: DATA_WIDTH] <= matrix_A[t-8][2];
        act_valid_i[2] <= 1'b1;
      end else begin
        act_valid_i[2] <= 1'b0;
      end

      @(posedge clk);
    end
    
    // Kết thúc bơm
    act_valid_i <= 3'b0;
    act_flatten_i <= '0;
  endtask

  // 7. Chờ đường ống (Pipeline latency) đẩy hết kết quả ra ngoài
  task wait_for_completion();
    // Systolic delay (3) + PE delay (4) + Buffer margin = ~20 cycles
    repeat(100) @(posedge clk);
  endtask

  // 8. So sánh kết quả phần cứng và phần mềm
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
    
    // Kiểm tra xem số lượng kết quả bắt được có đủ 9 (3x3) hay không
    for (int i = 0; i < N; i++) begin
      if (out_count[i] != N) begin
         $display("  ✗ ERROR: Column %0d only output %0d/3 results!", i, out_count[i]);
         fail_count++;
      end
    end

    if (fail_count == 0) $display(">>> ALL TESTS PASSED! <<<");
    else                 $display(">>> %0d TESTS FAILED! <<<", fail_count);
  endtask

endmodule
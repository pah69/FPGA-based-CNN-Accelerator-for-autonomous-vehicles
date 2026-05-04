`timescale 1ns / 1ps

module tb_bp_sa_3x3 ();

  parameter int SIZE = 3;
  parameter int DATA_WIDTH = 16;
  parameter int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;
  parameter int FRAC_BITS = 16;

  parameter int NUM_IMAGES = 10;
  parameter int IMG_SIZE = 784;

  localparam int WGT_BUS_WIDTH = SIZE * DATA_WIDTH;
  localparam int ACT_BUS_WIDTH = SIZE * DATA_WIDTH;
  localparam int OUT_BUS_WIDTH = SIZE * PSUM_WIDTH;

  logic clk, rst_n;
  logic   [WGT_BUS_WIDTH-1:0] wgt_flatten_i;
  logic                       wgt_load_i;

  logic   [ACT_BUS_WIDTH-1:0] act_flatten_i;
  logic   [         SIZE-1:0] act_valid_i;

  logic   [OUT_BUS_WIDTH-1:0] psum_flatten_o;
  logic   [         SIZE-1:0] psum_valid_o;

  real                        memory_wgt     [            0 : (SIZE*SIZE)-1];
  real                        memory_img     [0 : (NUM_IMAGES * IMG_SIZE)-1];
  longint                     expected_psum  [                   0 : SIZE-1];

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  bp_sa_3x3 #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH),
      .SIZE(SIZE)
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

  task automatic read_files();
    int fd_wgt, fd_img, r1, r2;
    real temp_val;

    $display("---------------------------------------------------");
    $display("[TB-INIT] Dang doc file Float_Weights.txt...");
    fd_wgt = $fopen("Float_Weights.txt", "r");
    for (int i = 0; i < SIZE * SIZE; i++) begin
      r1 = $fscanf(fd_wgt, "%f", temp_val);
      memory_wgt[i] = temp_val;
    end
    $fclose(fd_wgt);

    $display("[TB-INIT] Dang doc file mnist_image_normalized.txt...");
    fd_img = $fopen("mnist_image_normalized.txt", "r");
    for (int i = 0; i < NUM_IMAGES * IMG_SIZE; i++) begin
      r2 = $fscanf(fd_img, "%f", temp_val);
      memory_img[i] = temp_val;
    end
    $fclose(fd_img);
    $display("[TB-INIT] Doc file HOAN TAT.");
  endtask

  function automatic logic [DATA_WIDTH-1:0] float_to_fixed(input real float_val);
    longint fixed_val;
    fixed_val = longint'(float_val * (2.0 ** FRAC_BITS));
    return fixed_val[DATA_WIDTH-1:0];
  endfunction

  task automatic load_weights();
    $display("---------------------------------------------------");
    $display("[TB-WGT] Bat dau Nap %0d hang Trong so vao SA...", SIZE);

    for (int row = SIZE - 1; row >= 0; row--) begin
      @(negedge clk);  // [QUAN TRỌNG]: Phải dùng negedge để tránh Race Condition
      wgt_load_i = 1'b1;

      for (int col = 0; col < SIZE; col++) begin
        real w_val;
        w_val = memory_wgt[row*SIZE+col];
        wgt_flatten_i[(col*DATA_WIDTH)+:DATA_WIDTH] = float_to_fixed(w_val);
      end

      $display("   -> Da nap Hang %0d", row);
    end
    @(negedge clk);  // [QUAN TRỌNG]: Phải dùng negedge
    wgt_load_i = 1'b0;
  endtask

  task automatic load_activations(input int img_idx);
    int start_pixel = (img_idx * IMG_SIZE) + 400;
    int num_cycles = SIZE * 4;

    $display("---------------------------------------------------");
    $display("[TB-ACT] Bơm Anh so %0d vao SA (Co tu dong Skew)...", img_idx);

    for (int cycle = 0; cycle < num_cycles; cycle++) begin
      @(negedge clk);  // [QUAN TRỌNG]: Phải dùng negedge!
      act_valid_i   = {SIZE{1'b1}};
      act_flatten_i = '0;

      for (int row = 0; row < SIZE; row++) begin
        int act_idx;
        act_idx = cycle - row;

        if (act_idx >= 0 && act_idx < SIZE) begin
          real a_val;
          // [ĐÃ SỬA LỖI LOGIC]: Dùng sải bước 28 của ảnh MNIST
          a_val = memory_img[start_pixel+(row*28)+act_idx];
          act_flatten_i[(row*DATA_WIDTH)+:DATA_WIDTH] = float_to_fixed(a_val);
        end
      end
      $display("   -> Cycle %0d: Bơm du lieu vao SA", cycle);
    end

    @(negedge clk);  // [QUAN TRỌNG]: Phải dùng negedge!
    act_valid_i = '0;
  endtask

  task automatic compute_expected(input int img_idx);
    int start_pixel = (img_idx * IMG_SIZE) + 400;

    for (int i = 0; i < SIZE; i++) expected_psum[i] = 0;

    for (int col = 0; col < SIZE; col++) begin
      for (int row = 0; row < SIZE; row++) begin
        real a_val, w_val;
        logic signed [(DATA_WIDTH*2)-1:0] mult_res;

        // [ĐÃ SỬA LỖI LOGIC]: Dùng sải bước 28
        a_val = memory_img[start_pixel+(row*28)+0];
        w_val = memory_wgt[row*SIZE+col];

        mult_res = $signed(float_to_fixed(a_val)) * $signed(float_to_fixed(w_val));
        expected_psum[col] += mult_res;
        expected_psum[col] = $signed(expected_psum[col][PSUM_WIDTH-1:0]);
      end
    end
  endtask

  int total_pass = 0;
  int total_fail = 0;
  task automatic check_output(input int img_idx);
    $display("---------------------------------------------------");
    $display("[TB-CHECK] Cho Ket qua Psum cua Anh %0d...", img_idx);
    for (int col = 0; col < SIZE; col++) begin
      // Biến cục bộ để phân tách luồng
      automatic int c = col;

      fork
        begin
          // [QUAN TRỌNG]: Đợi cờ valid tại negedge
          while (psum_valid_o[c] == 1'b0) @(negedge clk);

          begin
            logic signed [PSUM_WIDTH-1:0] hardware_res;

            hardware_res = psum_flatten_o[(c*PSUM_WIDTH)+:PSUM_WIDTH];

            $display("   -> Cột %0d | Hard: %0d | Soft: %0d", c, hardware_res, expected_psum[c]);

            if (hardware_res !== expected_psum[c]) begin
              $display("   [❌ LỖI] Psum khong khop tai cot %0d", c);
              total_fail++;
            end else begin
              $display("   [✅ PASS] Tuyet voi!");
              total_pass++;
            end
          end
        end
      join_none
    end

    // Đợi tất cả các luồng fork hoàn tất
    wait fork;
  endtask

  initial begin
    rst_n         = 0;
    wgt_flatten_i = 0;
    wgt_load_i    = 0;
    act_flatten_i = 0;
    act_valid_i   = 0;

    read_files();
    #20 rst_n = 1;
    #10;

    load_weights();

    for (int img = 0; img < NUM_IMAGES; img++) begin
      compute_expected(img);

      fork
        load_activations(img);
        check_output(img);
      join

      repeat (10) @(posedge clk);
    end

    $display("==================================================");
    $display("[TB-DONE] TOAN BO QUA TRINH TEST KET THUC!");
    $display("  -> TỔNG SỐ KẾT QUẢ ĐÚNG: %0d", total_pass);
    $display("  -> TỔNG SỐ KẾT QUẢ SAI : %0d", total_fail);
    $display("==================================================");
    $finish;
  end

endmodule

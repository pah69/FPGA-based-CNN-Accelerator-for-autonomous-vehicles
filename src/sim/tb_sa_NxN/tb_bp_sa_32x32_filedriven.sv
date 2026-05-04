`timescale 1ns / 1ps

module tb_bp_sa_32x32_filedriven;

  localparam int DATA_WIDTH  = 1;
  localparam int PSUM_WIDTH  = (2 * DATA_WIDTH) + 8;
  localparam int SIZE        = 32;
  localparam int IMG_W       = 28;
  localparam int IMG_H       = 28;
  localparam int IMG_PIXELS  = IMG_W * IMG_H;
  localparam int ACT_ROWS    = (IMG_PIXELS + SIZE - 1) / SIZE; // 784 -> 25 rows
  localparam int CLK_PERIOD  = 10;
  localparam int FRAC_BITS   = 8;   // Q8.8
  localparam int ROW_GAP     = 4;   // keep same stagger style as old TB
  localparam int DRAIN_CYCLES = 220;
  localparam int NUM_IMAGES_TO_TEST = 3; // set to 10000 for full run

  string WGT_FILE = "Float_Weights.txt";
  string IMG_FILE = "mnist_image_normalized.txt";

  logic clk;
  logic rst_n;

  logic [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i;
  logic                         wgt_load_i;
  logic [(DATA_WIDTH*SIZE)-1:0] act_flatten_i;
  logic [SIZE-1:0]              act_valid_i;
  logic [(PSUM_WIDTH*SIZE)-1:0] psum_flatten_o;
  logic [SIZE-1:0]              psum_valid_o;

  logic signed [DATA_WIDTH-1:0] wgt_mat [0:SIZE-1][0:SIZE-1];
  logic signed [DATA_WIDTH-1:0] act_mat [0:ACT_ROWS-1][0:SIZE-1];
  logic signed [PSUM_WIDTH-1:0] exp_mat [0:ACT_ROWS-1][0:SIZE-1];
  logic signed [PSUM_WIDTH-1:0] got_mat [0:ACT_ROWS-1][0:SIZE-1];

  real raw_wgt [0:SIZE-1][0:SIZE-1];
  real raw_img [0:IMG_PIXELS-1];

  int out_count [0:SIZE-1];
  int pass_count;
  int fail_count;
  int img_idx;
  int fd_wgt;
  int fd_img;

  bp_sa_32x32 #(
    .DATA_WIDTH (DATA_WIDTH),
    .PSUM_WIDTH (PSUM_WIDTH),
    .SIZE       (SIZE)
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

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  always_ff @(posedge clk) begin
    for (int c = 0; c < SIZE; c++) begin
      if (psum_valid_o[c] && out_count[c] < ACT_ROWS) begin
        got_mat[out_count[c]][c] <= $signed(psum_flatten_o[(c*PSUM_WIDTH)+:PSUM_WIDTH]);
        $display("[%0t] OUT col=%0d row=%0d val=%0d", $time, c, out_count[c],
                 $signed(psum_flatten_o[(c*PSUM_WIDTH)+:PSUM_WIDTH]));
        out_count[c] <= out_count[c] + 1;
      end
    end
  end

  initial begin
    $dumpfile("tb_bp_sa_32x32_filedriven.vcd");
    $dumpvars(0, tb_bp_sa_32x32_filedriven);
  end

  initial begin
    init_sig();
    rst_dut();

    open_files();
    load_wgt_file();
    show_wgt_sample();
    load_wgt_to_dut();

    for (img_idx = 0; img_idx < NUM_IMAGES_TO_TEST; img_idx++) begin
      if (!read_one_image(img_idx)) begin
        $display("[TB] stop: image file ended at image %0d", img_idx);
        break;
      end

      build_act_rows();
      calc_expected();
      clear_capture();

      $display("\n============================================================");
      $display("[TB] IMAGE %0d", img_idx);
      show_img_sample(img_idx);
      show_img_ascii(img_idx);
      feed_act();
      wait_compute_done(img_idx);
      check_out(img_idx);
    end

    close_files();
    $display("\n[TB] done");
    repeat (20) @(posedge clk);
    $finish;
  end

  task init_sig();
    rst_n         = 1'b1;
    wgt_flatten_i = '0;
    wgt_load_i    = 1'b0;
    act_flatten_i = '0;
    act_valid_i   = '0;
    pass_count    = 0;
    fail_count    = 0;
    clear_capture();
  endtask

  task clear_capture();
    for (int c = 0; c < SIZE; c++) out_count[c] = 0;
    for (int r = 0; r < ACT_ROWS; r++) begin
      for (int c = 0; c < SIZE; c++) begin
        got_mat[r][c] = '0;
      end
    end
  endtask

  task rst_dut();
    $display("[TB] reset");
    @(negedge clk);
    rst_n = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task open_files();
    fd_wgt = $fopen(WGT_FILE, "r");
    if (fd_wgt == 0) begin
      $display("[TB] ERROR: cannot open %s", WGT_FILE);
      $finish;
    end

    fd_img = $fopen(IMG_FILE, "r");
    if (fd_img == 0) begin
      $display("[TB] ERROR: cannot open %s", IMG_FILE);
      $display("[TB] Put the full MNIST text file beside the simulator run dir.");
      $finish;
    end

    $display("[TB] opened %s", WGT_FILE);
    $display("[TB] opened %s", IMG_FILE);
  endtask

  task close_files();
    if (fd_wgt) $fclose(fd_wgt);
    if (fd_img) $fclose(fd_img);
  endtask

  task load_wgt_file();
    real tmp;
    int rc;
    $display("\n[TB] load weights from file");
    for (int r = 0; r < SIZE; r++) begin
      for (int c = 0; c < SIZE; c++) begin
        rc = $fscanf(fd_wgt, "%f", tmp);
        if (rc != 1) begin
          $display("[TB] ERROR: weight read failed at r=%0d c=%0d", r, c);
          $finish;
        end
        raw_wgt[r][c] = tmp;
        wgt_mat[r][c] = q8_8(tmp);
      end
    end
  endtask

  function automatic logic signed [DATA_WIDTH-1:0] q8_8(input real x);
    int q;
    begin
      q = $rtoi(x * (1 << FRAC_BITS));
      q8_8 = DATA_WIDTH'(q);
    end
  endfunction

  task show_wgt_sample();
    $write("[TB] weights row0 raw : ");
    for (int c = 0; c < 8; c++) $write("%0.6f ", raw_wgt[0][c]);
    $write("\n");

    $write("[TB] weights row0 q8.8: ");
    for (int c = 0; c < 8; c++) $write("%0d ", $signed(wgt_mat[0][c]));
    $write("\n");
  endtask

  task pack_wgt_row(input int row_idx);
    begin
      wgt_flatten_i = '0;
      for (int c = 0; c < SIZE; c++) begin
        wgt_flatten_i[(c*DATA_WIDTH)+:DATA_WIDTH] = wgt_mat[row_idx][c];
      end
    end
  endtask

  task load_wgt_to_dut();
    $display("\n[TB] load weights to DUT");
    @(negedge clk);
    wgt_load_i = 1'b1;
    for (int r = SIZE-1; r >= 0; r--) begin
      pack_wgt_row(r);
      $display("[%0t] WGT row=%0d -> col0=%0d col1=%0d col2=%0d col3=%0d",
               $time, r,
               $signed(wgt_mat[r][0]), $signed(wgt_mat[r][1]),
               $signed(wgt_mat[r][2]), $signed(wgt_mat[r][3]));
      @(posedge clk);
      @(negedge clk);
    end
    wgt_load_i    = 1'b0;
    wgt_flatten_i = '0;
    @(posedge clk);
  endtask

  function automatic bit read_one_image(input int image_id);
    real tmp;
    int rc;
    begin
      read_one_image = 1'b1;
      for (int p = 0; p < IMG_PIXELS; p++) begin
        rc = $fscanf(fd_img, "%f", tmp);
        if (rc != 1) begin
          read_one_image = 1'b0;
          return;
        end
        raw_img[p] = tmp;
      end
      $display("[TB] image %0d loaded", image_id);
    end
  endfunction

  task build_act_rows();
    int p;
    p = 0;
    for (int r = 0; r < ACT_ROWS; r++) begin
      for (int c = 0; c < SIZE; c++) begin
        if (p < IMG_PIXELS) act_mat[r][c] = q8_8(raw_img[p]);
        else                act_mat[r][c] = '0;
        p++;
      end
    end
  endtask

  task show_img_sample(input int image_id);
    $write("[TB] image %0d raw p[0:15] : ", image_id);
    for (int i = 0; i < 16; i++) $write("%0.6f ", raw_img[i]);
    $write("\n");

    $write("[TB] image %0d q8.8 row0[0:15] : ", image_id);
    for (int i = 0; i < 16; i++) $write("%0d ", $signed(act_mat[0][i]));
    $write("\n");
  endtask

  task show_img_ascii(input int image_id);
    real px;
    string ch;
    $display("[TB] image %0d preview:", image_id);
    for (int y = 0; y < IMG_H; y++) begin
      $write("[TB] ");
      for (int x = 0; x < IMG_W; x++) begin
        px = raw_img[(y*IMG_W)+x];
        if (px > 0.75)      $write("#");
        else if (px > 0.40) $write("*");
        else if (px > 0.10) $write(".");
        else                $write(" ");
      end
      $write("\n");
    end
  endtask

  task calc_expected();
    for (int r = 0; r < ACT_ROWS; r++) begin
      for (int c = 0; c < SIZE; c++) begin
        exp_mat[r][c] = '0;
        for (int k = 0; k < SIZE; k++) begin
          exp_mat[r][c] += $signed(act_mat[r][k]) * $signed(wgt_mat[k][c]);
        end
      end
    end
  endtask

  task feed_act();
    int t_max;
    t_max = ACT_ROWS + (ROW_GAP * (SIZE-1)) + 2;
    $display("\n[TB] feed activations");

    for (int t = 0; t < t_max; t++) begin
      act_flatten_i = '0;
      act_valid_i   = '0;

      for (int row = 0; row < SIZE; row++) begin
        if ((t >= (row * ROW_GAP)) && (t < (row * ROW_GAP) + ACT_ROWS)) begin
          act_flatten_i[(row*DATA_WIDTH)+:DATA_WIDTH] = act_mat[t - (row*ROW_GAP)][row];
          act_valid_i[row] = 1'b1;
        end
      end

      if (|act_valid_i) begin
        $display("[%0t] ACT t=%0d vld=%b a0=%0d a1=%0d a2=%0d a3=%0d",
                 $time, t, act_valid_i,
                 $signed(act_flatten_i[(0*DATA_WIDTH)+:DATA_WIDTH]),
                 $signed(act_flatten_i[(1*DATA_WIDTH)+:DATA_WIDTH]),
                 $signed(act_flatten_i[(2*DATA_WIDTH)+:DATA_WIDTH]),
                 $signed(act_flatten_i[(3*DATA_WIDTH)+:DATA_WIDTH]));
      end

      @(posedge clk);
    end

    act_flatten_i = '0;
    act_valid_i   = '0;
  endtask

  function automatic bit all_outputs_done();
    begin
      all_outputs_done = 1'b1;
      for (int c = 0; c < SIZE; c++) begin
        if (out_count[c] < ACT_ROWS) all_outputs_done = 1'b0;
      end
    end
  endfunction

  task wait_compute_done(input int image_id);
    int cycles;
    cycles = 0;
    $display("\n[TB] wait compute image %0d", image_id);

    while ((cycles < DRAIN_CYCLES) && !all_outputs_done()) begin
      @(posedge clk);
      cycles++;
    end

    $display("[TB] drain cycles used = %0d", cycles);
    for (int c = 0; c < SIZE; c++) begin
      $display("[TB] out_count[%0d] = %0d", c, out_count[c]);
    end
  endtask

  task check_out(input int image_id);
    int img_pass;
    int img_fail;
    img_pass = 0;
    img_fail = 0;

    $display("\n[TB] check image %0d", image_id);

    for (int r = 0; r < ACT_ROWS; r++) begin
      for (int c = 0; c < SIZE; c++) begin
        if (got_mat[r][c] === exp_mat[r][c]) begin
          img_pass++;
        end else begin
          img_fail++;
          $display("FAIL img=%0d row=%0d col=%0d got=%0d exp=%0d",
                   image_id, r, c, $signed(got_mat[r][c]), $signed(exp_mat[r][c]));
        end
      end
    end

    pass_count += img_pass;
    fail_count += img_fail;

    $display("[TB] image %0d result: pass=%0d fail=%0d", image_id, img_pass, img_fail);
    $display("[TB] totals          : pass=%0d fail=%0d", pass_count, fail_count);
  endtask

endmodule

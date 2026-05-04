`timescale 1ns / 1ps

module tb_bp_sa_32x32;

  localparam int DW            = 16;
  localparam int PW            = (2 * DW) + 8;
  localparam int N             = 32;
  localparam int CLK_PER       = 10;
  localparam int VECS          = 8;   // number of input vectors to test
  localparam int ROW_GAP       = 4;   // row-to-row input delay
  localparam int DRAIN_CYCLES  = 220; // enough time for outputs to drain

  logic                   clk;
  logic                   rst_n;
  logic [DW*N-1:0]        wgt_i;
  logic                   wgt_ld;
  logic [DW*N-1:0]        act_i;
  logic [N-1:0]           act_v;
  logic [PW*N-1:0]        psum_o;
  logic [N-1:0]           psum_v;

  logic signed [DW-1:0]   w [0:N-1][0:N-1];
  logic signed [DW-1:0]   a [0:VECS-1][0:N-1];
  logic signed [PW-1:0]   exp_y [0:VECS-1][0:N-1];
  logic signed [PW-1:0]   got_y [0:VECS-1][0:N-1];

  int out_cnt [0:N-1];
  int pass_cnt;
  int fail_cnt;

  bp_sa_32x32 #(
    .DATA_WIDTH (DW),
    .PSUM_WIDTH (PW),
    .SIZE       (N)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .wgt_flatten_i  (wgt_i),
    .wgt_load_i     (wgt_ld),
    .act_flatten_i  (act_i),
    .act_valid_i    (act_v),
    .psum_flatten_o (psum_o),
    .psum_valid_o   (psum_v)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PER/2) clk = ~clk;
  end

  initial begin
    $dumpfile("tb_bp_sa_32x32.vcd");
    $dumpvars(0, tb_bp_sa_32x32);
  end

  always_ff @(posedge clk) begin
    for (int c = 0; c < N; c++) begin
      if (psum_v[c]) begin
        if (out_cnt[c] < VECS) begin
          got_y[out_cnt[c]][c] <= $signed(psum_o[(c*PW) +: PW]);
          $display("[%0t] OUT col=%0d vec=%0d val=%0d",
                   $time, c, out_cnt[c], $signed(psum_o[(c*PW) +: PW]));
          out_cnt[c] <= out_cnt[c] + 1;
        end
        else begin
          $display("[%0t] WARN extra output on col=%0d val=%0d",
                   $time, c, $signed(psum_o[(c*PW) +: PW]));
        end
      end
    end
  end

  initial begin
    init_tb();
    build_data();
    calc_exp();

    rst_dut();

    $display("\n================ WEIGHT LOAD ================");
    load_wgt();

    $display("\n============== ACTIVATION LOAD ==============");
    load_act();

    $display("\n================ COMPUTATION =================");
    wait_compute();

    $display("\n================ RESULT CHECK ================");
    check_out();

    repeat (20) @(posedge clk);
    $finish;
  end

  task automatic init_tb;
    begin
      rst_n    = 1'b1;
      wgt_i    = '0;
      wgt_ld   = 1'b0;
      act_i    = '0;
      act_v    = '0;
      pass_cnt = 0;
      fail_cnt = 0;

      for (int c = 0; c < N; c++) begin
        out_cnt[c] = 0;
      end

      for (int r = 0; r < VECS; r++) begin
        for (int c = 0; c < N; c++) begin
          got_y[r][c] = '0;
          exp_y[r][c] = '0;
        end
      end
    end
  endtask

  task automatic rst_dut;
    begin
      $display("[%0t] Reset start", $time);
      @(negedge clk);
      rst_n = 1'b0;
      repeat (4) @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      $display("[%0t] Reset done", $time);
    end
  endtask

  task automatic build_data;
    begin
      // weight matrix: small signed values, deterministic
      for (int r = 0; r < N; r++) begin
        for (int c = 0; c < N; c++) begin
          w[r][c] = ((r * 3 + c * 2) % 11) - 5;
        end
      end

      // activation vectors: deterministic, non-trivial
      for (int v = 0; v < VECS; v++) begin
        for (int c = 0; c < N; c++) begin
          a[v][c] = ((v * 5 + c) % 9) - 4;
        end
      end

      $display("[%0t] Data built", $time);
      $display("  W row0  : %0d %0d %0d %0d ... %0d",
               w[0][0], w[0][1], w[0][2], w[0][3], w[0][N-1]);
      $display("  W row31 : %0d %0d %0d %0d ... %0d",
               w[N-1][0], w[N-1][1], w[N-1][2], w[N-1][3], w[N-1][N-1]);
      $display("  A vec0  : %0d %0d %0d %0d ... %0d",
               a[0][0], a[0][1], a[0][2], a[0][3], a[0][N-1]);
    end
  endtask

  task automatic calc_exp;
    begin
      for (int v = 0; v < VECS; v++) begin
        for (int c = 0; c < N; c++) begin
          exp_y[v][c] = '0;
          for (int k = 0; k < N; k++) begin
            exp_y[v][c] += $signed(a[v][k]) * $signed(w[k][c]);
          end
        end
      end
      $display("[%0t] Expected results ready", $time);
    end
  endtask

  task automatic pack_wgt_row(input int r);
    begin
      for (int c = 0; c < N; c++) begin
        wgt_i[(c*DW) +: DW] = w[r][c];
      end
    end
  endtask

  task automatic load_wgt;
    begin
      // bottom row first, top row last
      @(negedge clk);
      wgt_ld = 1'b1;

      for (int r = N-1; r >= 0; r--) begin
        pack_wgt_row(r);
        $display("[%0t] WGT load row=%0d  first4={%0d,%0d,%0d,%0d}",
                 $time, r, w[r][0], w[r][1], w[r][2], w[r][3]);
        @(posedge clk);
      end

      @(negedge clk);
      wgt_ld = 1'b0;
      wgt_i  = '0;
      @(posedge clk);
      $display("[%0t] WGT load done", $time);
    end
  endtask

  task automatic drive_act_cycle(input int t);
    int vec_idx;
    begin
      act_i = '0;
      act_v = '0;

      for (int r = 0; r < N; r++) begin
        vec_idx = t - (r * ROW_GAP);
        if ((vec_idx >= 0) && (vec_idx < VECS)) begin
          act_i[(r*DW) +: DW] = a[vec_idx][r];
          act_v[r]            = 1'b1;
        end
      end
    end
  endtask

  task automatic load_act;
    int total_cycles;
    begin
      total_cycles = VECS + ((N-1) * ROW_GAP);

      for (int t = 0; t < total_cycles; t++) begin
        @(negedge clk);
        drive_act_cycle(t);

        $display("[%0t] ACT t=%0d row0=%0d v0=%0b row1=%0d v1=%0b row31=%0d v31=%0b",
                 $time,
                 t,
                 $signed(act_i[(0*DW) +: DW]),  act_v[0],
                 $signed(act_i[(1*DW) +: DW]),  act_v[1],
                 $signed(act_i[(31*DW)+: DW]),  act_v[31]);

        @(posedge clk);
      end

      @(negedge clk);
      act_i = '0;
      act_v = '0;
      @(posedge clk);
      $display("[%0t] ACT load done", $time);
    end
  endtask

  task automatic wait_compute;
    begin
      repeat (DRAIN_CYCLES) begin
        @(posedge clk);
        if (($time % 100) == 0) begin
          $display("[%0t] drain... out_cnt[0]=%0d out_cnt[15]=%0d out_cnt[31]=%0d",
                   $time, out_cnt[0], out_cnt[15], out_cnt[31]);
        end
      end
    end
  endtask

  task automatic check_out;
    begin
      for (int c = 0; c < N; c++) begin
        if (out_cnt[c] != VECS) begin
          $display("MISS col=%0d got=%0d expected=%0d", c, out_cnt[c], VECS);
          fail_cnt++;
        end
      end

      for (int v = 0; v < VECS; v++) begin
        for (int c = 0; c < N; c++) begin
          if (got_y[v][c] === exp_y[v][c]) begin
            pass_cnt++;
            if ((v < 2) && (c < 4)) begin
              $display("PASS vec=%0d col=%0d val=%0d", v, c, $signed(got_y[v][c]));
            end
          end
          else begin
            fail_cnt++;
            $display("FAIL vec=%0d col=%0d got=%0d exp=%0d",
                     v, c, $signed(got_y[v][c]), $signed(exp_y[v][c]));
          end
        end
      end

      $display("--------------------------------------------");
      $display("PASS = %0d", pass_cnt);
      $display("FAIL = %0d", fail_cnt);
      if (fail_cnt == 0) begin
        $display(">>> ALL TESTS PASSED <<<");
      end
      else begin
        $display(">>> TEST FAILED <<<");
      end
      $display("--------------------------------------------");
    end
  endtask

endmodule

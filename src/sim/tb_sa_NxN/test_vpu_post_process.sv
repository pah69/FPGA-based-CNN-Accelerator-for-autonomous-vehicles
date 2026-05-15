`timescale 1ns / 1ps

module test_vpu_post_process;

  localparam int SIZE = 2;
  localparam int ACC_WIDTH = 32;
  localparam int OUT_WIDTH = 8;
  localparam int CLK_PERIOD = 10;

  localparam int ACT_BYPASS = 0;
  localparam int ACT_RELU   = 1;
  localparam int POOL_BYPASS = 0;
  localparam int POOL_MAX    = 1;
  localparam int POOL_AVG    = 2;

  logic clk;
  logic rst_n;

  logic signed [(ACC_WIDTH*SIZE)-1:0] relu_acc_i;
  logic                               relu_valid_i;
  logic                               relu_done_i;
  logic signed [(OUT_WIDTH*SIZE)-1:0] relu_data_o;
  logic                               relu_valid_o;
  logic                               relu_done_o;

  logic signed [(ACC_WIDTH*SIZE)-1:0] max_acc_i;
  logic                               max_valid_i;
  logic                               max_done_i;
  logic signed [(OUT_WIDTH*SIZE)-1:0] max_data_o;
  logic                               max_valid_o;
  logic                               max_done_o;

  logic signed [(ACC_WIDTH*SIZE)-1:0] avg_acc_i;
  logic                               avg_valid_i;
  logic                               avg_done_i;
  logic signed [(OUT_WIDTH*SIZE)-1:0] avg_data_o;
  logic                               avg_valid_o;
  logic                               avg_done_o;

  int test_count;
  int pass_count;
  int fail_count;

  vector_processing_unit_v2 #(
      .SIZE             (SIZE),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACT_WIDTH        (ACC_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_RELU),
      .NORM_SHIFT       (2),
      .NORM_ROUND_ENABLE(1'b1),
      .POOL_MODE        (POOL_BYPASS),
      .POOL_WINDOW      (2)
  ) dut_relu_norm (
      .clk           (clk),
      .rst_n         (rst_n),
      .acc_flatten_i (relu_acc_i),
      .acc_valid_i   (relu_valid_i),
      .done_i        (relu_done_i),
      .data_flatten_o(relu_data_o),
      .data_valid_o  (relu_valid_o),
      .done_o        (relu_done_o)
  );

  vector_processing_unit_v2 #(
      .SIZE             (SIZE),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACT_WIDTH        (ACC_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_BYPASS),
      .NORM_SHIFT       (0),
      .NORM_ROUND_ENABLE(1'b1),
      .POOL_MODE        (POOL_MAX),
      .POOL_WINDOW      (2)
  ) dut_max_pool (
      .clk           (clk),
      .rst_n         (rst_n),
      .acc_flatten_i (max_acc_i),
      .acc_valid_i   (max_valid_i),
      .done_i        (max_done_i),
      .data_flatten_o(max_data_o),
      .data_valid_o  (max_valid_o),
      .done_o        (max_done_o)
  );

  vector_processing_unit_v2 #(
      .SIZE             (SIZE),
      .ACC_WIDTH        (ACC_WIDTH),
      .ACT_WIDTH        (ACC_WIDTH),
      .OUT_WIDTH        (OUT_WIDTH),
      .ACT_MODE         (ACT_BYPASS),
      .NORM_SHIFT       (0),
      .NORM_ROUND_ENABLE(1'b1),
      .POOL_MODE        (POOL_AVG),
      .POOL_WINDOW      (2)
  ) dut_avg_pool (
      .clk           (clk),
      .rst_n         (rst_n),
      .acc_flatten_i (avg_acc_i),
      .acc_valid_i   (avg_valid_i),
      .done_i        (avg_done_i),
      .data_flatten_o(avg_data_o),
      .data_valid_o  (avg_valid_o),
      .done_o        (avg_done_o)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  function automatic logic signed [(ACC_WIDTH*SIZE)-1:0] pack_acc_pair(
      input logic signed [ACC_WIDTH-1:0] lane0,
      input logic signed [ACC_WIDTH-1:0] lane1
  );
    pack_acc_pair = {lane1, lane0};
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] get_lane(
      input logic signed [(OUT_WIDTH*SIZE)-1:0] data_flatten,
      input int lane
  );
    get_lane = data_flatten[(lane*OUT_WIDTH)+:OUT_WIDTH];
  endfunction

  task automatic print_header(input string title);
    $display("");
    $display("============================================================");
    $display("%s", title);
    $display("============================================================");
  endtask

  task automatic display_relu_norm_state(input string tag);
    $display("[%0t] %s", $time, tag);
    $display("  input : valid=%b done=%b acc={lane1:%0d,lane0:%0d}",
             relu_valid_i, relu_done_i,
             $signed(relu_acc_i[(1*ACC_WIDTH)+:ACC_WIDTH]),
             $signed(relu_acc_i[(0*ACC_WIDTH)+:ACC_WIDTH]));
    $display("  output: valid=%b done=%b data={lane1:%0d,lane0:%0d}",
             relu_valid_o, relu_done_o,
             $signed(get_lane(relu_data_o, 1)),
             $signed(get_lane(relu_data_o, 0)));
  endtask

  task automatic display_max_pool_state(input string tag);
    $display("[%0t] %s", $time, tag);
    $display("  input : valid=%b done=%b acc={lane1:%0d,lane0:%0d}",
             max_valid_i, max_done_i,
             $signed(max_acc_i[(1*ACC_WIDTH)+:ACC_WIDTH]),
             $signed(max_acc_i[(0*ACC_WIDTH)+:ACC_WIDTH]));
    $display("  output: valid=%b done=%b data={lane1:%0d,lane0:%0d}",
             max_valid_o, max_done_o,
             $signed(get_lane(max_data_o, 1)),
             $signed(get_lane(max_data_o, 0)));
  endtask

  task automatic display_avg_pool_state(input string tag);
    $display("[%0t] %s", $time, tag);
    $display("  input : valid=%b done=%b acc={lane1:%0d,lane0:%0d}",
             avg_valid_i, avg_done_i,
             $signed(avg_acc_i[(1*ACC_WIDTH)+:ACC_WIDTH]),
             $signed(avg_acc_i[(0*ACC_WIDTH)+:ACC_WIDTH]));
    $display("  output: valid=%b done=%b data={lane1:%0d,lane0:%0d}",
             avg_valid_o, avg_done_o,
             $signed(get_lane(avg_data_o, 1)),
             $signed(get_lane(avg_data_o, 0)));
  endtask

  task automatic expect_flag(input string label, input logic condition);
    test_count++;
    if (condition) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s", label);
    end
  endtask

  task automatic expect_out_eq(
      input string label,
      input logic signed [OUT_WIDTH-1:0] actual,
      input logic signed [OUT_WIDTH-1:0] expected
  );
    test_count++;
    if (actual === expected) begin
      pass_count++;
    end else begin
      fail_count++;
      $display("FAIL: %s got=%0d expected=%0d", label, $signed(actual), $signed(expected));
    end
  endtask

  task automatic init_signals();
    rst_n        = 1'b0;
    relu_acc_i   = '0;
    relu_valid_i = 1'b0;
    relu_done_i  = 1'b0;
    max_acc_i    = '0;
    max_valid_i  = 1'b0;
    max_done_i   = 1'b0;
    avg_acc_i    = '0;
    avg_valid_i  = 1'b0;
    avg_done_i   = 1'b0;
    test_count   = 0;
    pass_count   = 0;
    fail_count   = 0;
  endtask

  task automatic reset_duts();
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
  endtask

  task automatic drive_relu_norm(
      input logic signed [ACC_WIDTH-1:0] lane0,
      input logic signed [ACC_WIDTH-1:0] lane1,
      input logic done
  );
    @(negedge clk);
    relu_acc_i   = pack_acc_pair(lane0, lane1);
    relu_valid_i = 1'b1;
    relu_done_i  = done;
    @(posedge clk);
    #1;
    display_relu_norm_state("drive ReLU/normalizer sample");
    @(negedge clk);
    relu_acc_i   = '0;
    relu_valid_i = 1'b0;
    relu_done_i  = 1'b0;
  endtask

  task automatic drive_max_pool(
      input logic signed [ACC_WIDTH-1:0] lane0,
      input logic signed [ACC_WIDTH-1:0] lane1,
      input logic done
  );
    @(negedge clk);
    max_acc_i   = pack_acc_pair(lane0, lane1);
    max_valid_i = 1'b1;
    max_done_i  = done;
    @(posedge clk);
    #1;
    display_max_pool_state("drive max-pool sample");
    @(negedge clk);
    max_acc_i   = '0;
    max_valid_i = 1'b0;
    max_done_i  = 1'b0;
  endtask

  task automatic drive_avg_pool(
      input logic signed [ACC_WIDTH-1:0] lane0,
      input logic signed [ACC_WIDTH-1:0] lane1,
      input logic done
  );
    @(negedge clk);
    avg_acc_i   = pack_acc_pair(lane0, lane1);
    avg_valid_i = 1'b1;
    avg_done_i  = done;
    @(posedge clk);
    #1;
    display_avg_pool_state("drive avg-pool sample");
    @(negedge clk);
    avg_acc_i   = '0;
    avg_valid_i = 1'b0;
    avg_done_i  = 1'b0;
  endtask

  task automatic wait_relu_output();
    int timeout;
    timeout = 0;
    while (!relu_valid_o && (timeout < 20)) begin
      @(posedge clk);
      #1;
      timeout++;
    end
    expect_flag("ReLU/normalizer output valid", relu_valid_o);
    display_relu_norm_state("capture ReLU/normalizer output");
  endtask

  task automatic wait_max_output();
    int timeout;
    timeout = 0;
    while (!max_valid_o && (timeout < 30)) begin
      @(posedge clk);
      #1;
      timeout++;
    end
    expect_flag("max-pool output valid", max_valid_o);
    display_max_pool_state("capture max-pool output");
  endtask

  task automatic wait_avg_output();
    int timeout;
    timeout = 0;
    while (!avg_valid_o && (timeout < 30)) begin
      @(posedge clk);
      #1;
      timeout++;
    end
    expect_flag("avg-pool output valid", avg_valid_o);
    display_avg_pool_state("capture avg-pool output");
  endtask

  task automatic test_relu_normalize_saturate();
    print_header("TEST: VPU ReLU + normalize + saturation");

    drive_relu_norm(32'sd19, -32'sd5, 1'b1);
    wait_relu_output();

    expect_out_eq("lane0 ReLU 19 rounded >> 2", get_lane(relu_data_o, 0), 8'sd5);
    expect_out_eq("lane1 ReLU negative clamps to zero", get_lane(relu_data_o, 1), 8'sd0);
    expect_flag("done propagates through bypass pool", relu_done_o);

    drive_relu_norm(32'sd600, 32'sd508, 1'b1);
    wait_relu_output();

    expect_out_eq("lane0 saturates positive int8", get_lane(relu_data_o, 0), 8'sd127);
    expect_out_eq("lane1 rounds 508 >> 2 to 127", get_lane(relu_data_o, 1), 8'sd127);
    expect_flag("done propagates on saturated sample", relu_done_o);
  endtask

  task automatic test_max_pool();
    print_header("TEST: VPU max pooling");

    drive_max_pool(32'sd3, -32'sd4, 1'b0);
    repeat (6) begin
      @(posedge clk);
      #1;
      expect_flag("max pool does not output before window fills", max_valid_o == 1'b0);
    end

    drive_max_pool(32'sd9, 32'sd2, 1'b1);
    wait_max_output();

    expect_out_eq("max pool lane0", get_lane(max_data_o, 0), 8'sd9);
    expect_out_eq("max pool lane1", get_lane(max_data_o, 1), 8'sd2);
    expect_flag("max pool done asserted on final sample", max_done_o);
  endtask

  task automatic test_avg_pool();
    print_header("TEST: VPU average pooling");

    drive_avg_pool(32'sd8, -32'sd6, 1'b0);
    repeat (6) begin
      @(posedge clk);
      #1;
      expect_flag("avg pool does not output before window fills", avg_valid_o == 1'b0);
    end

    drive_avg_pool(32'sd2, 32'sd4, 1'b1);
    wait_avg_output();

    expect_out_eq("avg pool lane0", get_lane(avg_data_o, 0), 8'sd5);
    expect_out_eq("avg pool lane1 truncates signed average toward zero", get_lane(avg_data_o, 1), -8'sd1);
    expect_flag("avg pool done asserted on final sample", avg_done_o);
  endtask

  initial begin
    init_signals();
    reset_duts();

    test_relu_normalize_saturate();
    test_max_pool();
    test_avg_pool();

    $display("test_vpu_post_process: checks=%0d pass=%0d fail=%0d",
             test_count, pass_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "test_vpu_post_process failed");
    end
    $finish;
  end

endmodule : test_vpu_post_process

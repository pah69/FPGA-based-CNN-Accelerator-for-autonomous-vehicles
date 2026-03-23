`timescale 1ns / 1ps

module tb_top;

  // Parameters
  localparam DATA_WIDTH = 17;
  localparam ADDR_WIDTH = 16;
  localparam MAC_PIPELINE_DEPTH = 4;
  localparam CLK_PERIOD = 10;

  // Signals
  logic clk = 0;
  logic rst_n;

  // standard signals
  logic signed [DATA_WIDTH-1:0] activation_i, activation_o, weight_i;
  logic signed [2*DATA_WIDTH:0] result_o;
  logic        [ADDR_WIDTH-1:0] weight_addr;
  logic weight_we, valid_in, start, acc_clear, valid_out;

  // Instantiate
  pe #(
      .DATA_WIDTH        (DATA_WIDTH),
      .ADDR_WIDTH        (ADDR_WIDTH),
      .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
  ) dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .activation_i(activation_i),
      .activation_o(activation_o),
      .weight_we   (weight_we),
      .weight_addr (weight_addr),
      .weight_i    (weight_i),
      .valid_in    (valid_in),
      .start       (start),
      .acc_clear   (acc_clear),
      .valid_out   (valid_out),
      .result_o    (result_o)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #10 clk = ~clk;  // 100 MHz clock
  end

  initial begin
    $display(" -----------------------");
    $display("  DUMP VCD ENABLED ");
    $display(" -----------------------");
    $dumpfile("pe_test.vcd");
    $dumpvars;
    $dumpon;
  end

  // =========================================================================
  // Test 1: Apply Reset Test
  // =========================================================================
  task test_apply_reset();
    $display("\n[%0t] === STARTING RESET TEST ===", $time);
    rst_n        <= 1'b0;
    activation_i <= '0;
    weight_we    <= 1'b0;
    weight_addr  <= '0;
    weight_i     <= '0;
    valid_in     <= 1'b0;
    start        <= 1'b0;
    acc_clear    <= 1'b0;

    // Synchronous reset delay
    repeat (5) @(negedge clk);
    rst_n <= 1'b1;
    $display("[%0t] === Reset Complete ===", $time);
  endtask

  // =========================================================================
  // Test 2: Load Inputs Test (Weights)
  // =========================================================================
  task test_load_inputs();
    $display("\n[%0t] === LOADING WEIGHTS INTO BRAM ===", $time);

    @(posedge clk);
    weight_we <= 1'b1;
    weight_addr <= 16'd0;
    weight_i <= 17'sd2;
    // weight_i <= $random;
    @(posedge clk);
    weight_addr <= 16'd1;
    weight_i <= -17'sd3;
    // weight_i <= $random;
    @(posedge clk);
    weight_addr <= 16'd2;
    weight_i <= 17'sd5;
    // weight_i <= $random;

    @(posedge clk);
    weight_we <= 1'b0;
    $display("[%0t] === Weight Loading Complete ===", $time);
  endtask

  // =========================================================================
  // Test 3: Computing
  // =========================================================================
  task test_computing();
    $display("\n[%0t] === STARTING COMPUTE TEST ===", $time);

    // Request Weight 0
    @(posedge clk);
    weight_addr <= 16'd0;

    // Drive Act 0, Request Weight 1, Assert Start
    @(posedge clk);
    activation_i <= 17'sd10;
    valid_in <= 1'b1;
    start <= 1'b1;
    weight_addr <= 16'd1;

    // Drive Activation 1, Request Weight 2, De-assert Start
    @(posedge clk);
    activation_i <= 17'sd20;
    start <= 1'b0;
    weight_addr <= 16'd2;

    // Drive Act 2
    @(posedge clk);
    activation_i <= 17'sd30;

    // End seq
    @(posedge clk);
    valid_in <= 1'b0;
    activation_i <= '0;

    // Wait
    repeat (6) @(posedge clk);
    $display("\n[%0t] === COMPUTE TEST COMPLETE ===", $time);
  endtask

  // =========================================================================
  // MONITOR
  // =========================================================================
  always_ff @(posedge clk) begin
    if (valid_out) begin
      $display(
          "    ---> [%0t] OUTPUT: Valid_out = 1 | Forwarded Act_o = %0d | Accumulator Result = %0d",
          $time, activation_o, result_o);
    end
  end

  // Test Sequence 
  initial begin
    test_apply_reset();
    repeat (2) @(posedge clk);

    test_load_inputs();
    repeat (2) @(posedge clk);

    test_computing();
    repeat (10) @(posedge clk);

    $display("\nSimulation Finished\n");
    $finish;
  end

endmodule

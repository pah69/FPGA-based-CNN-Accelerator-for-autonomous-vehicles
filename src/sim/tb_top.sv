`timescale 1ns / 1ps

module tb_top;

  // --- Parameters ---
  localparam DATA_WIDTH = 17;
  localparam ADDR_WIDTH = 16;
  localparam MAC_PIPELINE_DEPTH = 4;
  localparam CLK_PERIOD = 10;

  // --- Signals ---
  logic clk = 0;
  logic rst_n;

  // Grouped standard signals
  logic signed [DATA_WIDTH-1:0] activation_i, activation_o, weight_i;
  logic signed [2*DATA_WIDTH:0] result_o;
  logic [ADDR_WIDTH-1:0] weight_addr;
  logic weight_we, valid_in, start, acc_clear, valid_out;

  // --- DUT Instantiation ---
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .activation_i(activation_i),
      .activation_o(activation_o),
      .weight_we(weight_we),
      .weight_addr(weight_addr),
      .weight_i(weight_i),
      .valid_in(valid_in),
      .start(start),
      .acc_clear(acc_clear),
      .valid_out(valid_out),
      .result_o(result_o)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #10 clk = ~clk;  // 100 MHz clock
  end

  
  // =========================================================================
  // TASK 1: Apply Reset Test
  // =========================================================================
  task test_apply_reset();
    $display("\n[%0t] === STARTING RESET TEST ===", $time);
    rst_n        = 1'b0;
    activation_i = '0;
    weight_we    = 1'b0;
    weight_addr  = '0;
    weight_i     = '0;
    valid_in     = 1'b0;
    start        = 1'b0;
    acc_clear    = 1'b0;

    // Synchronous reset delay
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    $display("[%0t] Reset Complete.", $time);
  endtask

  // =========================================================================
  // TASK 2: Load Inputs Test (Weights)
  // =========================================================================
  task test_load_inputs();
    $display("\n[%0t] === LOADING WEIGHTS INTO BRAM ===", $time);

    @(posedge clk);
    weight_we = 1'b1;
    weight_addr = 16'd0;
    weight_i = 17'sd2;
    @(posedge clk);
    weight_addr = 16'd1;
    weight_i = -17'sd3;
    @(posedge clk);
    weight_addr = 16'd2;
    weight_i = 17'sd5;

    @(posedge clk);
    weight_we = 1'b0;
    $display("[%0t] Weight Loading Complete.", $time);
  endtask

  // =========================================================================
  // TASK 3: Computing Test (Streaming Activations)
  // =========================================================================
  task test_computing();
    $display("\n[%0t] === STARTING COMPUTE TEST ===", $time);

    // Cycle 0: Request Weight 0
    @(posedge clk);
    weight_addr = 16'd0;

    // Cycle 1: Drive Act 0, Request Weight 1, Assert Start
    @(posedge clk);
    activation_i = 17'sd10;
    valid_in = 1'b1;
    start = 1'b1;
    weight_addr = 16'd1;

    // Cycle 2: Drive Act 1, Request Weight 2, De-assert Start
    @(posedge clk);
    activation_i = 17'sd20;
    start = 1'b0;
    weight_addr = 16'd2;

    // Cycle 3: Drive Act 2
    @(posedge clk);
    activation_i = 17'sd30;

    // Cycle 4: End stream
    @(posedge clk);
    valid_in = 1'b0;
    activation_i = '0;

    // Wait for pipeline to drain
    repeat (6) @(posedge clk);
    $display("\n[%0t] === COMPUTE TEST COMPLETE ===", $time);
  endtask

  // =========================================================================
  // DEBUG MONITOR
  // =========================================================================
  always_ff @(posedge clk) begin
    if (valid_out) begin
      $display(
          "    ---> [%0t] OUTPUT: Valid_out = 1 | Forwarded Act_o = %0d | Accumulator Result = %0d",
          $time, activation_o, result_o);
    end
  end

  // --- Main Test Sequence ---
  initial begin
    test_apply_reset();
    repeat (2) @(posedge clk);  // Synchronous delay between tests

    test_load_inputs();
    repeat (2) @(posedge clk);

    test_computing();

    repeat (10) @(posedge clk);  // Final buffer before finishing
    $display("\nSimulation Finished Successfully.");
    $finish;
  end
  
  initial begin
    $display(" -----------------------");
    $display("  DUMP VCD ENABLED ");
    $display(" -----------------------");
    $dumpfile("pe_test.vcd");
    $dumpvars;
    $dumpon;
  end
endmodule

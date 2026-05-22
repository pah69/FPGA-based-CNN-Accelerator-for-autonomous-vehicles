

`timescale 1ns / 1ps

/**
 * Processing Element (PE) Testbench - FIXED VERSION
 * 
 * Fixes from original:
 * 1. Proper pipeline latency accounting (multiplier 3 cycles + output register 1 = 4 total)
 * 2. Correct validity signal propagation through pipeline
 * 3. Proper waiting for results before checking
 */
module pe_tb2 ();

  // Parameters
  localparam int DATA_WIDTH = 17;
  localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;  // 42 bits
  localparam int CLK_PERIOD = 10;
  localparam int PIPELINE_LATENCY = 4;  // 3 mult + 1 output register

  // Test signals
  logic clk;
  logic rst_n;

  // Activation stream
  logic signed [DATA_WIDTH-1:0] act_i;
  logic act_valid_i;
  logic signed [DATA_WIDTH-1:0] act_o;
  logic act_valid_o;

  // Partial sum stream
  logic signed [PSUM_WIDTH-1:0] psum_i;
  logic psum_valid_i;
  logic signed [PSUM_WIDTH-1:0] psum_o;
  logic psum_valid_o;

  // Weight
  logic signed [DATA_WIDTH-1:0] weight_i;
  logic weight_load_i;
  logic signed [DATA_WIDTH-1:0] weight_o;

  // Test tracking
  logic signed [PSUM_WIDTH-1:0] expected_results[$];
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  // Instantiate PE
  pe #(
      .DATA_WIDTH(DATA_WIDTH),
      .PSUM_WIDTH(PSUM_WIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .act_i(act_i),
      .act_valid_i(act_valid_i),
      .act_o(act_o),
      .act_valid_o(act_valid_o),
      .psum_i(psum_i),
      .psum_valid_i(psum_valid_i),
      .psum_o(psum_o),
      .psum_valid_o(psum_valid_o),
      .weight_i(weight_i),
      .weight_load_i(weight_load_i),
      .weight_o(weight_o)
  );

  // Clock generation
  initial begin
    clk = '0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Main test sequence
  initial begin
    // Initialize
    rst_n = '0;
    act_i = '0;
    act_valid_i = '0;
    psum_i = '0;
    psum_valid_i = '0;
    weight_i = '0;
    weight_load_i = '0;

    // Reset release
    @(posedge clk);
    rst_n = '1;
    @(posedge clk);

    // Load weight into PE
    $display("=== Loading Weight ===");
    weight_i = 17'd10;
    weight_load_i = 1'b1;
    @(posedge clk);
    weight_load_i = 1'b0;
    @(posedge clk);
    $display("  Weight loaded: %d\n", $signed(weight_o));

    // Test 1: Simple single MAC
    $display("=== Test 1: Single MAC Operation ===");
    $display("  weight=10, activation=5, psum=100");
    $display("  Expected: 100 + (10×5) = 150");
    test_single_mac(17'd5, 42'd100, 42'd150);

    // Test 2: Negative values
    $display("\n=== Test 2: Negative Activation ===");
    $display("  weight=10, activation=-3, psum=100");
    $display("  Expected: 100 + (10×-3) = 70");
    test_single_mac(-17'd3, 42'd100, 42'd70);

    // Test 3: Negative weight (requires reload)
    $display("\n=== Test 3: Negative Weight ===");
    weight_i = -17'd5;
    weight_load_i = 1'b1;
    @(posedge clk);
    weight_load_i = 1'b0;
    @(posedge clk);
    $display("  weight=-5, activation=8, psum=50");
    $display("  Expected: 50 + (-5×8) = 10");
    test_single_mac(17'd8, 42'd50, 42'd10);

    // Test 4: Continuous stream (multiple PEs worth of data)
    $display("\n=== Test 4: Continuous Stream (8 MACs) ===");
    weight_i = 17'd7;
    weight_load_i = 1'b1;
    @(posedge clk);
    weight_load_i = 1'b0;
    @(posedge clk);

    // Feed 8 data points
    for (int i = 0; i < 8; i++) begin
      logic signed [DATA_WIDTH-1:0] act_val = 17'sd1 + i;
      logic signed [PSUM_WIDTH-1:0] psum_val = 42'sd0 + (i * 100);
      logic signed [PSUM_WIDTH-1:0] expected = psum_val + (42'sd7 * act_val);

      @(posedge clk);
      act_i <= act_val;
      psum_i <= psum_val;
      act_valid_i <= 1'b1;
      psum_valid_i <= 1'b1;

      expected_results.push_back(expected);

      $display("  Cycle %0d: act=%3d, psum=%4d, expect=%4d", 
               i, $signed(act_val), $signed(psum_val), $signed(expected));
    end

    // Stop feeding data
    @(posedge clk);
    act_valid_i <= 1'b0;
    psum_valid_i <= 1'b0;

    // Wait for results to pipeline out
    // First result appears PIPELINE_LATENCY + 1 cycles after first input
    // All 8 results appear over the next 8 cycles
    repeat (PIPELINE_LATENCY + 10) @(posedge clk);

    // Verify continuous stream results
    check_continuous_results();

    // Summary
    $display("\n=== Test Summary ===");
    $display("  Total tests: %d", test_count);
    $display("  Passed: %d", pass_count);
    $display("  Failed: %d", fail_count);

    if (fail_count == 0) begin
      $display("✓ All tests PASSED!");
    end else begin
      $display("✗ %d test(s) FAILED!", fail_count);
    end

    #100;
    $finish;
  end

  // Task: test single MAC with known result
  task test_single_mac(
      input logic signed [DATA_WIDTH-1:0] act_val,
      input logic signed [PSUM_WIDTH-1:0] psum_val,
      input logic signed [PSUM_WIDTH-1:0] expected
  );
    test_count++;

    // Cycle 0: Send activation and psum
    @(posedge clk);
    act_i <= act_val;
    psum_i <= psum_val;
    act_valid_i <= 1'b1;
    psum_valid_i <= 1'b1;

    // Cycle 1: Stop feeding
    @(posedge clk);
    act_valid_i <= 1'b0;
    psum_valid_i <= 1'b0;

    // Multiplier: latency = 3 cycles (acts on cycle 0, outputs at cycle 3)
    // Psum delay: 3 stages (arrives at adder at cycle 3)
    // Output register: cycles 3→4
    // Result appears at cycle 4 (PIPELINE_LATENCY cycles after input)
    
    repeat (PIPELINE_LATENCY) @(posedge clk);

    // Now check the result
    @(posedge clk);
    if (psum_valid_o) begin
      if (psum_o == expected) begin
        $display("  ✓ PASS: Got %d (expected %d)", $signed(psum_o), $signed(expected));
        pass_count++;
      end else begin
        $display("  ✗ FAIL: Got %d, expected %d", $signed(psum_o), $signed(expected));
        fail_count++;
      end
    end else begin
      $display("  ✗ FAIL: psum_valid_o was low! Got %d, expected %d", 
               $signed(psum_o), $signed(expected));
      fail_count++;
    end
  endtask

  // Task: verify continuous stream results
  task check_continuous_results();
    logic signed [PSUM_WIDTH-1:0] expected;
    int result_count = 0;

    $display("  Checking continuous stream results:");

    // Results start appearing after PIPELINE_LATENCY cycles
    // Then one result per cycle
    for (int i = 0; i < expected_results.size() + 2; i++) begin
      @(posedge clk);

      if (psum_valid_o && result_count < expected_results.size()) begin
        expected = expected_results[result_count];
        test_count++;

        if (psum_o == expected) begin
          $display("    Result[%0d]: %d ✓", result_count, $signed(psum_o));
          pass_count++;
        end else begin
          $display("    Result[%0d]: Got %d, expected %d ✗", 
                   result_count, $signed(psum_o), $signed(expected));
          fail_count++;
        end
        result_count++;
      end
    end

    if (result_count < expected_results.size()) begin
      $display("    Warning: Only got %d results, expected %d", 
               result_count, expected_results.size());
    end
  endtask

  // Waveform dumping (optional)
  initial begin
    $dumpfile("pe_tb.vcd");
    $dumpvars(0, pe_tb);
  end

endmodule
`timescale 1ns / 1ps

module tb;

  // Parameters 
  localparam ROWS = 2;
  localparam COLS = 2;
  localparam DATA_WIDTH = 17;
  localparam ADDR_WIDTH = 16;
  localparam MAC_PIPELINE_DEPTH = 4;
  localparam CLK_PERIOD = 10;

  // Signals
  logic                         clk = 0;
  logic                         rst_n;

  // Inputs
  logic signed [DATA_WIDTH-1:0] act_in      [0:ROWS-1];
  logic signed [DATA_WIDTH-1:0] weight_in;
  logic        [ADDR_WIDTH-1:0] weight_addr;
  logic                         weight_we   [0:ROWS-1] [0:COLS-1];
  logic                         valid_in    [0:ROWS-1];
  logic                         start_in    [0:ROWS-1];
  logic                         clear_in    [0:ROWS-1];

  // Outputs
  logic signed [2*DATA_WIDTH:0] result_out  [0:ROWS-1] [0:COLS-1];
  logic                         valid_o     [0:ROWS-1] [0:COLS-1];

  // --- DUT Instantiation ---
  systolic_array #(
      .ROWS(ROWS),
      .COLS(COLS),
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .act_in(act_in),
      .weight_in(weight_in),
      .weight_addr(weight_addr),
      .weight_we(weight_we),
      .valid_in(valid_in),
      .start_in(start_in),
      .clear_in(clear_in),
      .result_out(result_out),
      .valid_o(valid_o)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #10 clk = ~clk;  // 100 MHz clock
  end

  // --- Main Test Sequence ---
  initial begin
    // ---------------------------------------------------------
    // 1. INITIALIZE & RESET
    // ---------------------------------------------------------
    $display("\n[%0t] === STARTING RESET ===", $time);
    rst_n = 0;
    weight_in = 0;
    weight_addr = 0;
    for (int r = 0; r < ROWS; r++) begin
      act_in[r]   = 0;
      valid_in[r] = 0;
      start_in[r] = 0;
      clear_in[r] = 0;
      for (int c = 0; c < COLS; c++) weight_we[r][c] = 0;
    end

    repeat (5) @(posedge clk);
    rst_n = 1;
    $display("[%0t] Reset Complete.", $time);

    // ---------------------------------------------------------
    // 2. LOAD WEIGHTS (1 weight per PE at Address 0)
    // ---------------------------------------------------------
    $display("\n[%0t] === LOADING WEIGHTS ===", $time);
    weight_addr = 16'd0;  // We will store all weights at address 0

    // Load PE[0][0] with weight 2
    @(posedge clk);
    weight_in = 2;
    weight_we[0][0] = 1;
    // Load PE[0][1] with weight 3
    @(posedge clk);
    weight_we[0][0] = 0;
    weight_in = 3;
    weight_we[0][1] = 1;
    // Load PE[1][0] with weight 4
    @(posedge clk);
    weight_we[0][1] = 0;
    weight_in = 4;
    weight_we[1][0] = 1;
    // Load PE[1][1] with weight 5
    @(posedge clk);
    weight_we[1][0] = 0;
    weight_in = 5;
    weight_we[1][1] = 1;

    @(posedge clk);
    weight_we[1][1] = 0;  // Turn off write enable
    $display("[%0t] Weights Loaded.", $time);

    // ---------------------------------------------------------
    // 3. COMPUTE PHASE (Diagonal Wavefront Input)
    // ---------------------------------------------------------
    $display("\n[%0t] === STARTING COMPUTE WAVEFRONT ===", $time);

    // Setup BRAM read address 1 cycle before driving valid_in
    @(posedge clk);
    weight_addr = 16'd0;

    // Cycle 1: Row 0 starts computing. Row 1 is idle.
    @(posedge clk);
    act_in[0]   = 10;
    valid_in[0] = 1;
    start_in[0] = 1;

    // Cycle 2: Row 0 continues. Row 1 starts computing.
    @(posedge clk);
    act_in[0]   = 20;
    valid_in[0] = 1;
    start_in[0] = 0;  // Accumulate for Row 0
    act_in[1]   = 30;
    valid_in[1] = 1;
    start_in[1] = 1;  // Start fresh for Row 1

    // Cycle 3: Row 0 ends. Row 1 continues.
    @(posedge clk);
    act_in[0]   = 0;
    valid_in[0] = 0;
    start_in[0] = 0;  // Row 0 data stream done
    act_in[1]   = 40;
    valid_in[1] = 1;
    start_in[1] = 0;  // Accumulate for Row 1

    // Cycle 4: Row 1 ends.
    @(posedge clk);
    act_in[1]   = 0;
    valid_in[1] = 0;
    start_in[1] = 0;  // Row 1 data stream done

    $display("[%0t] Inputs finished. Waiting for pipeline to drain...", $time);

    // ---------------------------------------------------------
    // 4. WAIT FOR RESULTS
    // ---------------------------------------------------------
    // The last PE[1][1] gets its data delayed by 4 cycles from Column 0. 
    // We wait long enough for all data to flush out.
    repeat (15) @(posedge clk);

    $display("\n[%0t] === SIMULATION COMPLETE ===", $time);
    $finish;
  end

  // ---------------------------------------------------------
  // DEBUG MONITOR (Automatically prints output of any valid PE)
  // ---------------------------------------------------------
  always_ff @(posedge clk) begin
    for (int r = 0; r < ROWS; r++) begin
      for (int c = 0; c < COLS; c++) begin
        if (valid_o[r][c]) begin
          $display("    ---> [%0t] PE[%0d][%0d] OUTPUT: Result = %0d", $time, r, c,
                   result_out[r][c]);
        end
      end
    end
  end

endmodule
// module tb_top;

//   // --- Parameters ---
//   localparam DATA_WIDTH = 17;
//   localparam ADDR_WIDTH = 16;
//   localparam MAC_PIPELINE_DEPTH = 4;
//   localparam CLK_PERIOD = 10;

//   // --- Signals ---
//   logic clk = 0;
//   logic rst_n;

//   // Grouped standard signals
//   logic signed [DATA_WIDTH-1:0] activation_i, activation_o, weight_i;
//   logic signed [2*DATA_WIDTH:0] result_o;
//   logic [ADDR_WIDTH-1:0] weight_addr;
//   logic weight_we, valid_i, start, acc_clear, valid_o;

//   // --- DUT Instantiation ---
//   pe #(
//       .DATA_WIDTH(DATA_WIDTH),
//       .ADDR_WIDTH(ADDR_WIDTH),
//       .MAC_PIPELINE_DEPTH(MAC_PIPELINE_DEPTH)
//   ) dut (
//       .clk         (clk),
//       .rst_n       (rst_n),
//       .activation_i(activation_i),
//       .activation_o(activation_o),
//       .weight_we   (weight_we),
//       .weight_addr (weight_addr),
//       .weight_i    (weight_i),
//       .valid_i     (valid_i),
//       .start       (start),
//       .acc_clear   (acc_clear),
//       .valid_o     (valid_o),
//       .result_o    (result_o)
//   );

//   // Clock generation
//   initial begin
//     clk = 0;
//     forever #10 clk = ~clk;  // 100 MHz clock
//   end


//   // =========================================================================
//   // TASK 1: Apply Reset Test
//   // =========================================================================
//   task test_apply_reset();
//     $display("\n[%0t] === STARTING RESET TEST ===", $time);
//     rst_n        = 1'b0;
//     activation_i = '0;
//     weight_we    = 1'b0;
//     weight_addr  = '0;
//     weight_i     = '0;
//     valid_i      = 1'b0;
//     start        = 1'b0;
//     acc_clear    = 1'b0;

//     // Synchronous reset delay
//     repeat (5) @(negedge clk);
//     rst_n = 1'b1;
//     $display("[%0t] Reset Complete.", $time);
//   endtask

//   // =========================================================================
//   // TASK 2: Load Inputs Test (Weights)
//   // =========================================================================
//   task test_load_inputs();
//     $display("\n[%0t] === LOADING WEIGHTS INTO BRAM ===", $time);

//     @(posedge clk);
//     weight_we = 1'b1;
//     weight_addr = 16'd0;
//     weight_i = 17'sd2;
//     @(posedge clk);
//     weight_addr = 16'd1;
//     weight_i = -17'sd3;
//     @(posedge clk);
//     weight_addr = 16'd2;
//     weight_i = 17'sd5;

//     @(posedge clk);
//     weight_we = 1'b0;
//     $display("[%0t] Weight Loading Complete.", $time);
//   endtask

//   // =========================================================================
//   // TASK 3: Computing Test (Streaming Activations)
//   // =========================================================================
//   task test_computing();
//     $display("\n[%0t] === STARTING COMPUTE TEST ===", $time);

//     // Cycle 0: Request Weight 0
//     @(posedge clk);
//     weight_addr = 16'd0;

//     // Cycle 1: Drive Act 0, Request Weight 1, Assert Start
//     @(posedge clk);
//     activation_i = 17'sd10;
//     valid_i = 1'b1;
//     start = 1'b1;
//     weight_addr = 16'd1;

//     // Cycle 2: Drive Act 1, Request Weight 2, De-assert Start
//     @(posedge clk);
//     activation_i = 17'sd20;
//     start = 1'b0;
//     weight_addr = 16'd2;

//     // Cycle 3: Drive Act 2
//     @(posedge clk);
//     activation_i = 17'sd30;

//     // Cycle 4: End stream
//     @(posedge clk);
//     valid_i = 1'b0;
//     activation_i = '0;

//     // Wait for pipeline to drain
//     repeat (6) @(posedge clk);
//     $display("\n[%0t] === COMPUTE TEST COMPLETE ===", $time);
//   endtask

//   // =========================================================================
//   // DEBUG MONITOR
//   // =========================================================================
//   always_ff @(posedge clk) begin
//     if (valid_o) begin
//       $display(
//           "    ---> [%0t] OUTPUT: valid_o = 1 | Forwarded Act_o = %0d | Accumulator Result = %0d",
//           $time, activation_o, result_o);
//     end
//   end

//   // --- Main Test Sequence ---
//   initial begin
//     test_apply_reset();
//     repeat (2) @(posedge clk);  // Synchronous delay between tests

//     test_load_inputs();
//     repeat (2) @(posedge clk);

//     test_computing();

//     repeat (10) @(posedge clk);  // Final buffer before finishing
//     $display("\nSimulation Finished Successfully.");
//     $finish;
//   end

//   initial begin
//     $display(" -----------------------");
//     $display("  DUMP VCD ENABLED ");
//     $display(" -----------------------");
//     $dumpfile("pe_test.vcd");
//     $dumpvars;
//     $dumpon;
//   end
// endmodule

`timescale 1ns / 1ps

module tb;

  localparam ROWS = 2;
  localparam COLS = 2;
  localparam DATA_WIDTH = 17;
  localparam CLK_PERIOD = 10;

  logic                         clk = 0;
  logic                         rst_n;

  logic signed [DATA_WIDTH-1:0] act_in     [0:ROWS-1];
  logic                         valid_in;
  logic                         start_in;
  logic                         clear_in;

  logic signed [DATA_WIDTH-1:0] weight_in  [0:COLS-1];
  logic                         weight_load[0:COLS-1];

  logic signed [2*DATA_WIDTH:0] result_out [0:ROWS-1] [0:COLS-1];
  logic                         valid_out  [0:ROWS-1] [0:COLS-1];
  logic signed [DATA_WIDTH-1:0] weight_dbg [0:ROWS-1] [0:COLS-1];

  logic signed [2*DATA_WIDTH:0] expected   [0:ROWS-1] [0:COLS-1];

  systolic_array #(
      .ROWS(ROWS),
      .COLS(COLS),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .act_in(act_in),
      .valid_in(valid_in),
      .start_in(start_in),
      .clear_in(clear_in),
      .weight_in(weight_in),
      .weight_load(weight_load),
      .result_out(result_out),
      .valid_out(valid_out),
      .weight_dbg(weight_dbg)
  );

  initial begin
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  task automatic zero_inputs;
    begin
      valid_in = 1'b0;
      start_in = 1'b0;
      clear_in = 1'b0;
      for (int r = 0; r < ROWS; r++) act_in[r] = '0;
      for (int c = 0; c < COLS; c++) begin
        weight_in[c]   = '0;
        weight_load[c] = 1'b0;
      end
    end
  endtask

  // Load one B[k,:] row into PE weight registers column-wise
  task automatic load_weight_step(input logic signed [DATA_WIDTH-1:0] w0,
                                  input logic signed [DATA_WIDTH-1:0] w1);
    begin
      @(posedge clk);
      weight_in[0]   <= w0;
      weight_in[1]   <= w1;
      weight_load[0] <= 1'b1;
      weight_load[1] <= 1'b1;
      valid_in       <= 1'b0;
      start_in       <= 1'b0;
      clear_in       <= 1'b0;
      act_in[0]      <= '0;
      act_in[1]      <= '0;

      @(posedge clk);
      weight_load[0] <= 1'b0;
      weight_load[1] <= 1'b0;
    end
  endtask

  // Feed one A[:,k] column as row activations
  task automatic compute_step(input logic signed [DATA_WIDTH-1:0] a0,
                              input logic signed [DATA_WIDTH-1:0] a1, input logic start_pulse);
    begin
      @(posedge clk);
      act_in[0] <= a0;
      act_in[1] <= a1;
      valid_in  <= 1'b1;
      start_in  <= start_pulse;
      clear_in  <= 1'b0;

      @(posedge clk);
      act_in[0] <= '0;
      act_in[1] <= '0;
      valid_in  <= 1'b0;
      start_in  <= 1'b0;
    end
  endtask

  initial begin
    expected[0][0] = 35'sd5;
    expected[0][1] = 35'sd4;
    expected[1][0] = 35'sd4;
    expected[1][1] = 35'sd5;

    $display("\n[0] === RESET ===");
    rst_n = 1'b0;
    zero_inputs();
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // Explicit accumulator clear after reset
    @(posedge clk);
    clear_in <= 1'b1;
    @(posedge clk);
    clear_in <= 1'b0;

    // A = [1 2; 2 1]
    // B = [1 2; 2 1]
    // Step k=0: use A[:,0] and B[0,:]
    $display("\n[%0t] === K = 0 : LOAD WEIGHTS B[0,:] ===", $time);
    load_weight_step(17'sd1, 17'sd2);

    $display("[%0t] === K = 0 : COMPUTE WITH A[:,0] ===", $time);
    compute_step(17'sd1, 17'sd2, 1'b1);

    // Step k=1: use A[:,1] and B[1,:]
    $display("\n[%0t] === K = 1 : LOAD WEIGHTS B[1,:] ===", $time);
    load_weight_step(17'sd2, 17'sd1);

    $display("[%0t] === K = 1 : COMPUTE WITH A[:,1] ===", $time);
    compute_step(17'sd2, 17'sd1, 1'b0);

    // Drain MAC pipeline (mult=3 + acc=1)
    repeat (8) @(posedge clk);

    $display("\n[%0t] === FINAL RESULT MATRIX ===", $time);
    $display("C = [ %0d %0d ; %0d %0d ]", result_out[0][0], result_out[0][1], result_out[1][0],
             result_out[1][1]);

    for (int r = 0; r < ROWS; r++) begin
      for (int c = 0; c < COLS; c++) begin
        if (result_out[r][c] !== expected[r][c]) begin
          $error("Mismatch at C[%0d][%0d]: got %0d, expected %0d", r, c, result_out[r][c],
                 expected[r][c]);
        end
      end
    end

    // $display("TEST PASSED.");
    $finish;
  end

  always_ff @(posedge clk) begin
    for (int r = 0; r < ROWS; r++) begin
      for (int c = 0; c < COLS; c++) begin
        if (valid_out[r][c]) begin
          $display("[%0t] valid_out[%0d][%0d] result_out=%0d weight=%0d", $time, r, c,
                   result_out[r][c], weight_dbg[r][c]);
        end
      end
    end
  end

  initial begin
    $dumpfile("tb_top_ws_reg.vcd");
    $dumpvars(0, tb);
  end

endmodule : tb
// module tb;

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

//   // DEBUG MONITOR
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

//     // repeat (10) @(posedge clk);  // Final buffer before finishing
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

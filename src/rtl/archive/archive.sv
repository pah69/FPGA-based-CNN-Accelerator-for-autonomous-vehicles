
////////////////////////////////////////////////////////////////////////////////

module mac_unit_tb;

    // Parameters
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100MHz clock

    // Signals
    logic clk;
    logic rst_n;
    logic [DATA_WIDTH-1:0] a_in;
    logic [DATA_WIDTH-1:0] b_in;
    logic [DATA_WIDTH*2:0] dut_result;

    // Reference Model Signals
    logic [DATA_WIDTH*2:0] expected_acc;
    logic [(2*DATA_WIDTH)-1:0] expected_mult_queue [$]; // Queue to model multiplier latency
    logic [DATA_WIDTH*2:0] accumulator_val;

    // Instantiate the DUT
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .mac_a_in(a_in),
        .mac_b_in(b_in),
        .result(dut_result)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test Sequence
    initial begin
        // 1. Initialize & Reset
        rst_n = 0;
        a_in = 0;
        b_in = 0;
        accumulator_val = 0;
        expected_mult_queue.delete();

        $display("--- Starting Simulation ---");

        // Hold reset for 5 cycles
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk); // Wait one cycle after reset release

        // 2. Direct Test Cases
        drive_stimulus(32'd2, 32'd3);   // 2 * 3 = 6
        drive_stimulus(32'd10, 32'd10); // 10 * 10 = 100
        drive_stimulus(32'd1, 32'd5);   // 1 * 5 = 5
        drive_stimulus(32'd0, 32'd50);  // 0 * 50 = 0 (Check zero multiplication)

        // 3. Random Testing
        $display("--- Starting Random Stimulus ---");
        repeat(20) begin
            drive_stimulus($urandom_range(0, 1000), $urandom_range(0, 1000));
        end

        // 4. Wait for Pipeline to drain
        repeat(10) begin
            drive_stimulus(0, 0);
        end

        $display("--- Test Passed! ---");
        $finish;
    end



/////// Task implementation
    
    // Task to drive inputs and model expected behavior
    task drive_stimulus(input logic [DATA_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] b);
    logic [(2*DATA_WIDTH)-1:0] current_mult;
        begin
            // Drive DUT inputs
            a_in <= a;
            b_in <= b;

            // 1. Calculate Multiplication immediately
            current_mult = a * b;

            // 2. Push to queue to model Multiplier Latency (4 cycles)
            expected_mult_queue.push_back(current_mult);

            // 3. Process the Output side (Model the Accumulator)
            if (expected_mult_queue.size() > 4) begin
                logic [(2*DATA_WIDTH)-1:0] delayed_mult;
                delayed_mult = expected_mult_queue.pop_front();
                accumulator_val = accumulator_val + delayed_mult;
            end

            // 4. Compare vs DUT
            @(posedge clk);
            if ($time > (10 * CLK_PERIOD)) begin
                $display("Time: %0t | Input: %0d*%0d | DUT Output: %0d | Internal Calc: %0d", 
                         $time, a, b, dut_result, accumulator_val);

            end
        end
    endtask

endmodule

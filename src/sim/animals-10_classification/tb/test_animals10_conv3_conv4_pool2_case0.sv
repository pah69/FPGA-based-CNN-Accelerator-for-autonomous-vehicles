`timescale 1ns/1ps

module test_animals10_conv3_conv4_pool2_case0;
    localparam int INPUT_COUNT = 32 * 32 * 32;
    localparam int CONV3_WEIGHT_COUNT = 64 * 32 * 3 * 3;
    localparam int CONV4_WEIGHT_COUNT = 64 * 64 * 3 * 3;
    localparam int CONV3_CONV4_WEIGHT_COUNT = CONV3_WEIGHT_COUNT + CONV4_WEIGHT_COUNT;
    localparam int MODEL_WEIGHT_COUNT = 304224;
    localparam int MODEL_PARAM_COUNT = 586;
    localparam int CONV3_CONV4_PARAM_COUNT = 128;
    localparam int CONV3_WEIGHT_OFFSET = 10080;
    localparam int CONV3_PARAM_OFFSET = 64;
    localparam int POOL2_OUT_COUNT = 64 * 16 * 16;
    localparam int TIMEOUT_CYCLES = 40000000;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;

    logic input_we;
    logic [14:0] input_addr;
    logic signed [7:0] input_data;

    logic weight_we;
    logic [15:0] weight_addr;
    logic signed [7:0] weight_data;

    logic param_we;
    logic [6:0] param_addr;
    logic signed [31:0] bias_data;
    logic signed [31:0] requant_mult_data;
    logic signed [7:0] requant_shift_data;

    logic output_valid;
    logic output_last;
    logic [13:0] output_index;
    logic signed [7:0] data;

    logic [31:0] debug_total_cycle_count;
    logic [31:0] debug_conv3_cycle_count;
    logic [31:0] debug_conv3_tile_count;
    logic [31:0] debug_conv3_output_count;
    logic [31:0] debug_conv4_cycle_count;
    logic [31:0] debug_conv4_tile_count;
    logic [31:0] debug_conv4_output_count;
    logic [31:0] debug_pool2_cycle_count;
    logic [31:0] debug_pool2_output_count;

    logic signed [7:0] input_mem[0:INPUT_COUNT-1];
    logic signed [7:0] weight_mem[0:MODEL_WEIGHT_COUNT-1];
    logic signed [31:0] bias_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] requant_mult_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] requant_shift_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] golden_pool2_out[0:POOL2_OUT_COUNT-1];
    bit seen_output[0:POOL2_OUT_COUNT-1];

    string export_dir;
    string input_hex;
    string weight_hex;
    string bias_hex;
    string requant_mult_hex;
    string requant_shift_hex;
    string golden_pool2_hex;

    int out_mismatches;
    int duplicate_outputs;
    int outputs_seen;
    int first_out_mismatch;
    int first_duplicate;
    logic signed [7:0] first_out_got;
    logic signed [7:0] first_out_expected;
    bit has_export_dir_plusarg;

    animals10_conv3_conv4_pool2_systolic_4x4 dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start),
        .busy_o(busy),
        .done_o(done),
        .input_we_i(input_we),
        .input_addr_i(input_addr),
        .input_data_i(input_data),
        .weight_we_i(weight_we),
        .weight_addr_i(weight_addr),
        .weight_data_i(weight_data),
        .param_we_i(param_we),
        .param_addr_i(param_addr),
        .bias_data_i(bias_data),
        .requant_mult_data_i(requant_mult_data),
        .requant_shift_data_i(requant_shift_data),
        .output_valid_o(output_valid),
        .output_last_o(output_last),
        .output_index_o(output_index),
        .data_o(data),
        .debug_total_cycle_count_o(debug_total_cycle_count),
        .debug_conv3_cycle_count_o(debug_conv3_cycle_count),
        .debug_conv3_tile_count_o(debug_conv3_tile_count),
        .debug_conv3_output_count_o(debug_conv3_output_count),
        .debug_conv4_cycle_count_o(debug_conv4_cycle_count),
        .debug_conv4_tile_count_o(debug_conv4_tile_count),
        .debug_conv4_output_count_o(debug_conv4_output_count),
        .debug_pool2_cycle_count_o(debug_pool2_cycle_count),
        .debug_pool2_output_count_o(debug_pool2_output_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic require_file(input string path);
        int handle;
        begin
            handle = $fopen(path, "r");
            if (handle == 0) begin
                $fatal(1, "Missing required file: %s", path);
            end
            $fclose(handle);
        end
    endtask

    task automatic load_hex_files;
        begin
            require_file(input_hex);
            require_file(weight_hex);
            require_file(bias_hex);
            require_file(requant_mult_hex);
            require_file(requant_shift_hex);
            require_file(golden_pool2_hex);

            $readmemh(input_hex, input_mem);
            $readmemh(weight_hex, weight_mem);
            $readmemh(bias_hex, bias_mem);
            $readmemh(requant_mult_hex, requant_mult_mem);
            $readmemh(requant_shift_hex, requant_shift_mem);
            $readmemh(golden_pool2_hex, golden_pool2_out);
        end
    endtask

    task automatic clear_inputs;
        begin
            start = 1'b0;
            input_we = 1'b0;
            input_addr = '0;
            input_data = '0;
            weight_we = 1'b0;
            weight_addr = '0;
            weight_data = '0;
            param_we = 1'b0;
            param_addr = '0;
            bias_data = '0;
            requant_mult_data = '0;
            requant_shift_data = '0;
        end
    endtask

    task automatic write_input(input int addr, input logic signed [7:0] value);
        begin
            @(posedge clk);
            input_we <= 1'b1;
            input_addr <= addr[14:0];
            input_data <= value;
            @(posedge clk);
            input_we <= 1'b0;
            input_addr <= '0;
            input_data <= '0;
        end
    endtask

    task automatic write_weight(input int addr, input logic signed [7:0] value);
        begin
            @(posedge clk);
            weight_we <= 1'b1;
            weight_addr <= addr[15:0];
            weight_data <= value;
            @(posedge clk);
            weight_we <= 1'b0;
            weight_addr <= '0;
            weight_data <= '0;
        end
    endtask

    task automatic write_param(
        input int addr,
        input logic signed [31:0] bias_value,
        input logic signed [31:0] mult_value,
        input logic signed [7:0] shift_value
    );
        begin
            @(posedge clk);
            param_we <= 1'b1;
            param_addr <= addr[6:0];
            bias_data <= bias_value;
            requant_mult_data <= mult_value;
            requant_shift_data <= shift_value;
            @(posedge clk);
            param_we <= 1'b0;
            param_addr <= '0;
            bias_data <= '0;
            requant_mult_data <= '0;
            requant_shift_data <= '0;
        end
    endtask

    task automatic load_dut_memories;
        begin
            for (int i = 0; i < INPUT_COUNT; i++) begin
                write_input(i, input_mem[i]);
            end
            for (int i = 0; i < CONV3_CONV4_WEIGHT_COUNT; i++) begin
                write_weight(i, weight_mem[CONV3_WEIGHT_OFFSET + i]);
            end
            for (int i = 0; i < CONV3_CONV4_PARAM_COUNT; i++) begin
                write_param(
                    i,
                    bias_mem[CONV3_PARAM_OFFSET + i],
                    requant_mult_mem[CONV3_PARAM_OFFSET + i],
                    requant_shift_mem[CONV3_PARAM_OFFSET + i]
                );
            end
        end
    endtask

    task automatic start_dut;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic check_stream;
        int idx;
        int wait_cycles;
        begin
            out_mismatches = 0;
            duplicate_outputs = 0;
            outputs_seen = 0;
            first_out_mismatch = -1;
            first_duplicate = -1;
            first_out_got = '0;
            first_out_expected = '0;
            wait_cycles = 0;

            for (int i = 0; i < POOL2_OUT_COUNT; i++) begin
                seen_output[i] = 1'b0;
            end

            do begin
                @(posedge clk);
                #1;
                wait_cycles++;
                if (wait_cycles > TIMEOUT_CYCLES) begin
                    $fatal(1, "Timeout waiting for Conv3+Conv4+Pool2 completion after %0d cycles",
                           wait_cycles);
                end

                if (output_valid) begin
                    idx = int'(output_index);
                    outputs_seen++;
                    if (idx < 0 || idx >= POOL2_OUT_COUNT) begin
                        $fatal(1, "Pool2 output index out of range: %0d", idx);
                    end
                    if (seen_output[idx]) begin
                        duplicate_outputs++;
                        if (first_duplicate < 0) begin
                            first_duplicate = idx;
                        end
                    end
                    seen_output[idx] = 1'b1;

                    if (data !== golden_pool2_out[idx]) begin
                        out_mismatches++;
                        if (first_out_mismatch < 0) begin
                            first_out_mismatch = idx;
                            first_out_got = data;
                            first_out_expected = golden_pool2_out[idx];
                        end
                    end
                end
            end while (!done);

            $display(
                "ANIMALS10_CONV3_CONV4_POOL2 outputs_seen=%0d out_mismatches=%0d duplicates=%0d",
                outputs_seen, out_mismatches, duplicate_outputs
            );
            $display(
                "ANIMALS10_CONV3_CONV4_POOL2 counters total=%0d conv3_cycles=%0d conv3_tiles=%0d conv3_outputs=%0d conv4_cycles=%0d conv4_tiles=%0d conv4_outputs=%0d pool2_cycles=%0d pool2_outputs=%0d",
                debug_total_cycle_count,
                debug_conv3_cycle_count,
                debug_conv3_tile_count,
                debug_conv3_output_count,
                debug_conv4_cycle_count,
                debug_conv4_tile_count,
                debug_conv4_output_count,
                debug_pool2_cycle_count,
                debug_pool2_output_count
            );

            if (first_duplicate >= 0) begin
                $display("FIRST_DUPLICATE idx=%0d", first_duplicate);
            end
            if (first_out_mismatch >= 0) begin
                $display("FIRST_OUT_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_out_mismatch, first_out_got, first_out_expected);
            end

            if (outputs_seen != POOL2_OUT_COUNT) begin
                $fatal(1, "Expected %0d Pool2 outputs, got %0d", POOL2_OUT_COUNT, outputs_seen);
            end
            if (duplicate_outputs != 0 || out_mismatches != 0) begin
                $fatal(1, "Animals-10 Conv3+Conv4+Pool2 DUT did not match Python INT8 golden output");
            end

            $display("PASS: Animals-10 Conv3+Conv4+Pool2 DUT matches Python INT8 golden output");
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);

        input_hex = $sformatf("%s/debug_case0/pool1_out_i8.hex", export_dir);
        weight_hex = $sformatf("%s/animals10_weights_i8.hex", export_dir);
        bias_hex = $sformatf("%s/animals10_bias_i32.hex", export_dir);
        requant_mult_hex = $sformatf("%s/animals10_requant_mult_i32.hex", export_dir);
        requant_shift_hex = $sformatf("%s/animals10_requant_shift_i8.hex", export_dir);
        golden_pool2_hex = $sformatf("%s/debug_case0/pool2_out_i8.hex", export_dir);

        $display("Animals-10 Conv3+Conv4+Pool2 4x4 systolic DUT bench");
        $display("  export_dir=%s", export_dir);

        clear_inputs();
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        load_hex_files();
        load_dut_memories();
        start_dut();
        check_stream();
        $finish;
    end
endmodule

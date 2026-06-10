`timescale 1ns/1ps

module test_animals10_gap_case0;
    localparam int INPUT_COUNT = 128 * 8 * 8;
    localparam int GAP_OUT_COUNT = 128;
    localparam int TIMEOUT_CYCLES = 1000;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;

    logic input_we;
    logic [12:0] input_addr;
    logic signed [7:0] input_data;

    logic output_valid;
    logic output_last;
    logic [6:0] output_index;
    logic signed [7:0] data;
    logic [31:0] debug_cycle_count;
    logic [31:0] debug_output_count;

    logic signed [7:0] input_mem[0:INPUT_COUNT-1];
    logic signed [7:0] golden_out[0:GAP_OUT_COUNT-1];
    bit seen_output[0:GAP_OUT_COUNT-1];

    string export_dir;
    string input_hex;
    string golden_out_hex;

    int out_mismatches;
    int duplicate_outputs;
    int outputs_seen;
    int first_out_mismatch;
    int first_duplicate;
    logic signed [7:0] first_out_got;
    logic signed [7:0] first_out_expected;
    bit has_export_dir_plusarg;

    animals10_gap_i8 dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start),
        .busy_o(busy),
        .done_o(done),
        .input_we_i(input_we),
        .input_addr_i(input_addr),
        .input_data_i(input_data),
        .output_valid_o(output_valid),
        .output_last_o(output_last),
        .output_index_o(output_index),
        .data_o(data),
        .debug_cycle_count_o(debug_cycle_count),
        .debug_output_count_o(debug_output_count)
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
            require_file(golden_out_hex);
            $readmemh(input_hex, input_mem);
            $readmemh(golden_out_hex, golden_out);
        end
    endtask

    task automatic clear_inputs;
        begin
            start = 1'b0;
            input_we = 1'b0;
            input_addr = '0;
            input_data = '0;
        end
    endtask

    task automatic write_input(input int addr, input logic signed [7:0] value);
        begin
            @(posedge clk);
            input_we <= 1'b1;
            input_addr <= addr[12:0];
            input_data <= value;
            @(posedge clk);
            input_we <= 1'b0;
            input_addr <= '0;
            input_data <= '0;
        end
    endtask

    task automatic load_dut_memories;
        begin
            for (int i = 0; i < INPUT_COUNT; i++) begin
                write_input(i, input_mem[i]);
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
            for (int i = 0; i < GAP_OUT_COUNT; i++) begin
                seen_output[i] = 1'b0;
            end

            do begin
                @(posedge clk);
                #1;
                wait_cycles++;
                if (wait_cycles > TIMEOUT_CYCLES) begin
                    $fatal(1, "Timeout waiting for GAP completion after %0d cycles", wait_cycles);
                end

                if (output_valid) begin
                    idx = int'(output_index);
                    outputs_seen++;
                    if (idx < 0 || idx >= GAP_OUT_COUNT) begin
                        $fatal(1, "GAP output index out of range: %0d", idx);
                    end
                    if (seen_output[idx]) begin
                        duplicate_outputs++;
                        if (first_duplicate < 0) begin
                            first_duplicate = idx;
                        end
                    end
                    seen_output[idx] = 1'b1;

                    if (data !== golden_out[idx]) begin
                        out_mismatches++;
                        if (first_out_mismatch < 0) begin
                            first_out_mismatch = idx;
                            first_out_got = data;
                            first_out_expected = golden_out[idx];
                        end
                    end
                end
            end while (!done);

            $display(
                "ANIMALS10_GAP outputs_seen=%0d out_mismatches=%0d duplicates=%0d",
                outputs_seen, out_mismatches, duplicate_outputs
            );
            $display(
                "ANIMALS10_GAP counters cycles=%0d outputs=%0d",
                debug_cycle_count, debug_output_count
            );

            if (first_duplicate >= 0) begin
                $display("FIRST_DUPLICATE idx=%0d", first_duplicate);
            end
            if (first_out_mismatch >= 0) begin
                $display("FIRST_OUT_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_out_mismatch, first_out_got, first_out_expected);
            end

            if (outputs_seen != GAP_OUT_COUNT) begin
                $fatal(1, "Expected %0d GAP outputs, got %0d", GAP_OUT_COUNT, outputs_seen);
            end
            if (duplicate_outputs != 0 || out_mismatches != 0) begin
                $fatal(1, "Animals-10 GAP DUT did not match Python INT8 golden output");
            end

            $display("PASS: Animals-10 GAP DUT matches Python INT8 golden output");
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);

        input_hex = $sformatf("%s/debug_case0/pool3_out_i8.hex", export_dir);
        golden_out_hex = $sformatf("%s/debug_case0/gap_out_i8.hex", export_dir);

        $display("Animals-10 GAP DUT bench");
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

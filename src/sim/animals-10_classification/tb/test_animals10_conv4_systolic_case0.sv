`timescale 1ns/1ps

module test_animals10_conv4_systolic_case0;
    localparam int IN_C = 64;
    localparam int IN_H = 32;
    localparam int IN_W = 32;
    localparam int OUT_C = 64;
    localparam int OUT_H = 32;
    localparam int OUT_W = 32;
    localparam int K_H = 3;
    localparam int K_W = 3;

    localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
    localparam int CONV4_WEIGHT_COUNT = OUT_C * IN_C * K_H * K_W;
    localparam int MODEL_WEIGHT_COUNT = 304224;
    localparam int MODEL_PARAM_COUNT = 586;
    localparam int CONV4_OUT_COUNT = OUT_C * OUT_H * OUT_W;
    localparam int CONV4_WEIGHT_OFFSET = 28512;
    localparam int CONV4_PARAM_OFFSET = 128;
    localparam int TIMEOUT_CYCLES = 50000000;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;

    logic input_we;
    logic [15:0] input_addr;
    logic signed [7:0] input_data;

    logic weight_we;
    logic [15:0] weight_addr;
    logic signed [7:0] weight_data;

    logic param_we;
    logic [5:0] param_addr;
    logic signed [31:0] bias_data;
    logic signed [31:0] requant_mult_data;
    logic signed [7:0] requant_shift_data;

    logic output_valid;
    logic output_last;
    logic [15:0] output_index;
    logic signed [31:0] acc;
    logic signed [7:0] data;
    logic [31:0] debug_cycle_count;
    logic [31:0] debug_tile_count;
    logic [31:0] debug_output_count;

    logic signed [7:0] input_mem[0:INPUT_COUNT-1];
    logic signed [7:0] weight_mem[0:MODEL_WEIGHT_COUNT-1];
    logic signed [31:0] bias_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] requant_mult_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] requant_shift_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] golden_acc[0:CONV4_OUT_COUNT-1];
    logic signed [7:0] golden_out[0:CONV4_OUT_COUNT-1];
    bit seen_output[0:CONV4_OUT_COUNT-1];

    string export_dir;
    string input_hex;
    string weight_hex;
    string bias_hex;
    string requant_mult_hex;
    string requant_shift_hex;
    string golden_acc_hex;
    string golden_out_hex;

    int acc_mismatches;
    int out_mismatches;
    int duplicate_outputs;
    int outputs_seen;
    int first_acc_mismatch;
    int first_out_mismatch;
    int first_duplicate;
    logic signed [31:0] first_acc_got;
    logic signed [31:0] first_acc_expected;
    logic signed [7:0] first_out_got;
    logic signed [7:0] first_out_expected;
    bit has_export_dir_plusarg;

    animals10_conv4_systolic_4x4 dut (
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
        .acc_o(acc),
        .data_o(data),
        .debug_cycle_count_o(debug_cycle_count),
        .debug_tile_count_o(debug_tile_count),
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
            require_file(weight_hex);
            require_file(bias_hex);
            require_file(requant_mult_hex);
            require_file(requant_shift_hex);
            require_file(golden_acc_hex);
            require_file(golden_out_hex);

            $readmemh(input_hex, input_mem);
            $readmemh(weight_hex, weight_mem);
            $readmemh(bias_hex, bias_mem);
            $readmemh(requant_mult_hex, requant_mult_mem);
            $readmemh(requant_shift_hex, requant_shift_mem);
            $readmemh(golden_acc_hex, golden_acc);
            $readmemh(golden_out_hex, golden_out);
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
            input_addr <= addr[15:0];
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
            param_addr <= addr[5:0];
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
            for (int i = 0; i < CONV4_WEIGHT_COUNT; i++) begin
                write_weight(i, weight_mem[CONV4_WEIGHT_OFFSET + i]);
            end
            for (int i = 0; i < OUT_C; i++) begin
                write_param(
                    i,
                    bias_mem[CONV4_PARAM_OFFSET + i],
                    requant_mult_mem[CONV4_PARAM_OFFSET + i],
                    requant_shift_mem[CONV4_PARAM_OFFSET + i]
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
            acc_mismatches = 0;
            out_mismatches = 0;
            duplicate_outputs = 0;
            outputs_seen = 0;
            first_acc_mismatch = -1;
            first_out_mismatch = -1;
            first_duplicate = -1;
            first_acc_got = '0;
            first_acc_expected = '0;
            first_out_got = '0;
            first_out_expected = '0;
            wait_cycles = 0;
            for (int i = 0; i < CONV4_OUT_COUNT; i++) begin
                seen_output[i] = 1'b0;
            end

            do begin
                @(posedge clk);
                #1;
                wait_cycles++;
                if (wait_cycles > TIMEOUT_CYCLES) begin
                    $fatal(1, "Timeout waiting for systolic Conv4 completion after %0d cycles", wait_cycles);
                end

                if (output_valid) begin
                    idx = int'(output_index);
                    outputs_seen++;
                    if (idx < 0 || idx >= CONV4_OUT_COUNT) begin
                        $fatal(1, "Output index out of range: %0d", idx);
                    end
                    if (seen_output[idx]) begin
                        duplicate_outputs++;
                        if (first_duplicate < 0) begin
                            first_duplicate = idx;
                        end
                    end
                    seen_output[idx] = 1'b1;

                    if (acc !== golden_acc[idx]) begin
                        acc_mismatches++;
                        if (first_acc_mismatch < 0) begin
                            first_acc_mismatch = idx;
                            first_acc_got = acc;
                            first_acc_expected = golden_acc[idx];
                        end
                    end
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
                "ANIMALS10_CONV4_SYSTOLIC outputs_seen=%0d acc_mismatches=%0d out_mismatches=%0d duplicates=%0d",
                outputs_seen, acc_mismatches, out_mismatches, duplicate_outputs
            );
            $display(
                "ANIMALS10_CONV4_SYSTOLIC counters cycles=%0d tiles=%0d outputs=%0d",
                debug_cycle_count, debug_tile_count, debug_output_count
            );

            if (first_duplicate >= 0) begin
                $display("FIRST_DUPLICATE idx=%0d", first_duplicate);
            end
            if (first_acc_mismatch >= 0) begin
                $display("FIRST_ACC_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_acc_mismatch, first_acc_got, first_acc_expected);
            end
            if (first_out_mismatch >= 0) begin
                $display("FIRST_OUT_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_out_mismatch, first_out_got, first_out_expected);
            end

            if (outputs_seen != CONV4_OUT_COUNT) begin
                $fatal(1, "Expected %0d Conv4 outputs, got %0d", CONV4_OUT_COUNT, outputs_seen);
            end
            if (duplicate_outputs != 0 || acc_mismatches != 0 || out_mismatches != 0) begin
                $fatal(1, "Animals-10 Conv4 systolic DUT did not match Python INT8 golden output");
            end

            $display("PASS: Animals-10 Conv4 systolic DUT matches Python INT8 golden output");
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);

        input_hex = $sformatf("%s/debug_case0/conv3_out_i8.hex", export_dir);
        weight_hex = $sformatf("%s/animals10_weights_i8.hex", export_dir);
        bias_hex = $sformatf("%s/animals10_bias_i32.hex", export_dir);
        requant_mult_hex = $sformatf("%s/animals10_requant_mult_i32.hex", export_dir);
        requant_shift_hex = $sformatf("%s/animals10_requant_shift_i8.hex", export_dir);
        golden_acc_hex = $sformatf("%s/debug_case0/conv4_acc_i32.hex", export_dir);
        golden_out_hex = $sformatf("%s/debug_case0/conv4_out_i8.hex", export_dir);

        $display("Animals-10 Conv4 4x4 systolic DUT bench");
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

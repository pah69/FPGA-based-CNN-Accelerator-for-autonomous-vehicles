`timescale 1ns/1ps

module test_animals10_full_network_10cases;
    localparam int INPUT_COUNT = 3 * 64 * 64;
    localparam int TEST_CASE_COUNT = 10;
    localparam int TEST_INPUT_COUNT = TEST_CASE_COUNT * INPUT_COUNT;
    localparam int MODEL_WEIGHT_COUNT = 304224;
    localparam int MODEL_PARAM_COUNT = 586;
    localparam int FC2_OUT_COUNT = 10;
    localparam int TEST_LOGIT_COUNT = TEST_CASE_COUNT * FC2_OUT_COUNT;
    localparam int TIMEOUT_CYCLES = 100000000;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;

    logic input_we;
    logic [13:0] input_addr;
    logic signed [7:0] input_data;

    logic weight_we;
    logic [18:0] weight_addr;
    logic signed [7:0] weight_data;

    logic param_we;
    logic [9:0] param_addr;
    logic signed [31:0] bias_data;
    logic signed [31:0] requant_mult_data;
    logic signed [7:0] requant_shift_data;

    logic output_valid;
    logic output_last;
    logic [3:0] output_index;
    logic signed [31:0] acc;
    logic signed [7:0] data;

    logic [31:0] debug_total_cycle_count;
    logic [31:0] debug_stage1_cycle_count;
    logic [31:0] debug_stage2_cycle_count;
    logic [31:0] debug_stage3_cycle_count;
    logic [31:0] debug_conv1_cycle_count;
    logic [31:0] debug_conv1_tile_count;
    logic [31:0] debug_conv1_output_count;
    logic [31:0] debug_conv2_cycle_count;
    logic [31:0] debug_conv2_tile_count;
    logic [31:0] debug_conv2_output_count;
    logic [31:0] debug_pool1_cycle_count;
    logic [31:0] debug_pool1_output_count;
    logic [31:0] debug_conv3_cycle_count;
    logic [31:0] debug_conv3_tile_count;
    logic [31:0] debug_conv3_output_count;
    logic [31:0] debug_conv4_cycle_count;
    logic [31:0] debug_conv4_tile_count;
    logic [31:0] debug_conv4_output_count;
    logic [31:0] debug_pool2_cycle_count;
    logic [31:0] debug_pool2_output_count;
    logic [31:0] debug_conv5_cycle_count;
    logic [31:0] debug_conv5_tile_count;
    logic [31:0] debug_conv5_output_count;
    logic [31:0] debug_conv6_cycle_count;
    logic [31:0] debug_conv6_tile_count;
    logic [31:0] debug_conv6_output_count;
    logic [31:0] debug_pool3_cycle_count;
    logic [31:0] debug_pool3_output_count;
    logic [31:0] debug_gap_cycle_count;
    logic [31:0] debug_gap_output_count;
    logic [31:0] debug_fc1_cycle_count;
    logic [31:0] debug_fc1_output_count;
    logic [31:0] debug_fc2_cycle_count;
    logic [31:0] debug_fc2_output_count;

    logic signed [7:0] input_mem[0:TEST_INPUT_COUNT-1];
    logic signed [7:0] weight_mem[0:MODEL_WEIGHT_COUNT-1];
    logic signed [31:0] bias_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] requant_mult_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] requant_shift_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] golden_logits[0:TEST_LOGIT_COUNT-1];
    logic [7:0] labels[0:TEST_CASE_COUNT-1];
    logic signed [7:0] case_logits[0:FC2_OUT_COUNT-1];
    bit seen_output[0:FC2_OUT_COUNT-1];

    string export_dir;
    string input_hex;
    string weight_hex;
    string bias_hex;
    string requant_mult_hex;
    string requant_shift_hex;
    string golden_logits_hex;
    string labels_hex;

    int cases_to_run;
    int total_outputs_seen;
    int out_mismatches;
    int duplicate_outputs;
    int first_out_mismatch_case;
    int first_out_mismatch_idx;
    int first_duplicate_case;
    int first_duplicate_idx;
    logic signed [7:0] first_out_got;
    logic signed [7:0] first_out_expected;
    bit has_export_dir_plusarg;
    bit has_max_cases_plusarg;

    animals10_full_network_i8 dut (
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
        .debug_total_cycle_count_o(debug_total_cycle_count),
        .debug_stage1_cycle_count_o(debug_stage1_cycle_count),
        .debug_stage2_cycle_count_o(debug_stage2_cycle_count),
        .debug_stage3_cycle_count_o(debug_stage3_cycle_count),
        .debug_conv1_cycle_count_o(debug_conv1_cycle_count),
        .debug_conv1_tile_count_o(debug_conv1_tile_count),
        .debug_conv1_output_count_o(debug_conv1_output_count),
        .debug_conv2_cycle_count_o(debug_conv2_cycle_count),
        .debug_conv2_tile_count_o(debug_conv2_tile_count),
        .debug_conv2_output_count_o(debug_conv2_output_count),
        .debug_pool1_cycle_count_o(debug_pool1_cycle_count),
        .debug_pool1_output_count_o(debug_pool1_output_count),
        .debug_conv3_cycle_count_o(debug_conv3_cycle_count),
        .debug_conv3_tile_count_o(debug_conv3_tile_count),
        .debug_conv3_output_count_o(debug_conv3_output_count),
        .debug_conv4_cycle_count_o(debug_conv4_cycle_count),
        .debug_conv4_tile_count_o(debug_conv4_tile_count),
        .debug_conv4_output_count_o(debug_conv4_output_count),
        .debug_pool2_cycle_count_o(debug_pool2_cycle_count),
        .debug_pool2_output_count_o(debug_pool2_output_count),
        .debug_conv5_cycle_count_o(debug_conv5_cycle_count),
        .debug_conv5_tile_count_o(debug_conv5_tile_count),
        .debug_conv5_output_count_o(debug_conv5_output_count),
        .debug_conv6_cycle_count_o(debug_conv6_cycle_count),
        .debug_conv6_tile_count_o(debug_conv6_tile_count),
        .debug_conv6_output_count_o(debug_conv6_output_count),
        .debug_pool3_cycle_count_o(debug_pool3_cycle_count),
        .debug_pool3_output_count_o(debug_pool3_output_count),
        .debug_gap_cycle_count_o(debug_gap_cycle_count),
        .debug_gap_output_count_o(debug_gap_output_count),
        .debug_fc1_cycle_count_o(debug_fc1_cycle_count),
        .debug_fc1_output_count_o(debug_fc1_output_count),
        .debug_fc2_cycle_count_o(debug_fc2_cycle_count),
        .debug_fc2_output_count_o(debug_fc2_output_count)
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
            require_file(golden_logits_hex);
            require_file(labels_hex);

            $readmemh(input_hex, input_mem);
            $readmemh(weight_hex, weight_mem);
            $readmemh(bias_hex, bias_mem);
            $readmemh(requant_mult_hex, requant_mult_mem);
            $readmemh(requant_shift_hex, requant_shift_mem);
            $readmemh(golden_logits_hex, golden_logits);
            $readmemh(labels_hex, labels);
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
            input_addr <= addr[13:0];
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
            weight_addr <= addr[18:0];
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
            param_addr <= addr[9:0];
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

    task automatic load_model_memories;
        begin
            for (int i = 0; i < MODEL_WEIGHT_COUNT; i++) begin
                write_weight(i, weight_mem[i]);
            end
            for (int i = 0; i < MODEL_PARAM_COUNT; i++) begin
                write_param(i, bias_mem[i], requant_mult_mem[i], requant_shift_mem[i]);
            end
        end
    endtask

    task automatic load_case_input(input int case_idx);
        begin
            for (int i = 0; i < INPUT_COUNT; i++) begin
                write_input(i, input_mem[(case_idx * INPUT_COUNT) + i]);
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

    task automatic check_case(input int case_idx);
        int idx;
        int wait_cycles;
        int case_outputs_seen;
        int pred_idx;
        logic signed [7:0] pred_value;
        begin
            wait_cycles = 0;
            case_outputs_seen = 0;
            for (int i = 0; i < FC2_OUT_COUNT; i++) begin
                seen_output[i] = 1'b0;
                case_logits[i] = '0;
            end

            do begin
                @(posedge clk);
                #1;
                wait_cycles++;
                if (wait_cycles > TIMEOUT_CYCLES) begin
                    $fatal(1,
                           "Timeout waiting for full-network case %0d after %0d cycles",
                           case_idx, wait_cycles);
                end

                if (output_valid) begin
                    idx = int'(output_index);
                    case_outputs_seen++;
                    total_outputs_seen++;
                    if (idx < 0 || idx >= FC2_OUT_COUNT) begin
                        $fatal(1, "FC2 output index out of range: %0d", idx);
                    end
                    if (seen_output[idx]) begin
                        duplicate_outputs++;
                        if (first_duplicate_case < 0) begin
                            first_duplicate_case = case_idx;
                            first_duplicate_idx = idx;
                        end
                    end
                    seen_output[idx] = 1'b1;
                    case_logits[idx] = data;

                    if (data !== golden_logits[(case_idx * FC2_OUT_COUNT) + idx]) begin
                        out_mismatches++;
                        if (first_out_mismatch_case < 0) begin
                            first_out_mismatch_case = case_idx;
                            first_out_mismatch_idx = idx;
                            first_out_got = data;
                            first_out_expected = golden_logits[(case_idx * FC2_OUT_COUNT) + idx];
                        end
                    end
                end
            end while (!done);

            if (case_outputs_seen != FC2_OUT_COUNT) begin
                $fatal(1, "Expected %0d logits for case %0d, got %0d",
                       FC2_OUT_COUNT, case_idx, case_outputs_seen);
            end

            pred_idx = 0;
            pred_value = case_logits[0];
            for (int i = 1; i < FC2_OUT_COUNT; i++) begin
                if (case_logits[i] > pred_value) begin
                    pred_idx = i;
                    pred_value = case_logits[i];
                end
            end

            $display(
                "ANIMALS10_FULL_NETWORK_CASE case=%0d label=%0d prediction=%0d outputs=%0d out_mismatches_so_far=%0d total_cycles=%0d",
                case_idx,
                int'(labels[case_idx]),
                pred_idx,
                case_outputs_seen,
                out_mismatches,
                debug_total_cycle_count
            );
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);
        cases_to_run = TEST_CASE_COUNT;
        has_max_cases_plusarg = $value$plusargs("MAX_CASES=%d", cases_to_run);
        if (cases_to_run < 1 || cases_to_run > TEST_CASE_COUNT) begin
            $fatal(1, "MAX_CASES must be in range 1..%0d, got %0d", TEST_CASE_COUNT, cases_to_run);
        end

        input_hex = $sformatf("%s/animals10_test_inputs_i8.hex", export_dir);
        weight_hex = $sformatf("%s/animals10_weights_i8.hex", export_dir);
        bias_hex = $sformatf("%s/animals10_bias_i32.hex", export_dir);
        requant_mult_hex = $sformatf("%s/animals10_requant_mult_i32.hex", export_dir);
        requant_shift_hex = $sformatf("%s/animals10_requant_shift_i8.hex", export_dir);
        golden_logits_hex = $sformatf("%s/animals10_test_logits_i8.hex", export_dir);
        labels_hex = $sformatf("%s/animals10_test_labels.hex", export_dir);

        $display("Animals-10 full-network balanced DUT bench");
        $display("  export_dir=%s", export_dir);
        $display("  cases_to_run=%0d", cases_to_run);

        clear_inputs();
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        load_hex_files();
        load_model_memories();

        total_outputs_seen = 0;
        out_mismatches = 0;
        duplicate_outputs = 0;
        first_out_mismatch_case = -1;
        first_out_mismatch_idx = -1;
        first_duplicate_case = -1;
        first_duplicate_idx = -1;
        first_out_got = '0;
        first_out_expected = '0;

        for (int case_idx = 0; case_idx < cases_to_run; case_idx++) begin
            load_case_input(case_idx);
            start_dut();
            check_case(case_idx);
        end

        $display(
            "ANIMALS10_FULL_NETWORK_BALANCED cases=%0d outputs_seen=%0d out_mismatches=%0d duplicates=%0d",
            cases_to_run, total_outputs_seen, out_mismatches, duplicate_outputs
        );

        if (first_duplicate_case >= 0) begin
            $display("FIRST_DUPLICATE case=%0d idx=%0d", first_duplicate_case, first_duplicate_idx);
        end
        if (first_out_mismatch_case >= 0) begin
            $display("FIRST_OUT_MISMATCH case=%0d idx=%0d got=%0d expected=%0d",
                     first_out_mismatch_case,
                     first_out_mismatch_idx,
                     first_out_got,
                     first_out_expected);
        end

        if (total_outputs_seen != cases_to_run * FC2_OUT_COUNT) begin
            $fatal(1, "Expected %0d final logits, got %0d",
                   cases_to_run * FC2_OUT_COUNT, total_outputs_seen);
        end
        if (duplicate_outputs != 0 || out_mismatches != 0) begin
            $fatal(1, "Animals-10 balanced full-network DUT did not match Python INT8 logits");
        end

        $display("PASS: Animals-10 balanced full-network DUT matches Python INT8 logits");
        $finish;
    end
endmodule

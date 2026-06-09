`timescale 1ns/1ps

module test_animals10_conv1_dut_case0;
    localparam int IN_C = 3;
    localparam int IN_H = 64;
    localparam int IN_W = 64;
    localparam int OUT_C = 32;
    localparam int OUT_H = 64;
    localparam int OUT_W = 64;
    localparam int K_H = 3;
    localparam int K_W = 3;

    localparam int INPUT_COUNT = IN_C * IN_H * IN_W;
    localparam int CONV1_WEIGHT_COUNT = OUT_C * IN_C * K_H * K_W;
    localparam int MODEL_WEIGHT_COUNT = 304224;
    localparam int MODEL_PARAM_COUNT = 586;
    localparam int CONV1_OUT_COUNT = OUT_C * OUT_H * OUT_W;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;

    logic input_we;
    logic [13:0] input_addr;
    logic signed [7:0] input_data;

    logic weight_we;
    logic [9:0] weight_addr;
    logic signed [7:0] weight_data;

    logic param_we;
    logic [4:0] param_addr;
    logic signed [31:0] bias_data;
    logic signed [31:0] requant_mult_data;
    logic signed [7:0] requant_shift_data;

    logic output_valid;
    logic output_last;
    logic [16:0] output_index;
    logic signed [31:0] acc;
    logic signed [7:0] data;

    logic signed [7:0] input_mem[0:INPUT_COUNT-1];
    logic signed [7:0] weight_mem[0:MODEL_WEIGHT_COUNT-1];
    logic signed [31:0] bias_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] requant_mult_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [7:0] requant_shift_mem[0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] golden_acc[0:CONV1_OUT_COUNT-1];
    logic signed [7:0] golden_out[0:CONV1_OUT_COUNT-1];

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
    int outputs_seen;
    int first_acc_mismatch;
    int first_out_mismatch;
    bit has_export_dir_plusarg;

    animals10_conv1_direct dut (
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
        .data_o(data)
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
            weight_addr <= addr[9:0];
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
            param_addr <= addr[4:0];
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
            for (int i = 0; i < CONV1_WEIGHT_COUNT; i++) begin
                write_weight(i, weight_mem[i]);
            end
            for (int i = 0; i < OUT_C; i++) begin
                write_param(i, bias_mem[i], requant_mult_mem[i], requant_shift_mem[i]);
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
        begin
            acc_mismatches = 0;
            out_mismatches = 0;
            outputs_seen = 0;
            first_acc_mismatch = -1;
            first_out_mismatch = -1;

            do begin
                @(posedge clk);
                #1;
                if (output_valid) begin
                    idx = int'(output_index);
                    outputs_seen++;
                    if (acc !== golden_acc[idx]) begin
                        acc_mismatches++;
                        if (first_acc_mismatch < 0) begin
                            first_acc_mismatch = idx;
                        end
                    end
                    if (data !== golden_out[idx]) begin
                        out_mismatches++;
                        if (first_out_mismatch < 0) begin
                            first_out_mismatch = idx;
                        end
                    end
                end
            end while (!done);

            $display("ANIMALS10_CONV1_DUT outputs_seen=%0d acc_mismatches=%0d out_mismatches=%0d",
                     outputs_seen, acc_mismatches, out_mismatches);

            if (first_acc_mismatch >= 0) begin
                $display("FIRST_ACC_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_acc_mismatch, acc, golden_acc[first_acc_mismatch]);
            end
            if (first_out_mismatch >= 0) begin
                $display("FIRST_OUT_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_out_mismatch, data, golden_out[first_out_mismatch]);
            end

            if (outputs_seen != CONV1_OUT_COUNT) begin
                $fatal(1, "Expected %0d Conv1 outputs, got %0d", CONV1_OUT_COUNT, outputs_seen);
            end
            if (acc_mismatches != 0 || out_mismatches != 0) begin
                $fatal(1, "Animals-10 Conv1 DUT did not match Python INT8 golden output");
            end

            $display("PASS: Animals-10 Conv1 DUT matches Python INT8 golden output");
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);

        input_hex = $sformatf("%s/animals10_test_inputs_i8.hex", export_dir);
        weight_hex = $sformatf("%s/animals10_weights_i8.hex", export_dir);
        bias_hex = $sformatf("%s/animals10_bias_i32.hex", export_dir);
        requant_mult_hex = $sformatf("%s/animals10_requant_mult_i32.hex", export_dir);
        requant_shift_hex = $sformatf("%s/animals10_requant_shift_i8.hex", export_dir);
        golden_acc_hex = $sformatf("%s/debug_case0/conv1_acc_i32.hex", export_dir);
        golden_out_hex = $sformatf("%s/debug_case0/conv1_out_i8.hex", export_dir);

        $display("Animals-10 Conv1 DUT bench");
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


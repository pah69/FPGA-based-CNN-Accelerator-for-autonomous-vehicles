`timescale 1ns/1ps

module test_animals10_conv1_case0;
    localparam int IN_C = 3;
    localparam int IN_H = 64;
    localparam int IN_W = 64;
    localparam int OUT_C = 32;
    localparam int OUT_H = 64;
    localparam int OUT_W = 64;
    localparam int K_H = 3;
    localparam int K_W = 3;
    localparam int PAD = 1;

    localparam int INPUT_VALUES_PER_CASE = IN_C * IN_H * IN_W;
    localparam int DEFAULT_TEST_CASES = 10;
    localparam int TOTAL_INPUT_VALUES = INPUT_VALUES_PER_CASE * DEFAULT_TEST_CASES;
    localparam int CONV1_WEIGHT_COUNT = OUT_C * IN_C * K_H * K_W;
    localparam int MODEL_WEIGHT_COUNT = 304224;
    localparam int MODEL_PARAM_COUNT = 586;
    localparam int CONV1_OUT_COUNT = OUT_C * OUT_H * OUT_W;

    logic signed [7:0]  input_all      [0:TOTAL_INPUT_VALUES-1];
    logic signed [7:0]  weight_all     [0:MODEL_WEIGHT_COUNT-1];
    logic signed [31:0] bias_all       [0:MODEL_PARAM_COUNT-1];
    logic signed [31:0] requant_mult   [0:MODEL_PARAM_COUNT-1];
    logic signed [7:0]  requant_shift  [0:MODEL_PARAM_COUNT-1];

    logic signed [31:0] golden_acc     [0:CONV1_OUT_COUNT-1];
    logic signed [7:0]  golden_out     [0:CONV1_OUT_COUNT-1];
    logic signed [31:0] computed_acc   [0:CONV1_OUT_COUNT-1];
    logic signed [7:0]  computed_out   [0:CONV1_OUT_COUNT-1];

    string export_dir;
    string input_hex;
    string weight_hex;
    string bias_hex;
    string requant_mult_hex;
    string requant_shift_hex;
    string golden_acc_hex;
    string golden_out_hex;

    int case_index;
    int case_base;
    int acc_mismatches;
    int out_mismatches;
    int first_acc_mismatch;
    int first_out_mismatch;
    bit has_export_dir_plusarg;
    bit has_case_index_plusarg;

    function automatic int input_idx(input int c, input int y, input int x);
        return (c * IN_H * IN_W) + (y * IN_W) + x;
    endfunction

    function automatic int weight_idx(input int oc, input int ic, input int ky, input int kx);
        return (((oc * IN_C + ic) * K_H + ky) * K_W + kx);
    endfunction

    function automatic int output_idx(input int oc, input int y, input int x);
        return (oc * OUT_H * OUT_W) + (y * OUT_W) + x;
    endfunction

    function automatic int signed input_value(input int c, input int y, input int x);
        if (y < 0 || y >= IN_H || x < 0 || x >= IN_W) begin
            return 0;
        end
        return int'(input_all[case_base + input_idx(c, y, x)]);
    endfunction

    function automatic longint signed round_shift_i64(input longint signed value, input int shift);
        longint signed offset;
        if (shift == 0) begin
            return value;
        end
        offset = 64'sd1 <<< (shift - 1);
        if (value >= 0) begin
            return (value + offset) >>> shift;
        end
        return (value - offset) >>> shift;
    endfunction

    function automatic int signed clamp_i8(input longint signed value);
        if (value > 127) begin
            return 127;
        end
        if (value < -128) begin
            return -128;
        end
        return int'(value);
    endfunction

    function automatic int signed requant_relu(
        input int oc,
        input longint signed acc
    );
        longint signed biased;
        longint signed product;
        longint signed scaled;
        int signed clipped;

        biased = acc + longint'(bias_all[oc]);
        product = biased * longint'(requant_mult[oc]);
        scaled = round_shift_i64(product, int'(requant_shift[oc]));
        clipped = clamp_i8(scaled);
        if (clipped < 0) begin
            return 0;
        end
        return clipped;
    endfunction

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

    task automatic load_files;
        begin
            require_file(input_hex);
            require_file(weight_hex);
            require_file(bias_hex);
            require_file(requant_mult_hex);
            require_file(requant_shift_hex);
            require_file(golden_acc_hex);
            require_file(golden_out_hex);

            $readmemh(input_hex, input_all);
            $readmemh(weight_hex, weight_all);
            $readmemh(bias_hex, bias_all);
            $readmemh(requant_mult_hex, requant_mult);
            $readmemh(requant_shift_hex, requant_shift);
            $readmemh(golden_acc_hex, golden_acc);
            $readmemh(golden_out_hex, golden_out);
        end
    endtask

    task automatic compute_conv1;
        longint signed acc;
        int signed out_q;
        int out_i;
        int in_y;
        int in_x;
        int oc;
        int oy;
        int ox;
        int ic;
        int ky;
        int kx;
        begin
            for (oc = 0; oc < OUT_C; oc++) begin
                for (oy = 0; oy < OUT_H; oy++) begin
                    for (ox = 0; ox < OUT_W; ox++) begin
                        acc = 0;
                        for (ic = 0; ic < IN_C; ic++) begin
                            for (ky = 0; ky < K_H; ky++) begin
                                for (kx = 0; kx < K_W; kx++) begin
                                    in_y = oy + ky - PAD;
                                    in_x = ox + kx - PAD;
                                    acc += longint'(input_value(ic, in_y, in_x))
                                         * longint'(weight_all[weight_idx(oc, ic, ky, kx)]);
                                end
                            end
                        end

                        out_i = output_idx(oc, oy, ox);
                        computed_acc[out_i] = acc[31:0];
                        out_q = requant_relu(oc, acc);
                        computed_out[out_i] = out_q[7:0];
                    end
                end
            end
        end
    endtask

    task automatic compare_outputs;
        int i;
        begin
            acc_mismatches = 0;
            out_mismatches = 0;
            first_acc_mismatch = -1;
            first_out_mismatch = -1;

            for (i = 0; i < CONV1_OUT_COUNT; i++) begin
                if (computed_acc[i] !== golden_acc[i]) begin
                    acc_mismatches++;
                    if (first_acc_mismatch < 0) begin
                        first_acc_mismatch = i;
                    end
                end
                if (computed_out[i] !== golden_out[i]) begin
                    out_mismatches++;
                    if (first_out_mismatch < 0) begin
                        first_out_mismatch = i;
                    end
                end
            end

            $display("ANIMALS10_CONV1 case=%0d acc_mismatches=%0d out_mismatches=%0d",
                     case_index, acc_mismatches, out_mismatches);

            if (first_acc_mismatch >= 0) begin
                $display("FIRST_ACC_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_acc_mismatch,
                         computed_acc[first_acc_mismatch],
                         golden_acc[first_acc_mismatch]);
            end

            if (first_out_mismatch >= 0) begin
                $display("FIRST_OUT_MISMATCH idx=%0d got=%0d expected=%0d",
                         first_out_mismatch,
                         computed_out[first_out_mismatch],
                         golden_out[first_out_mismatch]);
            end

            if (acc_mismatches != 0 || out_mismatches != 0) begin
                $fatal(1, "Animals-10 Conv1 case %0d did not match Python INT8 golden output", case_index);
            end

            $display("PASS: Animals-10 Conv1 case %0d matches Python INT8 golden output", case_index);
        end
    endtask

    initial begin
        export_dir = "../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export";
        case_index = 0;

        has_export_dir_plusarg = $value$plusargs("EXPORT_DIR=%s", export_dir);
        has_case_index_plusarg = $value$plusargs("CASE_INDEX=%d", case_index);

        if (case_index < 0 || case_index >= DEFAULT_TEST_CASES) begin
            $fatal(1, "CASE_INDEX=%0d outside supported range 0..%0d", case_index, DEFAULT_TEST_CASES - 1);
        end

        case_base = case_index * INPUT_VALUES_PER_CASE;
        input_hex = $sformatf("%s/animals10_test_inputs_i8.hex", export_dir);
        weight_hex = $sformatf("%s/animals10_weights_i8.hex", export_dir);
        bias_hex = $sformatf("%s/animals10_bias_i32.hex", export_dir);
        requant_mult_hex = $sformatf("%s/animals10_requant_mult_i32.hex", export_dir);
        requant_shift_hex = $sformatf("%s/animals10_requant_shift_i8.hex", export_dir);
        golden_acc_hex = $sformatf("%s/debug_case0/conv1_acc_i32.hex", export_dir);
        golden_out_hex = $sformatf("%s/debug_case0/conv1_out_i8.hex", export_dir);

        $display("Animals-10 Conv1 contract bench");
        $display("  export_dir=%s", export_dir);
        $display("  case_index=%0d", case_index);

        load_files();
        compute_conv1();
        compare_outputs();
        $finish;
    end
endmodule

`timescale 1ns / 1ps

module tb_systolic_array_4x4;

    localparam int DATA_WIDTH = 17;
    localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;

    logic clk;
    logic rst_n;

    logic signed [(4*DATA_WIDTH)-1:0] act_in_flat;
    logic                             act_valid_i;

    logic signed [(4*DATA_WIDTH)-1:0] wgt_in_flat;
    logic                             wgt_ld_i;

    logic signed [(4*PSUM_WIDTH)-1:0] out_flat;
    logic        [3:0]                out_valid;

    logic signed [DATA_WIDTH-1:0] a0, a1, a2, a3;
    logic signed [DATA_WIDTH-1:0] w0, w1, w2, w3;

    integer err_cnt;

    systolic_array_4x4 #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .act_in_flat(act_in_flat),
        .act_valid_i(act_valid_i),
        .wgt_in_flat(wgt_in_flat),
        .wgt_ld_i   (wgt_ld_i),
        .out_flat   (out_flat),
        .out_valid  (out_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic set_act(
        input logic signed [DATA_WIDTH-1:0] ia0,
        input logic signed [DATA_WIDTH-1:0] ia1,
        input logic signed [DATA_WIDTH-1:0] ia2,
        input logic signed [DATA_WIDTH-1:0] ia3
    );
    begin
        act_in_flat[(0*DATA_WIDTH) +: DATA_WIDTH] = ia0;
        act_in_flat[(1*DATA_WIDTH) +: DATA_WIDTH] = ia1;
        act_in_flat[(2*DATA_WIDTH) +: DATA_WIDTH] = ia2;
        act_in_flat[(3*DATA_WIDTH) +: DATA_WIDTH] = ia3;
    end
    endtask

    task automatic set_wgt(
        input logic signed [DATA_WIDTH-1:0] iw0,
        input logic signed [DATA_WIDTH-1:0] iw1,
        input logic signed [DATA_WIDTH-1:0] iw2,
        input logic signed [DATA_WIDTH-1:0] iw3
    );
    begin
        wgt_in_flat[(0*DATA_WIDTH) +: DATA_WIDTH] = iw0;
        wgt_in_flat[(1*DATA_WIDTH) +: DATA_WIDTH] = iw1;
        wgt_in_flat[(2*DATA_WIDTH) +: DATA_WIDTH] = iw2;
        wgt_in_flat[(3*DATA_WIDTH) +: DATA_WIDTH] = iw3;
    end
    endtask

    task automatic clr_in;
    begin
        act_in_flat = '0;
        act_valid_i = 1'b0;
        wgt_in_flat = '0;
        wgt_ld_i    = 1'b0;
    end
    endtask

    task automatic show_wgt;
    begin
        $display("t=%0t", $time);
        $display("r0 w: %0d %0d %0d %0d",
            dut.weight_00, dut.weight_01, dut.weight_02, dut.weight_03);
        $display("r1 w: %0d %0d %0d %0d",
            dut.weight_10, dut.weight_11, dut.weight_12, dut.weight_13);
        $display("r2 w: %0d %0d %0d %0d",
            dut.weight_20, dut.weight_21, dut.weight_22, dut.weight_23);
        $display("r3 w: %0d %0d %0d %0d",
            dut.weight_30, dut.weight_31, dut.weight_32, dut.weight_33);
    end
    endtask

    task automatic show_act_all;
    begin
        $display("t=%0t", $time);

        $display("row0: pe00=%0d v0=%0b | pe01=%0d v1=%0b | pe02=%0d v2=%0b",
            dut.activation_00, dut.activation_valid_00,
            dut.activation_01, dut.activation_valid_01,
            dut.activation_02, dut.activation_valid_02);

        $display("row1: pe10=%0d v0=%0b | pe11=%0d v1=%0b | pe12=%0d v2=%0b",
            dut.activation_10, dut.activation_valid_10,
            dut.activation_11, dut.activation_valid_11,
            dut.activation_12, dut.activation_valid_12);

        $display("row2: pe20=%0d v0=%0b | pe21=%0d v1=%0b | pe22=%0d v2=%0b",
            dut.activation_20, dut.activation_valid_20,
            dut.activation_21, dut.activation_valid_21,
            dut.activation_22, dut.activation_valid_22);

        $display("row3: pe30=%0d v0=%0b | pe31=%0d v1=%0b | pe32=%0d v2=%0b",
            dut.activation_30, dut.activation_valid_30,
            dut.activation_31, dut.activation_valid_31,
            dut.activation_32, dut.activation_valid_32);
    end
    endtask

    task automatic chk_row_wgt(
        input int rid,
        input logic signed [DATA_WIDTH-1:0] ew0,
        input logic signed [DATA_WIDTH-1:0] ew1,
        input logic signed [DATA_WIDTH-1:0] ew2,
        input logic signed [DATA_WIDTH-1:0] ew3
    );
    begin
        case (rid)
            0: begin
                if ((dut.weight_00 !== ew0) || (dut.weight_01 !== ew1) ||
                    (dut.weight_02 !== ew2) || (dut.weight_03 !== ew3)) begin
                    $display("FAIL: row0 weight");
                    err_cnt = err_cnt + 1;
                end
            end
            1: begin
                if ((dut.weight_10 !== ew0) || (dut.weight_11 !== ew1) ||
                    (dut.weight_12 !== ew2) || (dut.weight_13 !== ew3)) begin
                    $display("FAIL: row1 weight");
                    err_cnt = err_cnt + 1;
                end
            end
            2: begin
                if ((dut.weight_20 !== ew0) || (dut.weight_21 !== ew1) ||
                    (dut.weight_22 !== ew2) || (dut.weight_23 !== ew3)) begin
                    $display("FAIL: row2 weight");
                    err_cnt = err_cnt + 1;
                end
            end
            3: begin
                if ((dut.weight_30 !== ew0) || (dut.weight_31 !== ew1) ||
                    (dut.weight_32 !== ew2) || (dut.weight_33 !== ew3)) begin
                    $display("FAIL: row3 weight");
                    err_cnt = err_cnt + 1;
                end
            end
        endcase
    end
    endtask

    task automatic chk_act_stage0(
        input logic signed [DATA_WIDTH-1:0] e0,
        input logic signed [DATA_WIDTH-1:0] e1,
        input logic signed [DATA_WIDTH-1:0] e2,
        input logic signed [DATA_WIDTH-1:0] e3
    );
    begin
        if (dut.activation_00 !== e0) begin $display("FAIL: activation_00"); err_cnt = err_cnt + 1; end
        if (dut.activation_10 !== e1) begin $display("FAIL: activation_10"); err_cnt = err_cnt + 1; end
        if (dut.activation_20 !== e2) begin $display("FAIL: activation_20"); err_cnt = err_cnt + 1; end
        if (dut.activation_30 !== e3) begin $display("FAIL: activation_30"); err_cnt = err_cnt + 1; end
    end
    endtask

    task automatic chk_act_stage1(
        input logic signed [DATA_WIDTH-1:0] e0,
        input logic signed [DATA_WIDTH-1:0] e1,
        input logic signed [DATA_WIDTH-1:0] e2,
        input logic signed [DATA_WIDTH-1:0] e3
    );
    begin
        if (dut.activation_01 !== e0) begin $display("FAIL: activation_01"); err_cnt = err_cnt + 1; end
        if (dut.activation_11 !== e1) begin $display("FAIL: activation_11"); err_cnt = err_cnt + 1; end
        if (dut.activation_21 !== e2) begin $display("FAIL: activation_21"); err_cnt = err_cnt + 1; end
        if (dut.activation_31 !== e3) begin $display("FAIL: activation_31"); err_cnt = err_cnt + 1; end
    end
    endtask

    task automatic chk_act_stage2(
        input logic signed [DATA_WIDTH-1:0] e0,
        input logic signed [DATA_WIDTH-1:0] e1,
        input logic signed [DATA_WIDTH-1:0] e2,
        input logic signed [DATA_WIDTH-1:0] e3
    );
    begin
        if (dut.activation_02 !== e0) begin $display("FAIL: activation_02"); err_cnt = err_cnt + 1; end
        if (dut.activation_12 !== e1) begin $display("FAIL: activation_12"); err_cnt = err_cnt + 1; end
        if (dut.activation_22 !== e2) begin $display("FAIL: activation_22"); err_cnt = err_cnt + 1; end
        if (dut.activation_32 !== e3) begin $display("FAIL: activation_32"); err_cnt = err_cnt + 1; end
    end
    endtask


    /////////////////////////////////////////////////////////////
    initial begin
        $display("=== tb start ===");

        err_cnt = 0;

        a0 = 17'sd11;
        a1 = 17'sd22;
        a2 = 17'sd33;
        a3 = 17'sd44;

        w0 = 17'sd101;
        w1 = 17'sd202;
        w2 = 17'sd303;
        w3 = 17'sd404;

        rst_n = 1'b0;
        clr_in();

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        ////////////////////////// weight load
        $display("TEST1: weight load");

        @(posedge clk);
        wgt_ld_i = 1'b1;
        set_wgt(w0, w1, w2, w3);

        @(posedge clk);
        wgt_ld_i = 1'b0;
        wgt_in_flat = '0;

        @(posedge clk); #1; show_wgt(); chk_row_wgt(0, w0, w1, w2, w3);
        @(posedge clk); #1; show_wgt(); chk_row_wgt(1, w0, w1, w2, w3);
        @(posedge clk); #1; show_wgt(); chk_row_wgt(2, w0, w1, w2, w3);
        @(posedge clk); #1; show_wgt(); chk_row_wgt(3, w0, w1, w2, w3);


        repeat (30) @(posedge clk);


        /////////////////////// activation shift
        $display("TEST2: act shift all rows");

        @(negedge clk);
        set_act(a0, a1, a2, a3);
        act_valid_i = 1'b1;

        @(negedge clk);
        act_valid_i = 1'b0;
        act_in_flat = '0;

        @(posedge dut.activation_valid_00);
        #1;
        show_act_all();
        chk_act_stage0(a0, a1, a2, a3);

        @(posedge dut.activation_valid_01);
        #1;
        show_act_all();
        chk_act_stage1(a0, a1, a2, a3);

        @(posedge dut.activation_valid_02);
        #1;
        show_act_all();
        chk_act_stage2(a0, a1, a2, a3);

        // if (err_cnt == 0)
        //     $display("ALL PASS");
        // else
        //     $display("DONE WITH %0d ERRORS", err_cnt);

        repeat (20) @(posedge clk);

        ///////////////////////////////////////////////////////////////////////////////
        $finish;
    end

endmodule
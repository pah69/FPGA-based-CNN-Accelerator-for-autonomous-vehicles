`timescale 1ns / 1ps

module tb_systolic_array_4x4;

  localparam int DATA_WIDTH = 17;
  localparam int PSUM_WIDTH = (2 * DATA_WIDTH) + 8;

  logic                             clk;
  logic                             rst_n;

  logic signed [(4*DATA_WIDTH)-1:0] act_in_flat;
  logic                             act_valid_i;

  logic signed [(4*DATA_WIDTH)-1:0] wgt_in_flat;
  logic                             wgt_ld_i;

  logic signed [(4*PSUM_WIDTH)-1:0] out_flat;
  logic        [               3:0] out_valid;

  logic signed [DATA_WIDTH-1:0] a0, a1, a2, a3;
  logic signed [DATA_WIDTH-1:0] w0, w1, w2, w3;

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

  // clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // pack act
  task automatic set_act(
      input logic signed [DATA_WIDTH-1:0] ia0, input logic signed [DATA_WIDTH-1:0] ia1,
      input logic signed [DATA_WIDTH-1:0] ia2, input logic signed [DATA_WIDTH-1:0] ia3);
    begin
      act_in_flat[(0*DATA_WIDTH)+:DATA_WIDTH] = ia0;
      act_in_flat[(1*DATA_WIDTH)+:DATA_WIDTH] = ia1;
      act_in_flat[(2*DATA_WIDTH)+:DATA_WIDTH] = ia2;
      act_in_flat[(3*DATA_WIDTH)+:DATA_WIDTH] = ia3;
    end
  endtask

  // pack wgt
  task automatic set_wgt(
      input logic signed [DATA_WIDTH-1:0] iw0, input logic signed [DATA_WIDTH-1:0] iw1,
      input logic signed [DATA_WIDTH-1:0] iw2, input logic signed [DATA_WIDTH-1:0] iw3);
    begin
      wgt_in_flat[(0*DATA_WIDTH)+:DATA_WIDTH] = iw0;
      wgt_in_flat[(1*DATA_WIDTH)+:DATA_WIDTH] = iw1;
      wgt_in_flat[(2*DATA_WIDTH)+:DATA_WIDTH] = iw2;
      wgt_in_flat[(3*DATA_WIDTH)+:DATA_WIDTH] = iw3;
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
      $display("r0 w: %0d %0d %0d %0d", dut.weight_00, dut.weight_01, dut.weight_02, dut.weight_03);
      $display("r1 w: %0d %0d %0d %0d", dut.weight_10, dut.weight_11, dut.weight_12, dut.weight_13);
      $display("r2 w: %0d %0d %0d %0d", dut.weight_20, dut.weight_21, dut.weight_22, dut.weight_23);
      $display("r3 w: %0d %0d %0d %0d", dut.weight_30, dut.weight_31, dut.weight_32, dut.weight_33);
    end
  endtask

  task automatic show_act_row0;
    begin
      $display("t=%0t", $time);
      $display("row0 act: in=%0d s0=%0d s1=%0d s2=%0d ", dut.act0_i, dut.activation_00,
               dut.activation_01, dut.activation_02);
    end
  endtask

  task automatic chk_row_wgt(input int rid, input logic signed [DATA_WIDTH-1:0] ew0,
                             input logic signed [DATA_WIDTH-1:0] ew1,
                             input logic signed [DATA_WIDTH-1:0] ew2,
                             input logic signed [DATA_WIDTH-1:0] ew3);
    begin
      case (rid)
        0: begin
          if ((dut.weight_00 !== ew0) || (dut.weight_01 !== ew1) ||
                    (dut.weight_02 !== ew2) || (dut.weight_03 !== ew3)) begin
            $display("FAIL: row0 weight");
            show_wgt();
            $finish;
          end
        end
        1: begin
          if ((dut.weight_10 !== ew0) || (dut.weight_11 !== ew1) ||
                    (dut.weight_12 !== ew2) || (dut.weight_13 !== ew3)) begin
            $display("FAIL: row1 weight");
            show_wgt();
            $finish;
          end
        end
        2: begin
          if ((dut.weight_20 !== ew0) || (dut.weight_21 !== ew1) ||
                    (dut.weight_22 !== ew2) || (dut.weight_23 !== ew3)) begin
            $display("FAIL: row2 weight");
            show_wgt();
            $finish;
          end
        end
        3: begin
          if ((dut.weight_30 !== ew0) || (dut.weight_31 !== ew1) ||
                    (dut.weight_32 !== ew2) || (dut.weight_33 !== ew3)) begin
            $display("FAIL: row3 weight");
            show_wgt();
            $finish;
          end
        end
      endcase
    end
  endtask

  task automatic chk_act_s0(input logic signed [DATA_WIDTH-1:0] ea);
    begin
      if (dut.activation_00 !== ea) begin
        $display("FAIL: activation_00");
        show_act_row0();
        // $finish;
      end
    end
  endtask


  task automatic chk_act_stage0(
      input logic signed [DATA_WIDTH-1:0] e0, input logic signed [DATA_WIDTH-1:0] e1,
      input logic signed [DATA_WIDTH-1:0] e2, input logic signed [DATA_WIDTH-1:0] e3);
    begin
      if (dut.activation_00 !== e0) $display("FAIL: activation_00");
      if (dut.activation_10 !== e1) $display("FAIL: activation_10");
      if (dut.activation_20 !== e2) $display("FAIL: activation_20");
      if (dut.activation_30 !== e3) $display("FAIL: activation_30");
    end
  endtask



  task automatic chk_act_s1(input logic signed [DATA_WIDTH-1:0] ea);
    begin
      if (dut.activation_01 !== ea) begin
        $display("FAIL: activation_01");
        show_act_row0();
        // $finish;
      end
    end
  endtask


  task automatic chk_act_stage1(
      input logic signed [DATA_WIDTH-1:0] e0, input logic signed [DATA_WIDTH-1:0] e1,
      input logic signed [DATA_WIDTH-1:0] e2, input logic signed [DATA_WIDTH-1:0] e3);
    begin
      if (dut.activation_01 !== e0) $display("FAIL: activation_01");
      if (dut.activation_11 !== e1) $display("FAIL: activation_11");
      if (dut.activation_21 !== e2) $display("FAIL: activation_21");
      if (dut.activation_31 !== e3) $display("FAIL: activation_31");
    end
  endtask


  task automatic chk_act_s2(input logic signed [DATA_WIDTH-1:0] ea);
    begin
      if (dut.activation_02 !== ea) begin
        $display("FAIL: activation_02");
        show_act_row0();
        // $finish;
      end
    end
  endtask


  task automatic chk_act_stage2(
      input logic signed [DATA_WIDTH-1:0] e0, input logic signed [DATA_WIDTH-1:0] e1,
      input logic signed [DATA_WIDTH-1:0] e2, input logic signed [DATA_WIDTH-1:0] e3);
    begin
      if (dut.activation_02 !== e0) $display("FAIL: activation_02");
      if (dut.activation_12 !== e1) $display("FAIL: activation_12");
      if (dut.activation_22 !== e2) $display("FAIL: activation_22");
      if (dut.activation_32 !== e3) $display("FAIL: activation_32");
    end
  endtask


  task automatic show_act_all;
    begin
      $display("t=%0t", $time);

      $display("row0: pe00=%0d v0=%0b | pe01=%0d v1=%0b | pe02=%0d v2=%0b", dut.activation_00,
               dut.activation_valid_00, dut.activation_01, dut.activation_valid_01,
               dut.activation_02, dut.activation_valid_02);

      $display("row1: pe10=%0d v0=%0b | pe11=%0d v1=%0b | pe12=%0d v2=%0b", dut.activation_10,
               dut.activation_valid_10, dut.activation_11, dut.activation_valid_11,
               dut.activation_12, dut.activation_valid_12);

      $display("row2: pe20=%0d v0=%0b | pe21=%0d v1=%0b | pe22=%0d v2=%0b", dut.activation_20,
               dut.activation_valid_20, dut.activation_21, dut.activation_valid_21,
               dut.activation_22, dut.activation_valid_22);

      $display("row3: pe30=%0d v0=%0b | pe31=%0d v1=%0b | pe32=%0d v2=%0b", dut.activation_30,
               dut.activation_valid_30, dut.activation_31, dut.activation_valid_31,
               dut.activation_32, dut.activation_valid_32);
    end
  endtask




  initial begin
    $display("=== tb start ===");
    $dumpfile("tb_systolic_array_4x4.vcd");
    $dumpvars(0, tb_systolic_array_4x4);

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

    // ///////////////////////////////////// test 1: weight load ///////////////////////////////


    ///////////////// load weight all 4 rows


    // $display("TEST1: weight load");

    // set_wgt(w0, w1, w2, w3);
    // wgt_ld_i = 1'b1;
    // @(posedge clk);
    // wgt_ld_i = 1'b0;

    // // row0 loads on same edge as wgt_ld_i = 1
    // #1;
    // show_wgt();
    // chk_row_wgt(0, w0, w1, w2, w3);

    // @(posedge clk);
    // #1;
    // show_wgt();
    // chk_row_wgt(1, w0, w1, w2, w3);

    // @(posedge clk);
    // #1;
    // show_wgt();
    // chk_row_wgt(2, w0, w1, w2, w3);

    // @(posedge clk);
    // #1;
    // show_wgt();
    // chk_row_wgt(3, w0, w1, w2, w3);

    // $display("PASS: weight load");

    // // clear inputs
    // clr_in();
    // @(posedge clk);

    // // test 2: act shift row0
    // $display("TEST2: act shift row0");

    // set_act(a0, '0, '0, '0);
    // act_valid_i = 1'b1;
    // @(posedge clk);
    // act_valid_i = 1'b0;
    // act_in_flat = '0;

    // // each hop through PE is 3 cycles
    // repeat (3) @(posedge clk);
    // #1;
    // show_act_row0();
    // chk_act_s0(a0);

    // repeat (3) @(posedge clk);
    // #1;
    // show_act_row0();
    // chk_act_s1(a0);

    // repeat (3) @(posedge clk);
    // #1;
    // show_act_row0();
    // chk_act_s2(a0);// clear inputs
    // clr_in();
    // @(posedge clk);
    ////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// Success //////////////////

    // single ROW 0 test /////
    // test 2: act shift row0
    // $display("TEST2: act shift row0");

    // @(negedge clk);
    // set_act(a0, '0, '0, '0);
    // act_valid_i = 1'b1;

    // @(negedge clk);
    // act_valid_i = 1'b0;
    // act_in_flat = '0;

    // @(posedge dut.activation_valid_00);
    // #1;
    // show_act_row0();
    // chk_act_s0(a0);

    // @(posedge dut.activation_valid_01);
    // #1;
    // show_act_row0();
    // chk_act_s1(a0);

    // @(posedge dut.activation_valid_02);
    // #1;
    // show_act_row0();
    // chk_act_s2(a0);

    // repeat (50) @(posedge clk);

    /////////////////////////////////////////////////////////////////////////


    // test 2: act shift all rows
    $display("TEST2: act shift all rows");

    @(negedge clk);
    set_act(a0, a1, a2, a3);
    act_valid_i = 1'b1;

    @(negedge clk);
    act_valid_i = 1'b0;
    act_in_flat = '0;

    // stage 0
    @(posedge dut.activation_valid_00);
    #1;
    show_act_all();
    chk_act_stage0(a0, a1, a2, a3);

    // stage 1
    @(posedge dut.activation_valid_01);
    #1;
    show_act_all();
    chk_act_stage1(a0, a1, a2, a3);

    // stage 2
    @(posedge dut.activation_valid_02);
    #1;
    show_act_all();
    chk_act_stage2(a0, a1, a2, a3);


    repeat (50) @(posedge clk);
    // $display("PASS: act shift all rows");
    $finish;
  end
endmodule

`timescale 1ns / 1ps
module adder #(
    parameter DATA_WIDTH = 17
) (
    input  logic signed [DATA_WIDTH*2:0] a_i,
    input  logic signed [DATA_WIDTH*2:0] b_i,
    output logic signed [DATA_WIDTH*2:0] sum
);
  assign sum = a_i + b_i;
endmodule



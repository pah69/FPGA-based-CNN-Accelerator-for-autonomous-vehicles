`timescale 1ns / 1ps

import layer_descriptor_pkg::*;

// Combinational ROM for the four compute-layer descriptors.
module layer_descriptor_rom (
    input logic [1:0] layer_idx_i,

    output logic        valid_o,
    output layer_type_t layer_type_o,
    output logic [15:0] in_h_o,
    output logic [15:0] in_w_o,
    output logic [15:0] in_ch_o,
    output logic [15:0] out_h_o,
    output logic [15:0] out_w_o,
    output logic [15:0] out_ch_o,
    output logic [15:0] kernel_h_o,
    output logic [15:0] kernel_w_o,
    output logic [15:0] k_total_o,
    output logic [15:0] num_k_tiles_o,
    output logic [15:0] num_oc_tiles_o,
    output logic [15:0] num_spatial_o,
    output logic [15:0] weight_base_o,
    output logic [15:0] bias_base_o,
    output logic [15:0] requant_base_o,
    output act_mode_t   act_mode_o,
    output logic        read_bank_o,
    output logic        write_bank_o
);

  always_comb begin
    valid_o        = 1'b1;
    layer_type_o   = LAYER_CONV;
    in_h_o         = '0;
    in_w_o         = '0;
    in_ch_o        = '0;
    out_h_o        = '0;
    out_w_o        = '0;
    out_ch_o       = '0;
    kernel_h_o     = '0;
    kernel_w_o     = '0;
    k_total_o      = '0;
    num_k_tiles_o  = '0;
    num_oc_tiles_o = '0;
    num_spatial_o  = '0;
    weight_base_o  = '0;
    bias_base_o    = '0;
    requant_base_o = '0;
    act_mode_o     = ACT_RELU;
    read_bank_o    = 1'b0;
    write_bank_o   = 1'b1;

    unique case (layer_idx_i)
      LAYER_IDX_CONV1: begin
        layer_type_o   = LAYER_CONV;
        in_h_o         = CONV1_IN_H;
        in_w_o         = CONV1_IN_W;
        in_ch_o        = CONV1_IN_CH;
        out_h_o        = CONV1_OUT_H;
        out_w_o        = CONV1_OUT_W;
        out_ch_o       = CONV1_OUT_CH;
        kernel_h_o     = CONV1_KERNEL_H;
        kernel_w_o     = CONV1_KERNEL_W;
        k_total_o      = CONV1_K_TOTAL;
        num_k_tiles_o  = CONV1_NUM_K_TILES;
        num_oc_tiles_o = CONV1_NUM_OC_TILES;
        num_spatial_o  = CONV1_NUM_SPATIAL;
        weight_base_o  = CONV1_WEIGHT_BASE;
        bias_base_o    = CONV1_BIAS_BASE;
        requant_base_o = CONV1_REQUANT_BASE;
        act_mode_o     = ACT_RELU;
        read_bank_o    = 1'b0;
        write_bank_o   = 1'b1;
      end

      LAYER_IDX_CONV2: begin
        layer_type_o   = LAYER_CONV;
        in_h_o         = CONV2_IN_H;
        in_w_o         = CONV2_IN_W;
        in_ch_o        = CONV2_IN_CH;
        out_h_o        = CONV2_OUT_H;
        out_w_o        = CONV2_OUT_W;
        out_ch_o       = CONV2_OUT_CH;
        kernel_h_o     = CONV2_KERNEL_H;
        kernel_w_o     = CONV2_KERNEL_W;
        k_total_o      = CONV2_K_TOTAL;
        num_k_tiles_o  = CONV2_NUM_K_TILES;
        num_oc_tiles_o = CONV2_NUM_OC_TILES;
        num_spatial_o  = CONV2_NUM_SPATIAL;
        weight_base_o  = CONV2_WEIGHT_BASE;
        bias_base_o    = CONV2_BIAS_BASE;
        requant_base_o = CONV2_REQUANT_BASE;
        act_mode_o     = ACT_RELU;
        read_bank_o    = 1'b0;
        write_bank_o   = 1'b1;
      end

      LAYER_IDX_FC1: begin
        layer_type_o   = LAYER_FC;
        in_h_o         = FC1_IN_H;
        in_w_o         = FC1_IN_W;
        in_ch_o        = FC1_IN_CH;
        out_h_o        = FC1_OUT_H;
        out_w_o        = FC1_OUT_W;
        out_ch_o       = FC1_OUT_CH;
        kernel_h_o     = FC1_KERNEL_H;
        kernel_w_o     = FC1_KERNEL_W;
        k_total_o      = FC1_K_TOTAL;
        num_k_tiles_o  = FC1_NUM_K_TILES;
        num_oc_tiles_o = FC1_NUM_OC_TILES;
        num_spatial_o  = FC1_NUM_SPATIAL;
        weight_base_o  = FC1_WEIGHT_BASE;
        bias_base_o    = FC1_BIAS_BASE;
        requant_base_o = FC1_REQUANT_BASE;
        act_mode_o     = ACT_RELU;
        read_bank_o    = 1'b0;
        write_bank_o   = 1'b1;
      end

      LAYER_IDX_FC2: begin
        layer_type_o   = LAYER_FC;
        in_h_o         = FC2_IN_H;
        in_w_o         = FC2_IN_W;
        in_ch_o        = FC2_IN_CH;
        out_h_o        = FC2_OUT_H;
        out_w_o        = FC2_OUT_W;
        out_ch_o       = FC2_OUT_CH;
        kernel_h_o     = FC2_KERNEL_H;
        kernel_w_o     = FC2_KERNEL_W;
        k_total_o      = FC2_K_TOTAL;
        num_k_tiles_o  = FC2_NUM_K_TILES;
        num_oc_tiles_o = FC2_NUM_OC_TILES;
        num_spatial_o  = FC2_NUM_SPATIAL;
        weight_base_o  = FC2_WEIGHT_BASE;
        bias_base_o    = FC2_BIAS_BASE;
        requant_base_o = FC2_REQUANT_BASE;
        act_mode_o     = ACT_BYPASS;
        read_bank_o    = 1'b1;
        write_bank_o   = 1'b0;
      end

      default: begin
        valid_o = 1'b0;
      end
    endcase
  end

endmodule : layer_descriptor_rom

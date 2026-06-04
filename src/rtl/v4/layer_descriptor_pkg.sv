`timescale 1ns / 1ps

package layer_descriptor_pkg;

  typedef enum logic [1:0] {
    LAYER_CONV = 2'd0,
    LAYER_FC   = 2'd1
  } layer_type_t;

  typedef enum logic [1:0] {
    ACT_BYPASS = 2'd0,
    ACT_RELU   = 2'd1
  } act_mode_t;

  typedef struct packed {
    layer_type_t layer_type;
    logic [15:0] in_h;
    logic [15:0] in_w;
    logic [15:0] in_ch;
    logic [15:0] out_h;
    logic [15:0] out_w;
    logic [15:0] out_ch;
    logic [15:0] kernel_h;
    logic [15:0] kernel_w;
    logic [15:0] k_total;
    logic [15:0] num_k_tiles;
    logic [15:0] num_oc_tiles;
    logic [15:0] num_spatial;
    logic [15:0] weight_base;
    logic [15:0] bias_base;
    logic [15:0] requant_base;
    act_mode_t act_mode;
    logic read_bank;
    logic write_bank;
  } layer_desc_t;

  localparam int CNN_NUM_LAYERS = 4;

  localparam logic [1:0] LAYER_IDX_CONV1 = 2'd0;
  localparam logic [1:0] LAYER_IDX_CONV2 = 2'd1;
  localparam logic [1:0] LAYER_IDX_FC1   = 2'd2;
  localparam logic [1:0] LAYER_IDX_FC2   = 2'd3;

  localparam logic [15:0] CONV1_IN_H = 16'd28;
  localparam logic [15:0] CONV1_IN_W = 16'd28;
  localparam logic [15:0] CONV1_IN_CH = 16'd1;
  localparam logic [15:0] CONV1_OUT_H = 16'd26;
  localparam logic [15:0] CONV1_OUT_W = 16'd26;
  localparam logic [15:0] CONV1_OUT_CH = 16'd8;
  localparam logic [15:0] CONV1_KERNEL_H = 16'd3;
  localparam logic [15:0] CONV1_KERNEL_W = 16'd3;
  localparam logic [15:0] CONV1_K_TOTAL = 16'd9;
  localparam logic [15:0] CONV1_NUM_K_TILES = 16'd5;
  localparam logic [15:0] CONV1_NUM_OC_TILES = 16'd4;
  localparam logic [15:0] CONV1_NUM_SPATIAL = 16'd676;
  localparam logic [15:0] CONV1_WEIGHT_BASE = 16'd0;
  localparam logic [15:0] CONV1_BIAS_BASE = 16'd0;
  localparam logic [15:0] CONV1_REQUANT_BASE = 16'd0;

  localparam logic [15:0] CONV2_IN_H = 16'd13;
  localparam logic [15:0] CONV2_IN_W = 16'd13;
  localparam logic [15:0] CONV2_IN_CH = 16'd8;
  localparam logic [15:0] CONV2_OUT_H = 16'd11;
  localparam logic [15:0] CONV2_OUT_W = 16'd11;
  localparam logic [15:0] CONV2_OUT_CH = 16'd10;
  localparam logic [15:0] CONV2_KERNEL_H = 16'd3;
  localparam logic [15:0] CONV2_KERNEL_W = 16'd3;
  localparam logic [15:0] CONV2_K_TOTAL = 16'd72;
  localparam logic [15:0] CONV2_NUM_K_TILES = 16'd36;
  localparam logic [15:0] CONV2_NUM_OC_TILES = 16'd5;
  localparam logic [15:0] CONV2_NUM_SPATIAL = 16'd121;
  localparam logic [15:0] CONV2_WEIGHT_BASE = 16'd72;
  localparam logic [15:0] CONV2_BIAS_BASE = 16'd8;
  localparam logic [15:0] CONV2_REQUANT_BASE = 16'd8;

  localparam logic [15:0] FC1_IN_H = 16'd1;
  localparam logic [15:0] FC1_IN_W = 16'd1;
  localparam logic [15:0] FC1_IN_CH = 16'd250;
  localparam logic [15:0] FC1_OUT_H = 16'd1;
  localparam logic [15:0] FC1_OUT_W = 16'd1;
  localparam logic [15:0] FC1_OUT_CH = 16'd16;
  localparam logic [15:0] FC1_KERNEL_H = 16'd1;
  localparam logic [15:0] FC1_KERNEL_W = 16'd1;
  localparam logic [15:0] FC1_K_TOTAL = 16'd250;
  localparam logic [15:0] FC1_NUM_K_TILES = 16'd125;
  localparam logic [15:0] FC1_NUM_OC_TILES = 16'd8;
  localparam logic [15:0] FC1_NUM_SPATIAL = 16'd1;
  localparam logic [15:0] FC1_WEIGHT_BASE = 16'd792;
  localparam logic [15:0] FC1_BIAS_BASE = 16'd18;
  localparam logic [15:0] FC1_REQUANT_BASE = 16'd18;

  localparam logic [15:0] FC2_IN_H = 16'd1;
  localparam logic [15:0] FC2_IN_W = 16'd1;
  localparam logic [15:0] FC2_IN_CH = 16'd16;
  localparam logic [15:0] FC2_OUT_H = 16'd1;
  localparam logic [15:0] FC2_OUT_W = 16'd1;
  localparam logic [15:0] FC2_OUT_CH = 16'd10;
  localparam logic [15:0] FC2_KERNEL_H = 16'd1;
  localparam logic [15:0] FC2_KERNEL_W = 16'd1;
  localparam logic [15:0] FC2_K_TOTAL = 16'd16;
  localparam logic [15:0] FC2_NUM_K_TILES = 16'd8;
  localparam logic [15:0] FC2_NUM_OC_TILES = 16'd5;
  localparam logic [15:0] FC2_NUM_SPATIAL = 16'd1;
  localparam logic [15:0] FC2_WEIGHT_BASE = 16'd4792;
  localparam logic [15:0] FC2_BIAS_BASE = 16'd34;
  localparam logic [15:0] FC2_REQUANT_BASE = 16'd34;

endpackage : layer_descriptor_pkg

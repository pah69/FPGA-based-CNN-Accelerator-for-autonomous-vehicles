#ifndef SINGLE_CASE_GOLDENS_H
#define SINGLE_CASE_GOLDENS_H

#include "tpu_axi_lite.h"

#define SINGLE_CASE_CONV1_COUNT 5408U
#define SINGLE_CASE_CONV2_COUNT 1210U
#define SINGLE_CASE_FC1_COUNT 16U
#define SINGLE_CASE_FC2_COUNT 10U

extern const s32 golden_layer0_conv_acc_i32[5408];
extern const s8 golden_layer0_out_i8[5408];
extern const s32 golden_layer1_conv_acc_i32[1210];
extern const s8 golden_layer1_out_i8[1210];
extern const s32 golden_layer2_fc_acc_i32[16];
extern const s8 golden_layer2_out_i8[16];
extern const s32 golden_layer3_fc_acc_i32[10];
extern const s8 golden_final_logits_i8[10];

#endif

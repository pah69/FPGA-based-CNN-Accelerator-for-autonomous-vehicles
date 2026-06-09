#ifndef GOLDEN_MODEL_H
#define GOLDEN_MODEL_H

#include "tpu_axi_lite.h"

#define GOLDEN_CONV1_OUT_COUNT  5408U
#define GOLDEN_POOL1_OUT_COUNT  1352U
#define GOLDEN_CONV2_OUT_COUNT  1210U
#define GOLDEN_POOL2_OUT_COUNT  250U
#define GOLDEN_FC1_OUT_COUNT    16U
#define GOLDEN_FC2_OUT_COUNT    10U

typedef struct {
    s32 conv1_acc[GOLDEN_CONV1_OUT_COUNT];
    s8 conv1_out[GOLDEN_CONV1_OUT_COUNT];
    s8 pool1_out[GOLDEN_POOL1_OUT_COUNT];
    s32 conv2_acc[GOLDEN_CONV2_OUT_COUNT];
    s8 conv2_out[GOLDEN_CONV2_OUT_COUNT];
    s8 pool2_out[GOLDEN_POOL2_OUT_COUNT];
    s32 fc1_acc[GOLDEN_FC1_OUT_COUNT];
    s8 fc1_out[GOLDEN_FC1_OUT_COUNT];
    s32 fc2_acc[GOLDEN_FC2_OUT_COUNT];
    s8 logits[TPU_LOGIT_COUNT];
} golden_layers_t;

typedef struct {
    u64 conv1_ticks;
    u64 pool1_ticks;
    u64 conv2_ticks;
    u64 pool2_ticks;
    u64 fc1_ticks;
    u64 fc2_ticks;
    u64 total_ticks;
} golden_profile_t;

void golden_model_run_profile(const s8 input[TPU_IMAGE_SIZE],
                              golden_layers_t *layers,
                              golden_profile_t *profile);

#endif

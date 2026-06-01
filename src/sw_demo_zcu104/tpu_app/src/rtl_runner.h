#ifndef RTL_RUNNER_H
#define RTL_RUNNER_H

#include "tpu_axi_lite.h"

typedef struct {
    int status_code;
    u32 status_reg;
    u32 error_reg;
    u32 cycles;
    tpu_layer_cycles_t layer_cycles;
    tpu_phase_profile_t phase_profile;
    u64 wall_ticks;
    u64 input_write_ticks;
    u64 wait_ticks;
    u64 output_read_ticks;
    s8 logits[TPU_LOGIT_COUNT];
} rtl_result_t;

int rtl_run_image(const s8 image[TPU_IMAGE_SIZE], rtl_result_t *result);

#endif

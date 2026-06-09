#ifndef CPU_FAST_MODEL_H
#define CPU_FAST_MODEL_H

#include "tpu_axi_lite.h"

void cpu_fast_infer_i8(const s8 input[TPU_IMAGE_SIZE], s8 logits[TPU_LOGIT_COUNT]);

#endif

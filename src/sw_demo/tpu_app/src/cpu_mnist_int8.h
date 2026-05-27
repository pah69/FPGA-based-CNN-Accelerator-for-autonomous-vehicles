#ifndef CPU_MNIST_INT8_H
#define CPU_MNIST_INT8_H

#include "tpu_axi_lite.h"

void cpu_mnist_infer_i8(const s8 input[TPU_IMAGE_SIZE], s8 logits[TPU_LOGIT_COUNT]);

#endif

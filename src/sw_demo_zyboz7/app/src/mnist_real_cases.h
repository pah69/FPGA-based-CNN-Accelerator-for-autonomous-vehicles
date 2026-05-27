#ifndef MNIST_REAL_CASES_H
#define MNIST_REAL_CASES_H

#include "tpu_axi_lite.h"
#include "xil_types.h"

typedef struct {
    const char *name;
    s8 label;
    s8 expected_prediction;
    s8 expected_logits[TPU_LOGIT_COUNT];
} mnist_real_case_t;

u32 mnist_real_case_count(void);
const mnist_real_case_t *mnist_real_case_get(u32 index);
int mnist_real_case_fill_input(u32 index, s8 input[TPU_IMAGE_SIZE]);

#endif

#ifndef MNIST_REAL_CASES_H
#define MNIST_REAL_CASES_H

#include "tpu_axi_lite.h"

#define MNIST_REAL_CASE_COUNT 10000U
#define MNIST_REAL_CASE_START 0U

extern const s8 mnist_real_inputs[MNIST_REAL_CASE_COUNT][TPU_IMAGE_SIZE];
extern const s8 mnist_real_expected_logits[MNIST_REAL_CASE_COUNT][TPU_LOGIT_COUNT];
extern const s8 mnist_real_labels[MNIST_REAL_CASE_COUNT];
extern const s8 mnist_real_expected_predictions[MNIST_REAL_CASE_COUNT];

#endif

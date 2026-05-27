#ifndef MNIST_CASES_H
#define MNIST_CASES_H

#include "tpu_axi_lite.h"
#include "xil_types.h"

#define MNIST_LABEL_UNKNOWN ((s8)-1)

typedef enum {
    MNIST_CASE_KIND_FAKE = 0,
    MNIST_CASE_KIND_REAL = 1
} mnist_case_kind_t;

typedef enum {
    MNIST_PATTERN_ZERO = 0,
    MNIST_PATTERN_IMPULSE_CENTER = 1,
    MNIST_PATTERN_CHECKER_PM32 = 2,
    MNIST_PATTERN_REAL = 3
} mnist_case_pattern_t;

typedef struct {
    const char *name;
    mnist_case_kind_t kind;
    mnist_case_pattern_t pattern;
    s8 label;
    s8 expected_prediction;
    s8 expected_logits[TPU_LOGIT_COUNT];
    u32 real_index;
} mnist_case_t;

u32 mnist_case_count(void);
int mnist_case_get(u32 index, mnist_case_t *test_case);
int mnist_case_make_input(const mnist_case_t *test_case, s8 input[TPU_IMAGE_SIZE]);
const char *mnist_case_kind_name(mnist_case_kind_t kind);

#endif

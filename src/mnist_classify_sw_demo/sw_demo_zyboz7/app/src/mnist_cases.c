#include "mnist_cases.h"

#include "mnist_real_cases.h"

static const mnist_case_t fake_cases[] = {
    {
        "fake_zero_image",
        MNIST_CASE_KIND_FAKE,
        MNIST_PATTERN_ZERO,
        MNIST_LABEL_UNKNOWN,
        1,
        { -4, 3, 2, -3, -4, 1, -2, 3, 0, -5 },
        0U
    },
    {
        "fake_impulse_center_127",
        MNIST_CASE_KIND_FAKE,
        MNIST_PATTERN_IMPULSE_CENTER,
        MNIST_LABEL_UNKNOWN,
        2,
        { -12, -3, 3, 3, 0, 2, -5, 0, -2, 0 },
        0U
    },
    {
        "fake_checker_pm32",
        MNIST_CASE_KIND_FAKE,
        MNIST_PATTERN_CHECKER_PM32,
        MNIST_LABEL_UNKNOWN,
        1,
        { -5, 3, 2, -1, -4, 1, -5, 3, -1, -5 },
        0U
    }
};

static u32 fake_case_count(void)
{
    return (u32)(sizeof(fake_cases) / sizeof(fake_cases[0]));
}

static void clear_input(s8 input[TPU_IMAGE_SIZE])
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        input[idx] = 0;
    }
}

static void copy_logits(s8 dst[TPU_LOGIT_COUNT], const s8 src[TPU_LOGIT_COUNT])
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        dst[idx] = src[idx];
    }
}

u32 mnist_case_count(void)
{
    return fake_case_count() + mnist_real_case_count();
}

int mnist_case_get(u32 index, mnist_case_t *test_case)
{
    u32 fake_count = fake_case_count();
    const mnist_real_case_t *real_case = 0;

    if (test_case == 0) {
        return -1;
    }

    if (index < fake_count) {
        *test_case = fake_cases[index];
        return 0;
    }

    real_case = mnist_real_case_get(index - fake_count);
    if (real_case == 0) {
        return -1;
    }

    test_case->name = real_case->name;
    test_case->kind = MNIST_CASE_KIND_REAL;
    test_case->pattern = MNIST_PATTERN_REAL;
    test_case->label = real_case->label;
    test_case->expected_prediction = real_case->expected_prediction;
    copy_logits(test_case->expected_logits, real_case->expected_logits);
    test_case->real_index = index - fake_count;
    return 0;
}

int mnist_case_make_input(const mnist_case_t *test_case, s8 input[TPU_IMAGE_SIZE])
{
    if ((test_case == 0) || (input == 0)) {
        return -1;
    }

    clear_input(input);

    switch (test_case->pattern) {
    case MNIST_PATTERN_ZERO:
        return 0;

    case MNIST_PATTERN_IMPULSE_CENTER:
        input[(14U * 28U) + 14U] = 127;
        return 0;

    case MNIST_PATTERN_CHECKER_PM32:
        for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
            u32 row = idx / 28U;
            u32 col = idx % 28U;
            input[idx] = (((row + col) & 1U) == 0U) ? 32 : -32;
        }
        return 0;

    case MNIST_PATTERN_REAL:
        return mnist_real_case_fill_input(test_case->real_index, input);

    default:
        return -1;
    }
}

const char *mnist_case_kind_name(mnist_case_kind_t kind)
{
    return (kind == MNIST_CASE_KIND_REAL) ? "real" : "fake";
}

#include "tpu_axi_lite.h"
#include "mnist_real_cases.h"

#include "xil_printf.h"
#include "xil_types.h"

#define TPU_INFERENCE_TIMEOUT_POLLS 100000000U

static const s8 expected_zero_logits[TPU_LOGIT_COUNT] = {
    -4, 3, 2, -3, -4, 1, -2, 3, 0, -5
};

static void print_logits(const char *label, const s8 logits[TPU_LOGIT_COUNT])
{
    xil_printf("%s {%d,%d,%d,%d,%d,%d,%d,%d,%d,%d}\r\n",
               label,
               (int)logits[0], (int)logits[1], (int)logits[2], (int)logits[3],
               (int)logits[4], (int)logits[5], (int)logits[6], (int)logits[7],
               (int)logits[8], (int)logits[9]);
}

static s8 argmax_logits(const s8 logits[TPU_LOGIT_COUNT])
{
    s8 best_idx = 0;
    s8 best_value = logits[0];

    for (u32 idx = 1U; idx < TPU_LOGIT_COUNT; idx++) {
        if (logits[idx] > best_value) {
            best_value = logits[idx];
            best_idx = (s8)idx;
        }
    }

    return best_idx;
}

static char image_pixel_char(s8 value)
{
    if (value <= 0) {
        return '.';
    }
    if (value < 24) {
        return ':';
    }
    if (value < 64) {
        return '*';
    }
    return '#';
}

static void print_image_preview_14x14(const s8 image[TPU_IMAGE_SIZE])
{
    xil_printf("image preview 14x14:\r\n");
    for (u32 y = 0U; y < 28U; y += 2U) {
        for (u32 x = 0U; x < 28U; x += 2U) {
            s8 max_value = image[(y * 28U) + x];
            s8 value = image[(y * 28U) + x + 1U];
            if (value > max_value) {
                max_value = value;
            }
            value = image[((y + 1U) * 28U) + x];
            if (value > max_value) {
                max_value = value;
            }
            value = image[((y + 1U) * 28U) + x + 1U];
            if (value > max_value) {
                max_value = value;
            }
            xil_printf("%c", image_pixel_char(max_value));
        }
        xil_printf("\r\n");
    }
}

static int run_ub_smoke_test(void)
{
    s8 value = 0;

    xil_printf("TEST: UB smoke\r\n");
    tpu_clear_status();

    if (tpu_ub_write(0U, 0U, (s8)0x12) != 0) {
        xil_printf("FAIL: bank0 write cmd error status=0x%08x\r\n", tpu_status());
        return -1;
    }

    if (tpu_ub_read(0U, 0U, &value) != 0 || value != (s8)0x12) {
        xil_printf("FAIL: bank0 readback got=%d status=0x%08x\r\n", (int)value, tpu_status());
        return -1;
    }

    if (tpu_ub_write(1U, 4095U, (s8)-5) != 0) {
        xil_printf("FAIL: bank1 write cmd error status=0x%08x\r\n", tpu_status());
        return -1;
    }

    if (tpu_ub_read(1U, 4095U, &value) != 0 || value != (s8)-5) {
        xil_printf("FAIL: bank1 readback got=%d status=0x%08x\r\n", (int)value, tpu_status());
        return -1;
    }

    xil_printf("PASS: UB smoke\r\n");
    return 0;
}

static int load_image(const s8 image[TPU_IMAGE_SIZE])
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        if (tpu_ub_write(0U, idx, image[idx]) != 0) {
            xil_printf("FAIL: image write addr=%u status=0x%08x\r\n", idx, tpu_status());
            return -1;
        }
    }

    return 0;
}

static int read_logits(s8 logits[TPU_LOGIT_COUNT])
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (tpu_ub_read(0U, idx, &logits[idx]) != 0) {
            xil_printf("FAIL: logit read idx=%u status=0x%08x\r\n", idx, tpu_status());
            return -1;
        }
    }

    return 0;
}

static int compare_logits(const s8 actual[TPU_LOGIT_COUNT],
                          const s8 expected[TPU_LOGIT_COUNT])
{
    int fail_count = 0;

    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (actual[idx] != expected[idx]) {
            xil_printf("FAIL: logit[%u] got=%d expected=%d\r\n",
                       idx, (int)actual[idx], (int)expected[idx]);
            fail_count++;
        }
    }

    return fail_count;
}

static int run_inference_case(const char *name,
                              const s8 image[TPU_IMAGE_SIZE],
                              const s8 expected_logits[TPU_LOGIT_COUNT],
                              s8 expected_label,
                              s8 expected_prediction_ref,
                              int show_preview)
{
    s8 logits[TPU_LOGIT_COUNT] = {0};
    s8 actual_prediction = 0;
    s8 expected_prediction = 0;
    u32 status = 0U;

    xil_printf("CASE: %s\r\n", name);
    if (expected_label >= 0) {
        xil_printf("label=%d\r\n", (int)expected_label);
    }
    if (show_preview != 0) {
        print_image_preview_14x14(image);
    }

    tpu_clear_status();

    if (load_image(image) != 0) {
        return -1;
    }

    tpu_write_reg(TPU_REG_CONTROL, TPU_CONTROL_START);

    if (tpu_wait_done(TPU_INFERENCE_TIMEOUT_POLLS, &status) != 0) {
        xil_printf("FAIL: inference timeout/error status=0x%08x err=0x%08x\r\n",
                   status, tpu_error());
        return -1;
    }

    xil_printf("INFO: cycles=%u status=0x%08x\r\n", tpu_cycles(), status);

    if (read_logits(logits) != 0) {
        return -1;
    }

    print_logits("actual logits  ", logits);
    print_logits("expected logits", expected_logits);

    actual_prediction = argmax_logits(logits);
    expected_prediction = argmax_logits(expected_logits);
    if ((expected_prediction_ref >= 0) && (expected_prediction_ref != expected_prediction)) {
        xil_printf("FAIL: golden prediction=%d does not match expected logits argmax=%d\r\n",
                   (int)expected_prediction_ref, (int)expected_prediction);
        return -1;
    }

    if (expected_prediction_ref >= 0) {
        expected_prediction = expected_prediction_ref;
    }

    xil_printf("prediction actual=%d expected=%d",
               (int)actual_prediction, (int)expected_prediction);
    if (expected_label >= 0) {
        xil_printf(" label=%d", (int)expected_label);
    }
    xil_printf("\r\n");

    if (compare_logits(logits, expected_logits) != 0) {
        return -1;
    }

    if (actual_prediction != expected_prediction) {
        xil_printf("FAIL: prediction mismatch\r\n");
        return -1;
    }

    if ((expected_label >= 0) && (actual_prediction != expected_label)) {
        xil_printf("FAIL: predicted class does not match label\r\n");
        return -1;
    }

    xil_printf("PASS: %s\r\n", name);
    return 0;
}

static int run_zero_image_inference(void)
{
    static const s8 zero_image[TPU_IMAGE_SIZE] = {0};

    xil_printf("TEST: zero-image inference\r\n");
    if (run_inference_case("zero_image", zero_image, expected_zero_logits, (s8)-1, (s8)-1, 0) != 0) {
        return -1;
    }

    xil_printf("PASS: zero-image inference\r\n");
    return 0;
}

static int run_real_mnist_inference(void)
{
    u32 pass_count = 0U;

    xil_printf("TEST: real MNIST inference\r\n");
    xil_printf("cases=%u source=18_05/e2e_cases\r\n", MNIST_REAL_CASE_COUNT);

    for (u32 idx = 0U; idx < MNIST_REAL_CASE_COUNT; idx++) {
        xil_printf("\r\nMNIST case %u/%u\r\n", idx + 1U, MNIST_REAL_CASE_COUNT);
        if (run_inference_case(mnist_real_cases[idx].name,
                               mnist_real_cases[idx].input,
                               mnist_real_cases[idx].expected_logits,
                               mnist_real_cases[idx].label,
                               mnist_real_cases[idx].expected_prediction,
                               1) != 0) {
            xil_printf("FAIL: real MNIST case %u\r\n", idx);
            return -1;
        }
        pass_count++;
    }

    xil_printf("PASS: real MNIST cases %u/%u\r\n", pass_count, MNIST_REAL_CASE_COUNT);
    return 0;
}

int main(void)
{
    xil_printf("\r\nTPU MNIST ZCU104 bare-metal demo\r\n");
    xil_printf("TPU_BASEADDR=0x%08x\r\n", TPU_BASEADDR);
    xil_printf("initial status=0x%08x\r\n", tpu_status());

    if (run_ub_smoke_test() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    if (run_zero_image_inference() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    if (run_real_mnist_inference() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    xil_printf("RESULT: PASS\r\n");
    return 0;
}

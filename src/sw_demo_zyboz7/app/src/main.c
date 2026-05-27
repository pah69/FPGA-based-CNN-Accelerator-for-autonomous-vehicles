#include "mnist_cases.h"
#include "tpu_axi_lite.h"

#include "xil_printf.h"
#include "xil_types.h"

#define TPU_READY_TIMEOUT_POLLS      1000000U
#define TPU_INFERENCE_TIMEOUT_POLLS  100000000U

#ifndef TPU_CASE_LIMIT
#define TPU_CASE_LIMIT 0U
#endif

static s8 image_buffer[TPU_IMAGE_SIZE];
static s8 actual_logits[TPU_LOGIT_COUNT];

static void print_logits(const char *label, const s8 logits[TPU_LOGIT_COUNT])
{
    xil_printf("%s {%d,%d,%d,%d,%d,%d,%d,%d,%d,%d}\r\n",
               label,
               (int)logits[0], (int)logits[1], (int)logits[2], (int)logits[3],
               (int)logits[4], (int)logits[5], (int)logits[6], (int)logits[7],
               (int)logits[8], (int)logits[9]);
}

static s8 argmax_i8(const s8 logits[TPU_LOGIT_COUNT])
{
    u32 best = 0U;

    for (u32 idx = 1U; idx < TPU_LOGIT_COUNT; idx++) {
        if (logits[idx] > logits[best]) {
            best = idx;
        }
    }

    return (s8)best;
}

static int run_ub_smoke_test(void)
{
    s8 value = 0;

    xil_printf("TEST: UB smoke\r\n");
    tpu_clear_status();

    if (tpu_wait_ready(TPU_READY_TIMEOUT_POLLS, 0) != 0) {
        xil_printf("FAIL: TPU not ready status=0x%08x debug0=0x%08x\r\n",
                   tpu_status(), tpu_debug0());
        return -1;
    }

    if (tpu_ub_write(0U, 0U, (s8)0x12) != 0) {
        xil_printf("FAIL: bank0 write status=0x%08x\r\n", tpu_status());
        return -1;
    }

    if ((tpu_ub_read(0U, 0U, &value) != 0) || (value != (s8)0x12)) {
        xil_printf("FAIL: bank0 read got=%d status=0x%08x\r\n",
                   (int)value, tpu_status());
        return -1;
    }

    if (tpu_ub_write(1U, 4095U, (s8)-5) != 0) {
        xil_printf("FAIL: bank1 write status=0x%08x\r\n", tpu_status());
        return -1;
    }

    if ((tpu_ub_read(1U, 4095U, &value) != 0) || (value != (s8)-5)) {
        xil_printf("FAIL: bank1 read got=%d status=0x%08x\r\n",
                   (int)value, tpu_status());
        return -1;
    }

    xil_printf("PASS: UB smoke\r\n");
    return 0;
}

static int load_input_image(const s8 input[TPU_IMAGE_SIZE])
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        if (tpu_ub_write(0U, idx, input[idx]) != 0) {
            xil_printf("FAIL: image write addr=%u status=0x%08x\r\n",
                       (unsigned int)idx, tpu_status());
            return -1;
        }
    }

    return 0;
}

static int read_final_logits(s8 logits[TPU_LOGIT_COUNT])
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (tpu_ub_read(0U, idx, &logits[idx]) != 0) {
            xil_printf("FAIL: logit read idx=%u status=0x%08x\r\n",
                       (unsigned int)idx, tpu_status());
            return -1;
        }
    }

    return 0;
}

static int compare_logits(const mnist_case_t *test_case,
                          const s8 logits[TPU_LOGIT_COUNT])
{
    int mismatch_count = 0;

    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (logits[idx] != test_case->expected_logits[idx]) {
            xil_printf("FAIL: %s logit[%u] got=%d expected=%d\r\n",
                       test_case->name, (unsigned int)idx,
                       (int)logits[idx], (int)test_case->expected_logits[idx]);
            mismatch_count++;
        }
    }

    return mismatch_count;
}

static int run_inference_case(u32 index, const mnist_case_t *test_case)
{
    u32 status = 0U;
    s8 actual_prediction = 0;
    int mismatch_count = 0;

    if (mnist_case_make_input(test_case, image_buffer) != 0) {
        xil_printf("FAIL: case[%u] %s could not prepare input\r\n",
                   (unsigned int)index, test_case->name);
        return -1;
    }

    tpu_clear_status();
    if (tpu_wait_ready(TPU_READY_TIMEOUT_POLLS, &status) != 0) {
        xil_printf("FAIL: case[%u] %s not ready status=0x%08x debug0=0x%08x\r\n",
                   (unsigned int)index, test_case->name, status, tpu_debug0());
        return -1;
    }

    if (load_input_image(image_buffer) != 0) {
        return -1;
    }

    if (tpu_start() != 0) {
        xil_printf("FAIL: case[%u] %s start rejected status=0x%08x\r\n",
                   (unsigned int)index, test_case->name, tpu_status());
        return -1;
    }

    if (tpu_wait_done(TPU_INFERENCE_TIMEOUT_POLLS, &status) != 0) {
        xil_printf("FAIL: case[%u] %s timeout/error status=0x%08x err=0x%08x debug0=0x%08x\r\n",
                   (unsigned int)index, test_case->name, status, tpu_error(), tpu_debug0());
        return -1;
    }

    if (read_final_logits(actual_logits) != 0) {
        return -1;
    }

    actual_prediction = argmax_i8(actual_logits);
    mismatch_count = compare_logits(test_case, actual_logits);

    if (actual_prediction != test_case->expected_prediction) {
        xil_printf("FAIL: %s pred=%d expected_pred=%d\r\n",
                   test_case->name, (int)actual_prediction,
                   (int)test_case->expected_prediction);
        mismatch_count++;
    }

    if (mismatch_count != 0) {
        print_logits("actual logits  ", actual_logits);
        print_logits("expected logits", test_case->expected_logits);
        return -1;
    }

    if (test_case->label == MNIST_LABEL_UNKNOWN) {
        xil_printf("PASS: case[%u] %s kind=%s pred=%d cycles16=%u\r\n",
                   (unsigned int)index, test_case->name,
                   mnist_case_kind_name(test_case->kind),
                   (int)actual_prediction, (unsigned int)tpu_cycles());
    } else {
        xil_printf("PASS: case[%u] %s kind=%s label=%d pred=%d cycles16=%u\r\n",
                   (unsigned int)index, test_case->name,
                   mnist_case_kind_name(test_case->kind),
                   (int)test_case->label, (int)actual_prediction,
                   (unsigned int)tpu_cycles());
    }

    return 0;
}

int main(void)
{
    u32 case_count = mnist_case_count();
    u32 pass_count = 0U;
    u32 fail_count = 0U;
    mnist_case_t test_case;

    if ((TPU_CASE_LIMIT != 0U) && (case_count > TPU_CASE_LIMIT)) {
        case_count = TPU_CASE_LIMIT;
    }

    xil_printf("\r\nTPU MNIST Zybo Z7 inference test\r\n");
    xil_printf("TPU_BASEADDR=0x%08x cases=%u\r\n",
               TPU_BASEADDR, (unsigned int)case_count);

    if (run_ub_smoke_test() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    for (u32 idx = 0U; idx < case_count; idx++) {
        if (mnist_case_get(idx, &test_case) != 0) {
            xil_printf("FAIL: could not fetch case[%u]\r\n", (unsigned int)idx);
            fail_count++;
            continue;
        }

        if (run_inference_case(idx, &test_case) == 0) {
            pass_count++;
        } else {
            fail_count++;
        }
    }

    xil_printf("SUMMARY: pass=%u fail=%u total=%u\r\n",
               (unsigned int)pass_count, (unsigned int)fail_count,
               (unsigned int)case_count);
    xil_printf("RESULT: %s\r\n", (fail_count == 0U) ? "PASS" : "FAIL");

    return (fail_count == 0U) ? 0 : 1;
}

#include "tpu_axi_lite.h"

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

static int load_zero_image(void)
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        if (tpu_ub_write(0U, idx, 0) != 0) {
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

static int run_zero_image_inference(void)
{
    s8 logits[TPU_LOGIT_COUNT] = {0};
    u32 status = 0U;

    xil_printf("TEST: zero-image inference\r\n");
    tpu_clear_status();

    if (load_zero_image() != 0) {
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
    print_logits("expected logits", expected_zero_logits);

    if (compare_logits(logits, expected_zero_logits) != 0) {
        return -1;
    }

    xil_printf("PASS: zero-image inference\r\n");
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

    xil_printf("RESULT: PASS\r\n");
    return 0;
}

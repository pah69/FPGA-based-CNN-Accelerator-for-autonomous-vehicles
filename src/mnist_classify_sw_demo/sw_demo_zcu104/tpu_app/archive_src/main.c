#include "tpu_axi_lite.h"
#include "mnist_real_cases.h"
#include "cpu_mnist_int8.h"

#include "xil_printf.h"
#include "xil_types.h"
#include "xiltimer.h"

#define TPU_INFERENCE_TIMEOUT_POLLS 100000000U
#define TPU_PL_CLOCK_HZ 100000000U
#define MNIST_PROGRESS_INTERVAL 1000U
#define MNIST_MAX_CLASS_FAIL_PRINTS 16U
#define RUN_STARTUP_SELF_TESTS 0
#define PRINT_STAGE_LOGS 0
#define PRINT_CLASS_FAIL_DETAILS 0
#define PRINT_DETAILED_TIMING 0

#define INFERENCE_RESULT_PASS       0
#define INFERENCE_RESULT_CLASS_FAIL 1
#define INFERENCE_RESULT_HW_FAIL   -1

static const s8 expected_zero_logits[TPU_LOGIT_COUNT] = {
    -4, 3, 2, -3, -4, 1, -2, 3, 0, -5
};

typedef struct {
    int result;
    s8 prediction;
    u32 cycles;
} inference_result_t;

typedef struct {
    u32 pass_count;
    u32 fail_count;
    u64 wall_ticks;
    u64 prepare_ticks;
    u64 clear_status_ticks;
    u64 input_write_ticks;
    u64 start_ticks;
    u64 wait_done_ticks;
    u64 output_read_ticks;
    u64 postprocess_ticks;
    u32 wall_ms;
    u32 fps_x100;
    u32 total_cycles;
    u32 avg_cycles;
    u32 min_cycles;
    u32 max_cycles;
    u32 raw_total_cycles;
    u32 raw_avg_cycles;
    u32 cycle_counter_wrapped;
    u32 kernel_ms;
    u32 kernel_fps_x100;
    u32 logit_mismatch_count;
    u32 prediction_mismatch_count;
} benchmark_stats_t;

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

static void print_u32_as_decimal_2(const char *label, u32 value_x100)
{
    u32 frac = value_x100 % 100U;

    xil_printf("%s%u.", label, value_x100 / 100U);
    if (frac < 10U) {
        xil_printf("0");
    }
    xil_printf("%u\r\n", frac);
}

static u32 ticks_to_ms(u64 ticks)
{
    return (u32)((ticks * 1000ULL) / (u64)COUNTS_PER_SECOND);
}

static u64 ticks_to_us(u64 ticks)
{
    return (ticks * 1000000ULL) / (u64)COUNTS_PER_SECOND;
}

static u32 percent_x100(u64 part_ticks, u64 total_ticks)
{
    if (total_ticks == 0ULL) {
        return 0U;
    }
    return (u32)(((part_ticks * 10000ULL) + (total_ticks / 2ULL)) / total_ticks);
}

static u32 fps_x100_from_ticks(u32 image_count, u64 ticks)
{
    if (ticks == 0ULL) {
        return 0U;
    }
    return (u32)((((u64)image_count * (u64)COUNTS_PER_SECOND * 100ULL) + (ticks / 2ULL)) / ticks);
}

static u32 fps_x100_from_cycles(u32 cycles_per_image)
{
    if (cycles_per_image == 0U) {
        return 0U;
    }
    return (u32)((((u64)TPU_PL_CLOCK_HZ * 100ULL) + ((u64)cycles_per_image / 2ULL)) /
                 (u64)cycles_per_image);
}

static u64 ticks_to_pl_cycles(u64 ticks)
{
    return ((ticks * (u64)TPU_PL_CLOCK_HZ) + ((u64)COUNTS_PER_SECOND / 2ULL)) /
           (u64)COUNTS_PER_SECOND;
}

static u32 speedup_x100_from_ticks(u64 baseline_ticks, u64 measured_ticks)
{
    if (measured_ticks == 0ULL) {
        return 0U;
    }
    return (u32)(((baseline_ticks * 100ULL) + (measured_ticks / 2ULL)) / measured_ticks);
}

static u32 speedup_x100_from_kernel_cycles(u64 baseline_ticks, u32 kernel_cycles)
{
    u64 cpu_us;
    u64 kernel_us;

    if (kernel_cycles == 0U) {
        return 0U;
    }

    cpu_us = ((baseline_ticks * 1000000ULL) + ((u64)COUNTS_PER_SECOND / 2ULL)) /
             (u64)COUNTS_PER_SECOND;
    kernel_us = ((((u64)kernel_cycles * 1000000ULL) + ((u64)TPU_PL_CLOCK_HZ / 2ULL)) /
                 (u64)TPU_PL_CLOCK_HZ);

    if (kernel_us == 0ULL) {
        return 0U;
    }

    return (u32)(((cpu_us * 100ULL) + (kernel_us / 2ULL)) / kernel_us);
}

static void print_timing_region(const char *label, u64 ticks, u64 total_ticks)
{
    u64 avg_us = 0ULL;
    u32 pct_x100 = percent_x100(ticks, total_ticks);

    if (MNIST_REAL_CASE_COUNT != 0U) {
        avg_us = ticks_to_us(ticks) / (u64)MNIST_REAL_CASE_COUNT;
    }

    xil_printf("%s%u ms avg=%u us/img pct=%u.",
               label, ticks_to_ms(ticks), (u32)avg_us, pct_x100 / 100U);
    if ((pct_x100 % 100U) < 10U) {
        xil_printf("0");
    }
    xil_printf("%u\r\n", pct_x100 % 100U);
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

static int load_image_silent(const s8 image[TPU_IMAGE_SIZE], u32 *fail_addr)
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        if (tpu_ub_write(0U, idx, image[idx]) != 0) {
            if (fail_addr != 0) {
                *fail_addr = idx;
            }
            return -1;
        }
    }

    return 0;
}

static int load_image(const s8 image[TPU_IMAGE_SIZE])
{
    u32 fail_addr = 0U;

    if (load_image_silent(image, &fail_addr) != 0) {
        xil_printf("FAIL: image write addr=%u status=0x%08x\r\n", fail_addr, tpu_status());
        return -1;
    }

    return 0;
}

static int read_logits_silent(s8 logits[TPU_LOGIT_COUNT], u32 *fail_idx)
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (tpu_ub_read(0U, idx, &logits[idx]) != 0) {
            if (fail_idx != 0) {
                *fail_idx = idx;
            }
            return -1;
        }
    }

    return 0;
}

static int read_logits(s8 logits[TPU_LOGIT_COUNT])
{
    u32 fail_idx = 0U;

    if (read_logits_silent(logits, &fail_idx) != 0) {
        xil_printf("FAIL: logit read idx=%u status=0x%08x\r\n", fail_idx, tpu_status());
        return -1;
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

static int logits_match(const s8 actual[TPU_LOGIT_COUNT],
                        const s8 expected[TPU_LOGIT_COUNT])
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (actual[idx] != expected[idx]) {
            return 0;
        }
    }

    return 1;
}

static int run_pl_inference_raw(const s8 image[TPU_IMAGE_SIZE],
                                s8 logits[TPU_LOGIT_COUNT],
                                s8 *prediction,
                                u32 *cycles)
{
    u32 status = 0U;

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

    *cycles = tpu_cycles();

    if (read_logits(logits) != 0) {
        return -1;
    }

    *prediction = argmax_logits(logits);
    return 0;
}

static inference_result_t run_inference_case(const s8 image[TPU_IMAGE_SIZE],
                                             const s8 expected_logits[TPU_LOGIT_COUNT],
                                             s8 expected_label,
                                             s8 expected_prediction_ref,
                                             int show_details)
{
    inference_result_t result = {INFERENCE_RESULT_HW_FAIL, 0, 0U};
    s8 logits[TPU_LOGIT_COUNT] = {0};
    s8 actual_prediction = 0;
    s8 expected_prediction = 0;

    if (run_pl_inference_raw(image, logits, &actual_prediction, &result.cycles) != 0) {
        return result;
    }

    if (show_details != 0) {
        print_logits("actual logits  ", logits);
        print_logits("expected logits", expected_logits);
    }

    expected_prediction = argmax_logits(expected_logits);
    if ((expected_prediction_ref >= 0) && (expected_prediction_ref != expected_prediction)) {
        print_logits("expected logits", expected_logits);
        xil_printf("FAIL: golden prediction=%d does not match expected logits argmax=%d\r\n",
                   (int)expected_prediction_ref, (int)expected_prediction);
        return result;
    }

    if (expected_prediction_ref >= 0) {
        expected_prediction = expected_prediction_ref;
    }

    if (show_details != 0) {
        xil_printf("prediction actual=%d expected=%d",
                   (int)actual_prediction, (int)expected_prediction);
        if (expected_label >= 0) {
            xil_printf(" label=%d", (int)expected_label);
        }
        xil_printf("\r\n");
    }
    result.prediction = actual_prediction;

    if (compare_logits(logits, expected_logits) != 0) {
        print_logits("actual logits  ", logits);
        print_logits("expected logits", expected_logits);
        return result;
    }

    if (actual_prediction != expected_prediction) {
        xil_printf("FAIL: prediction mismatch\r\n");
        return result;
    }

    if ((expected_label >= 0) && (actual_prediction != expected_label)) {
        result.result = INFERENCE_RESULT_CLASS_FAIL;
        return result;
    }

    result.result = INFERENCE_RESULT_PASS;
    return result;
}

static int run_zero_image_inference(void)
{
    static const s8 zero_image[TPU_IMAGE_SIZE] = {0};
    inference_result_t result;

    xil_printf("TEST: zero-image inference\r\n");
    result = run_inference_case(zero_image, expected_zero_logits, (s8)-1, (s8)-1, 0);
    if (result.result != INFERENCE_RESULT_PASS) {
        return -1;
    }

    xil_printf("PASS: zero-image inference cycles=%u\r\n", result.cycles);
    return 0;
}

static int run_cpu_mnist_inference(benchmark_stats_t *stats)
{
    s8 logits[TPU_LOGIT_COUNT];
    u32 first_logit_mismatch = 0U;
    u32 first_prediction_mismatch = 0U;

    if (stats == 0) {
        return -1;
    }

    stats->pass_count = 0U;
    stats->fail_count = 0U;
    stats->wall_ticks = 0ULL;
    stats->wall_ms = 0U;
    stats->fps_x100 = 0U;
    stats->logit_mismatch_count = 0U;
    stats->prediction_mismatch_count = 0U;

#if PRINT_STAGE_LOGS
    xil_printf("TEST: CPU PS INT8 inference\r\n");
    xil_printf("cases=%u start=%u\r\n", MNIST_REAL_CASE_COUNT, MNIST_REAL_CASE_START);
    xil_printf("timed loop has no per-image UART output\r\n");
#endif

    for (u32 idx = 0U; idx < MNIST_REAL_CASE_COUNT; idx++) {
        XTime start_time = 0;
        XTime end_time = 0;
        s8 prediction;

        XTime_GetTime(&start_time);
        cpu_mnist_infer_i8(mnist_real_inputs[idx], logits);
        prediction = argmax_logits(logits);
        XTime_GetTime(&end_time);
        stats->wall_ticks += (u64)(end_time - start_time);

        if (logits_match(logits, mnist_real_expected_logits[idx]) == 0) {
            if (stats->logit_mismatch_count == 0U) {
                first_logit_mismatch = idx;
            }
            stats->logit_mismatch_count++;
        }

        if (prediction != mnist_real_expected_predictions[idx]) {
            if (stats->prediction_mismatch_count == 0U) {
                first_prediction_mismatch = idx;
            }
            stats->prediction_mismatch_count++;
        }

        if (prediction == mnist_real_labels[idx]) {
            stats->pass_count++;
        } else {
            stats->fail_count++;
        }
    }

    stats->wall_ms = ticks_to_ms(stats->wall_ticks);
    stats->fps_x100 = fps_x100_from_ticks(MNIST_REAL_CASE_COUNT, stats->wall_ticks);

#if PRINT_STAGE_LOGS
    xil_printf("\r\nCPU PS classification summary\r\n");
    xil_printf("Pass : %u/%u cases\r\n", stats->pass_count, MNIST_REAL_CASE_COUNT);
    xil_printf("Fails: %u\r\n", stats->fail_count);
    if ((stats->logit_mismatch_count == 0U) && (stats->prediction_mismatch_count == 0U)) {
        xil_printf("CPU/golden logits: PASS\r\n");
    } else {
        xil_printf("CPU/golden logits: FAIL logit_mismatches=%u first=%u prediction_mismatches=%u first=%u\r\n",
                   stats->logit_mismatch_count, first_logit_mismatch,
                   stats->prediction_mismatch_count, first_prediction_mismatch);
    }
    xil_printf("CPU wall time     : %u ms\r\n", stats->wall_ms);
    print_u32_as_decimal_2("CPU FPS           : ", stats->fps_x100);
#else
    if ((stats->logit_mismatch_count != 0U) || (stats->prediction_mismatch_count != 0U)) {
        xil_printf("CPU/golden logits: FAIL logit_mismatches=%u first=%u prediction_mismatches=%u first=%u\r\n",
                   stats->logit_mismatch_count, first_logit_mismatch,
                   stats->prediction_mismatch_count, first_prediction_mismatch);
    }
    (void)first_logit_mismatch;
    (void)first_prediction_mismatch;
#endif

    return ((stats->logit_mismatch_count == 0U) && (stats->prediction_mismatch_count == 0U)) ? 0 : -1;
}

static int run_real_mnist_inference(benchmark_stats_t *stats)
{
    u32 pass_count = 0U;
    u32 fail_count = 0U;
    u32 stored_class_fails = 0U;
    u32 class_fail_case[MNIST_MAX_CLASS_FAIL_PRINTS];
    s8 class_fail_label[MNIST_MAX_CLASS_FAIL_PRINTS];
    s8 class_fail_prediction[MNIST_MAX_CLASS_FAIL_PRINTS];
    u32 total_cycles = 0U;
    u32 min_cycles = 0xFFFFFFFFU;
    u32 max_cycles = 0U;
    u32 avg_cycles = 0U;
    u32 total_time_ms = 0U;
    u32 fps_x100 = 0U;
    u64 wait_cycles_est = 0ULL;
    u32 first_logit_mismatch = 0U;
    u32 first_prediction_mismatch = 0U;
    u32 hw_fail = 0U;
    u32 hw_fail_case = 0U;
    u32 hw_fail_stage = 0U;
    u32 hw_fail_detail = 0U;
    u32 hw_fail_status = 0U;
    XTime loop_start = 0;
    XTime loop_end = 0;

    if (stats == 0) {
        return -1;
    }

    stats->pass_count = 0U;
    stats->fail_count = 0U;
    stats->wall_ticks = 0ULL;
    stats->prepare_ticks = 0ULL;
    stats->clear_status_ticks = 0ULL;
    stats->input_write_ticks = 0ULL;
    stats->start_ticks = 0ULL;
    stats->wait_done_ticks = 0ULL;
    stats->output_read_ticks = 0ULL;
    stats->postprocess_ticks = 0ULL;
    stats->wall_ms = 0U;
    stats->fps_x100 = 0U;
    stats->total_cycles = 0U;
    stats->avg_cycles = 0U;
    stats->min_cycles = 0U;
    stats->max_cycles = 0U;
    stats->raw_total_cycles = 0U;
    stats->raw_avg_cycles = 0U;
    stats->cycle_counter_wrapped = 0U;
    stats->kernel_ms = 0U;
    stats->kernel_fps_x100 = 0U;
    stats->logit_mismatch_count = 0U;
    stats->prediction_mismatch_count = 0U;

#if PRINT_STAGE_LOGS
    xil_printf("TEST: RTL PL accelerator inference\r\n");
    xil_printf("cases=%u start=%u clock_hz=%u\r\n",
               MNIST_REAL_CASE_COUNT, MNIST_REAL_CASE_START, TPU_PL_CLOCK_HZ);
    xil_printf("source=18_05/e2e_cases\r\n");
    xil_printf("timed loop has no per-image UART output\r\n");
#endif

    XTime_GetTime(&loop_start);
    for (u32 idx = 0U; idx < MNIST_REAL_CASE_COUNT; idx++) {
        const s8 *image_ptr;
        s8 logits[TPU_LOGIT_COUNT] = {0};
        s8 prediction = 0;
        s8 expected_prediction;
        u32 cycles = 0U;
        u32 status = 0U;
        u32 fail_addr = 0U;
        u32 fail_idx = 0U;
        int class_failed = 0;
        XTime t0 = 0;
        XTime t1 = 0;
        XTime t2 = 0;
        XTime t3 = 0;
        XTime t4 = 0;
        XTime t5 = 0;
        XTime t6 = 0;
        XTime t7 = 0;

        XTime_GetTime(&t0);
        image_ptr = mnist_real_inputs[idx];
        XTime_GetTime(&t1);

        tpu_clear_status();
        XTime_GetTime(&t2);

        if (load_image_silent(image_ptr, &fail_addr) != 0) {
            XTime_GetTime(&t3);
            stats->prepare_ticks += (u64)(t1 - t0);
            stats->clear_status_ticks += (u64)(t2 - t1);
            stats->input_write_ticks += (u64)(t3 - t2);
            hw_fail = 1U;
            hw_fail_case = idx;
            hw_fail_stage = 1U;
            hw_fail_detail = fail_addr;
            hw_fail_status = tpu_status();
            break;
        }
        XTime_GetTime(&t3);

        tpu_write_reg(TPU_REG_CONTROL, TPU_CONTROL_START);
        XTime_GetTime(&t4);

        if (tpu_wait_done(TPU_INFERENCE_TIMEOUT_POLLS, &status) != 0) {
            XTime_GetTime(&t5);
            stats->prepare_ticks += (u64)(t1 - t0);
            stats->clear_status_ticks += (u64)(t2 - t1);
            stats->input_write_ticks += (u64)(t3 - t2);
            stats->start_ticks += (u64)(t4 - t3);
            stats->wait_done_ticks += (u64)(t5 - t4);
            hw_fail = 1U;
            hw_fail_case = idx;
            hw_fail_stage = 2U;
            hw_fail_detail = 0U;
            hw_fail_status = status;
            break;
        }
        cycles = tpu_cycles();
        XTime_GetTime(&t5);

        if (read_logits_silent(logits, &fail_idx) != 0) {
            XTime_GetTime(&t6);
            stats->prepare_ticks += (u64)(t1 - t0);
            stats->clear_status_ticks += (u64)(t2 - t1);
            stats->input_write_ticks += (u64)(t3 - t2);
            stats->start_ticks += (u64)(t4 - t3);
            stats->wait_done_ticks += (u64)(t5 - t4);
            stats->output_read_ticks += (u64)(t6 - t5);
            hw_fail = 1U;
            hw_fail_case = idx;
            hw_fail_stage = 3U;
            hw_fail_detail = fail_idx;
            hw_fail_status = tpu_status();
            break;
        }
        XTime_GetTime(&t6);

        prediction = argmax_logits(logits);
        if (logits_match(logits, mnist_real_expected_logits[idx]) == 0) {
            if (stats->logit_mismatch_count == 0U) {
                first_logit_mismatch = idx;
            }
            stats->logit_mismatch_count++;
        }

        expected_prediction = argmax_logits(mnist_real_expected_logits[idx]);
        if ((mnist_real_expected_predictions[idx] >= 0) &&
            (mnist_real_expected_predictions[idx] != expected_prediction)) {
            if (stats->prediction_mismatch_count == 0U) {
                first_prediction_mismatch = idx;
            }
            stats->prediction_mismatch_count++;
        }
        if (mnist_real_expected_predictions[idx] >= 0) {
            expected_prediction = mnist_real_expected_predictions[idx];
        }
        if (prediction != expected_prediction) {
            if (stats->prediction_mismatch_count == 0U) {
                first_prediction_mismatch = idx;
            }
            stats->prediction_mismatch_count++;
        }

        total_cycles += cycles;
        if (cycles < min_cycles) {
            min_cycles = cycles;
        }
        if (cycles > max_cycles) {
            max_cycles = cycles;
        }

        class_failed = (prediction != mnist_real_labels[idx]) ? 1 : 0;
        if (class_failed != 0) {
            fail_count++;
            if (stored_class_fails < MNIST_MAX_CLASS_FAIL_PRINTS) {
                class_fail_case[stored_class_fails] = idx;
                class_fail_label[stored_class_fails] = mnist_real_labels[idx];
                class_fail_prediction[stored_class_fails] = prediction;
                stored_class_fails++;
            }
        } else {
            pass_count++;
        }

        XTime_GetTime(&t7);
        stats->prepare_ticks += (u64)(t1 - t0);
        stats->clear_status_ticks += (u64)(t2 - t1);
        stats->input_write_ticks += (u64)(t3 - t2);
        stats->start_ticks += (u64)(t4 - t3);
        stats->wait_done_ticks += (u64)(t5 - t4);
        stats->output_read_ticks += (u64)(t6 - t5);
        stats->postprocess_ticks += (u64)(t7 - t6);
    }
    XTime_GetTime(&loop_end);

    stats->raw_total_cycles = total_cycles;
    if (MNIST_REAL_CASE_COUNT != 0U) {
        stats->raw_avg_cycles = total_cycles / MNIST_REAL_CASE_COUNT;
    }

    wait_cycles_est = ticks_to_pl_cycles(stats->wait_done_ticks);
    if ((wait_cycles_est > 0ULL) &&
        (((u64)total_cycles * 2ULL) < wait_cycles_est) &&
        (wait_cycles_est <= 0xFFFFFFFFULL)) {
        total_cycles = (u32)wait_cycles_est;
        stats->cycle_counter_wrapped = 1U;
    }

    if (MNIST_REAL_CASE_COUNT != 0U) {
        avg_cycles = total_cycles / MNIST_REAL_CASE_COUNT;
    }
    if (TPU_PL_CLOCK_HZ != 0U) {
        total_time_ms = (u32)(((u64)total_cycles * 1000ULL) / (u64)TPU_PL_CLOCK_HZ);
    }
    if (avg_cycles != 0U) {
        fps_x100 = (u32)((((u64)TPU_PL_CLOCK_HZ * 100ULL) + ((u64)avg_cycles / 2ULL)) /
                         (u64)avg_cycles);
    }

    stats->pass_count = pass_count;
    stats->fail_count = fail_count;
    stats->wall_ticks = (u64)(loop_end - loop_start);
    stats->wall_ms = ticks_to_ms(stats->wall_ticks);
    stats->fps_x100 = fps_x100_from_ticks(MNIST_REAL_CASE_COUNT, stats->wall_ticks);
    stats->total_cycles = total_cycles;
    stats->avg_cycles = avg_cycles;
    stats->min_cycles = min_cycles;
    stats->max_cycles = max_cycles;
    stats->kernel_ms = total_time_ms;
    stats->kernel_fps_x100 = fps_x100;

#if PRINT_STAGE_LOGS
    xil_printf("\r\nRTL PL classification summary\r\n");
    xil_printf("Pass : %u/%u cases\r\n", pass_count, MNIST_REAL_CASE_COUNT);
    xil_printf("Fails: %u\r\n", fail_count);
#endif
#if PRINT_CLASS_FAIL_DETAILS
    for (u32 idx = 0U; idx < stored_class_fails; idx++) {
        xil_printf("CLASS FAIL case=%u label=%d prediction=%d\r\n",
                   class_fail_case[idx], (int)class_fail_label[idx], (int)class_fail_prediction[idx]);
    }
    if (fail_count > stored_class_fails) {
        xil_printf("Fail details printed: %u/%u\r\n", stored_class_fails, fail_count);
    }
#endif
#if PRINT_STAGE_LOGS
    if ((stats->logit_mismatch_count == 0U) && (stats->prediction_mismatch_count == 0U)) {
        xil_printf("RTL/golden logits: PASS\r\n");
    } else {
        xil_printf("RTL/golden logits: FAIL logit_mismatches=%u first=%u prediction_mismatches=%u first=%u\r\n",
                   stats->logit_mismatch_count, first_logit_mismatch,
                   stats->prediction_mismatch_count, first_prediction_mismatch);
    }
    if (hw_fail != 0U) {
        xil_printf("PL HW failure: case=%u stage=%u detail=%u status=0x%08x\r\n",
                   hw_fail_case, hw_fail_stage, hw_fail_detail, hw_fail_status);
    }
#else
    if ((stats->logit_mismatch_count != 0U) || (stats->prediction_mismatch_count != 0U)) {
        xil_printf("RTL/golden logits: FAIL logit_mismatches=%u first=%u prediction_mismatches=%u first=%u\r\n",
                   stats->logit_mismatch_count, first_logit_mismatch,
                   stats->prediction_mismatch_count, first_prediction_mismatch);
    }
    if (hw_fail != 0U) {
        xil_printf("PL HW failure: case=%u stage=%u detail=%u status=0x%08x\r\n",
                   hw_fail_case, hw_fail_stage, hw_fail_detail, hw_fail_status);
    }
    (void)first_logit_mismatch;
    (void)first_prediction_mismatch;
    (void)hw_fail_case;
    (void)hw_fail_stage;
    (void)hw_fail_detail;
    (void)hw_fail_status;
#endif
#if !PRINT_CLASS_FAIL_DETAILS
    (void)class_fail_case;
    (void)class_fail_label;
    (void)class_fail_prediction;
#endif

#if PRINT_DETAILED_TIMING
    xil_printf("\r\nRTL PL kernel timing\r\n");
    xil_printf("Clock Hz          : %u\r\n", TPU_PL_CLOCK_HZ);
    xil_printf("Total cycles      : %u\r\n", total_cycles);
    xil_printf("Avg cycles/image  : %u\r\n", avg_cycles);
    xil_printf("Min cycles/image  : %u\r\n", min_cycles);
    xil_printf("Max cycles/image  : %u\r\n", max_cycles);
    if (stats->cycle_counter_wrapped != 0U) {
        xil_printf("Counter source    : wait-time estimate; raw cycle reg avg=%u\r\n",
                   stats->raw_avg_cycles);
    }
    xil_printf("Accel time approx : %u ms\r\n", total_time_ms);
    print_u32_as_decimal_2("Accel FPS approx  : ", fps_x100);

    xil_printf("\r\nRTL PL end-to-end timing\r\n");
    xil_printf("Wall time         : %u ms\r\n", stats->wall_ms);
    print_u32_as_decimal_2("End-to-end FPS    : ", stats->fps_x100);

    xil_printf("\r\nRTL PL software timing breakdown\r\n");
    print_timing_region("Prepare input ptr : ", stats->prepare_ticks, stats->wall_ticks);
    print_timing_region("Control clear     : ", stats->clear_status_ticks, stats->wall_ticks);
    print_timing_region("Input UB write    : ", stats->input_write_ticks, stats->wall_ticks);
    print_timing_region("Start write       : ", stats->start_ticks, stats->wall_ticks);
    print_timing_region("Wait done         : ", stats->wait_done_ticks, stats->wall_ticks);
    print_timing_region("Output readback   : ", stats->output_read_ticks, stats->wall_ticks);
    print_timing_region("Argmax/check      : ", stats->postprocess_ticks, stats->wall_ticks);
#endif

    if ((hw_fail != 0U) || (stats->logit_mismatch_count != 0U) ||
        (stats->prediction_mismatch_count != 0U)) {
        return -1;
    }

    return 0;
}

static void print_benchmark_comparison(const benchmark_stats_t *cpu_stats,
                                       const benchmark_stats_t *pl_stats)
{
    u32 kernel_speedup_x100;
    u32 e2e_speedup_x100;

    kernel_speedup_x100 = speedup_x100_from_kernel_cycles(cpu_stats->wall_ticks,
                                                          pl_stats->total_cycles);
    e2e_speedup_x100 = speedup_x100_from_ticks(cpu_stats->wall_ticks,
                                               pl_stats->wall_ticks);

    xil_printf("\r\nCPU PS vs RTL PL benchmark\r\n");
    xil_printf("Cases              : %u\r\n", MNIST_REAL_CASE_COUNT);
    xil_printf("CPU accuracy       : %u/%u\r\n", cpu_stats->pass_count, MNIST_REAL_CASE_COUNT);
    xil_printf("PL accuracy        : %u/%u\r\n", pl_stats->pass_count, MNIST_REAL_CASE_COUNT);
    xil_printf("CPU total time     : %u ms\r\n", cpu_stats->wall_ms);
    xil_printf("PL kernel time     : %u ms\r\n", pl_stats->kernel_ms);
    xil_printf("PL end-to-end time : %u ms\r\n", pl_stats->wall_ms);
    if (pl_stats->cycle_counter_wrapped != 0U) {
        xil_printf("PL cycle source    : wait-time estimate; raw reg avg=%u\r\n",
                   pl_stats->raw_avg_cycles);
    }
    print_u32_as_decimal_2("CPU FPS            : ", cpu_stats->fps_x100);
    print_u32_as_decimal_2("PL kernel FPS      : ", pl_stats->kernel_fps_x100);
    print_u32_as_decimal_2("PL end-to-end FPS  : ", pl_stats->fps_x100);
    print_u32_as_decimal_2("Kernel speedup     : ", kernel_speedup_x100);
    print_u32_as_decimal_2("End-to-end speedup : ", e2e_speedup_x100);
}

int main(void)
{
    benchmark_stats_t cpu_stats;
    benchmark_stats_t pl_stats;

    xil_printf("\r\nTPU MNIST ZCU104 bare-metal demo\r\n");
    xil_printf("TPU_BASEADDR=0x%08x\r\n", TPU_BASEADDR);
    xil_printf("initial status=0x%08x\r\n", tpu_status());

#if RUN_STARTUP_SELF_TESTS
    if (run_ub_smoke_test() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    if (run_zero_image_inference() != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }
#endif

    if (run_cpu_mnist_inference(&cpu_stats) != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    if (run_real_mnist_inference(&pl_stats) != 0) {
        xil_printf("RESULT: FAIL\r\n");
        return 1;
    }

    print_benchmark_comparison(&cpu_stats, &pl_stats);

    xil_printf("RESULT: PASS\r\n");
    return 0;
}

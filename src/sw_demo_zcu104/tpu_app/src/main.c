#include "app_config.h"
#include "app_timer.h"
#include "compare.h"
#include "cpu_fast_model.h"
#include "golden_model.h"
#include "mnist_real_cases.h"
#include "report.h"
#include "rtl_runner.h"
#include "single_case_goldens.h"
#include "tpu_axi_lite.h"

#include "xil_printf.h"

typedef struct {
    u64 weight_load;
    u64 activation_fetch;
    u64 mxu_active;
    u64 mxu_drain;
    u64 accumulator;
    u64 vpu;
    u64 output_write;
    u64 controller_idle;
    u64 valid_mac_count;
    u64 issued_mac_count;
    u64 useful_mac_count;
    u64 exclusive_state_cycles;
} rtl_phase_sum_t;

typedef struct {
    u32 logit_pass;
    u32 class_pass;
    u32 prediction_pass;
    u64 total_ticks;
} cpu_batch_stats_t;

typedef struct {
    u32 logit_pass;
    u32 class_pass;
    u32 prediction_pass;
    u32 hw_fail;
    u64 total_wall_ticks;
    u64 input_write_ticks;
    u64 wait_ticks;
    u64 output_read_ticks;
    u64 total_cycles;
    u64 conv1_cycles;
    u64 pool1_cycles;
    u64 conv2_cycles;
    u64 pool2_cycles;
    u64 fc1_cycles;
    u64 fc2_cycles;
    rtl_phase_sum_t conv1_phase;
    rtl_phase_sum_t conv2_phase;
    rtl_phase_sum_t fc1_phase;
    u32 min_cycles;
    u32 max_cycles;
} rtl_batch_stats_t;

static golden_layers_t g_layers;

static u32 pl_cycles_to_ms(u64 cycles)
{
    return (u32)((cycles * 1000ULL) / (u64)APP_PL_CLOCK_HZ);
}

static u32 pl_fps_x100(u32 image_count, u64 cycles)
{
    if (cycles == 0ULL) {
        return 0U;
    }

    return (u32)((((u64)image_count * (u64)APP_PL_CLOCK_HZ * 100ULL) + (cycles / 2ULL)) /
                 cycles);
}

static u32 ratio_percent_x100(u64 numerator, u64 denominator)
{
    if (denominator == 0ULL) {
        return 0U;
    }

    return (u32)(((numerator * 10000ULL) + (denominator / 2ULL)) / denominator);
}

static void add_phase_sum(rtl_phase_sum_t *sum, const tpu_phase_cycles_t *phase)
{
    sum->weight_load += (u64)phase->weight_load;
    sum->activation_fetch += (u64)phase->activation_fetch;
    sum->mxu_active += (u64)phase->mxu_active;
    sum->mxu_drain += (u64)phase->mxu_drain;
    sum->accumulator += (u64)phase->accumulator;
    sum->vpu += (u64)phase->vpu;
    sum->output_write += (u64)phase->output_write;
    sum->controller_idle += (u64)phase->controller_idle;
    sum->valid_mac_count += (u64)phase->valid_mac_count;
    sum->issued_mac_count += (u64)phase->issued_mac_count;
    sum->useful_mac_count += (u64)phase->useful_mac_count;
    sum->exclusive_state_cycles += (u64)phase->exclusive_state_cycles;
}

static void print_percent_x100_value(u32 value_x100)
{
    u32 frac = value_x100 % 100U;

    xil_printf("%u.", value_x100 / 100U);
    if (frac < 10U) {
        xil_printf("0");
    }
    xil_printf("%u%%", frac);
}

static void print_compare_result(const char *name, compare_result_t result)
{
    if (result.mismatches == 0U) {
        xil_printf("  %s: PASS\r\n", name);
        return;
    }

    xil_printf("  %s: FAIL mismatches=%u first=%u got=%d expected=%d\r\n",
               name,
               result.mismatches,
               result.first_index,
               (int)result.actual_value,
               (int)result.expected_value);
}

static void print_layer_time(const char *name, u64 ticks)
{
    xil_printf("  ");
    xil_printf("%s", name);
    xil_printf(" timer_ticks=%u time=%u us\r\n",
               (u32)ticks,
               (u32)((ticks * 1000000ULL) / (u64)app_timer_ticks_per_second()));
}

static u32 run_single_case_layer_check(void)
{
    golden_profile_t profile;
    u32 fail_count = 0U;
    compare_result_t cmp;

    xil_printf("\r\nCPU golden layer check, case 0\r\n");
    golden_model_run_profile(mnist_real_inputs[0], &g_layers, &profile);

    cmp = compare_i32_vector(g_layers.conv1_acc, golden_layer0_conv_acc_i32, SINGLE_CASE_CONV1_COUNT);
    print_compare_result("Conv1 acc", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i8_vector(g_layers.conv1_out, golden_layer0_out_i8, SINGLE_CASE_CONV1_COUNT);
    print_compare_result("Conv1 out", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i32_vector(g_layers.conv2_acc, golden_layer1_conv_acc_i32, SINGLE_CASE_CONV2_COUNT);
    print_compare_result("Conv2 acc", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i8_vector(g_layers.conv2_out, golden_layer1_out_i8, SINGLE_CASE_CONV2_COUNT);
    print_compare_result("Conv2 out", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i32_vector(g_layers.fc1_acc, golden_layer2_fc_acc_i32, SINGLE_CASE_FC1_COUNT);
    print_compare_result("FC1 acc", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i8_vector(g_layers.fc1_out, golden_layer2_out_i8, SINGLE_CASE_FC1_COUNT);
    print_compare_result("FC1 out", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i32_vector(g_layers.fc2_acc, golden_layer3_fc_acc_i32, SINGLE_CASE_FC2_COUNT);
    print_compare_result("FC2 acc", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    cmp = compare_i8_vector(g_layers.logits, golden_final_logits_i8, SINGLE_CASE_FC2_COUNT);
    print_compare_result("FC2 logits", cmp);
    fail_count += (cmp.mismatches != 0U) ? 1U : 0U;

    xil_printf("  Pool1 checksum=%d Pool2 checksum=%d\r\n",
               (int)checksum_i8_vector(g_layers.pool1_out, GOLDEN_POOL1_OUT_COUNT),
               (int)checksum_i8_vector(g_layers.pool2_out, GOLDEN_POOL2_OUT_COUNT));

    xil_printf("CPU layer timing, case 0\r\n");
    print_layer_time("Conv1", profile.conv1_ticks);
    print_layer_time("Pool1", profile.pool1_ticks);
    print_layer_time("Conv2", profile.conv2_ticks);
    print_layer_time("Pool2", profile.pool2_ticks);
    print_layer_time("FC1", profile.fc1_ticks);
    print_layer_time("FC2", profile.fc2_ticks);
    print_layer_time("Total", profile.total_ticks);

    return fail_count;
}

static cpu_batch_stats_t run_cpu_batch(u32 count)
{
    cpu_batch_stats_t stats = {0U, 0U, 0U, 0ULL};
    u64 t0 = app_timer_ticks();

    for (u32 idx = 0U; idx < count; idx++) {
        s8 logits[TPU_LOGIT_COUNT];
        s8 predicted;
        compare_result_t cmp;

        cpu_fast_infer_i8(mnist_real_inputs[idx], logits);

        cmp = compare_i8_vector(logits, mnist_real_expected_logits[idx], TPU_LOGIT_COUNT);
        if (cmp.mismatches == 0U) {
            stats.logit_pass++;
        }

        predicted = compare_argmax_i8(logits, TPU_LOGIT_COUNT);
        if (predicted == mnist_real_labels[idx]) {
            stats.class_pass++;
        }
        if (predicted == mnist_real_expected_predictions[idx]) {
            stats.prediction_pass++;
        }
    }

    stats.total_ticks = app_timer_ticks() - t0;
    return stats;
}

static rtl_batch_stats_t run_rtl_batch(u32 count)
{
    rtl_batch_stats_t stats = {0};

    stats.min_cycles = 0xffffffffU;

    for (u32 idx = 0U; idx < count; idx++) {
        rtl_result_t result;
        s8 predicted;
        compare_result_t cmp;

        if (rtl_run_image(mnist_real_inputs[idx], &result) != 0) {
            stats.hw_fail++;
            xil_printf("  RTL HW FAIL case=%u status=0x%08x error=0x%08x\r\n",
                       idx,
                       result.status_reg,
                       result.error_reg);
            continue;
        }

        cmp = compare_i8_vector(result.logits, mnist_real_expected_logits[idx], TPU_LOGIT_COUNT);
        if (cmp.mismatches == 0U) {
            stats.logit_pass++;
        }

        predicted = compare_argmax_i8(result.logits, TPU_LOGIT_COUNT);
        if (predicted == mnist_real_labels[idx]) {
            stats.class_pass++;
        }
        if (predicted == mnist_real_expected_predictions[idx]) {
            stats.prediction_pass++;
        }

        stats.total_wall_ticks += result.wall_ticks;
        stats.input_write_ticks += result.input_write_ticks;
        stats.wait_ticks += result.wait_ticks;
        stats.output_read_ticks += result.output_read_ticks;
        stats.total_cycles += (u64)result.cycles;
        stats.conv1_cycles += (u64)result.layer_cycles.conv1;
        stats.pool1_cycles += (u64)result.layer_cycles.pool1;
        stats.conv2_cycles += (u64)result.layer_cycles.conv2;
        stats.pool2_cycles += (u64)result.layer_cycles.pool2;
        stats.fc1_cycles += (u64)result.layer_cycles.fc1;
        stats.fc2_cycles += (u64)result.layer_cycles.fc2;
        add_phase_sum(&stats.conv1_phase, &result.phase_profile.conv1);
        add_phase_sum(&stats.conv2_phase, &result.phase_profile.conv2);
        add_phase_sum(&stats.fc1_phase, &result.phase_profile.fc1);
        if (result.cycles < stats.min_cycles) {
            stats.min_cycles = result.cycles;
        }
        if (result.cycles > stats.max_cycles) {
            stats.max_cycles = result.cycles;
        }
    }

    if (stats.min_cycles == 0xffffffffU) {
        stats.min_cycles = 0U;
    }

    return stats;
}

static void print_cpu_batch(u32 count, cpu_batch_stats_t stats)
{
    xil_printf("CPU fast inference\r\n");
    report_percent("  logits match : ", stats.logit_pass, count);
    report_percent("  class label  : ", stats.class_pass, count);
    report_percent("  pred golden  : ", stats.prediction_pass, count);
    xil_printf("  total ticks  : %u\r\n", (u32)stats.total_ticks);
    xil_printf("  total time   : %u ms avg=%u us/img\r\n",
               app_timer_ms(stats.total_ticks),
               app_timer_us_per_item(stats.total_ticks, count));
    report_fixed2("  FPS          : ", app_timer_fps_x100(count, stats.total_ticks));
}

static void print_phase_batch(const char *name,
                              u32 completed,
                              u64 layer_cycles,
                              rtl_phase_sum_t phase)
{
    u32 avg_weight_load = 0U;
    u32 avg_activation_fetch = 0U;
    u32 avg_mxu_active = 0U;
    u32 avg_mxu_drain = 0U;
    u32 avg_accumulator = 0U;
    u32 avg_vpu = 0U;
    u32 avg_output_write = 0U;
    u32 avg_controller_idle = 0U;
    u32 avg_exclusive_state = 0U;
    u32 avg_issued_mac = 0U;
    u32 avg_useful_mac = 0U;
    u64 issued_mac_count = (phase.issued_mac_count != 0ULL) ? phase.issued_mac_count
                                                            : phase.valid_mac_count;

    if (completed != 0U) {
        avg_weight_load = (u32)(phase.weight_load / completed);
        avg_activation_fetch = (u32)(phase.activation_fetch / completed);
        avg_mxu_active = (u32)(phase.mxu_active / completed);
        avg_mxu_drain = (u32)(phase.mxu_drain / completed);
        avg_accumulator = (u32)(phase.accumulator / completed);
        avg_vpu = (u32)(phase.vpu / completed);
        avg_output_write = (u32)(phase.output_write / completed);
        avg_controller_idle = (u32)(phase.controller_idle / completed);
        avg_exclusive_state = (u32)(phase.exclusive_state_cycles / completed);
        avg_issued_mac = (u32)(issued_mac_count / completed);
        avg_useful_mac = (u32)(phase.useful_mac_count / completed);
    }

    xil_printf("  phase ");
    xil_printf("%s", name);
    xil_printf(": wgt=%u act_fetch=%u mxu_active=%u drain=%u acc=%u vpu=%u out=%u idle=%u\r\n",
               avg_weight_load,
               avg_activation_fetch,
               avg_mxu_active,
               avg_mxu_drain,
               avg_accumulator,
               avg_vpu,
               avg_output_write,
               avg_controller_idle);
    xil_printf("  ratio ");
    xil_printf("%s", name);
    xil_printf(": mxu_active=");
    print_percent_x100_value(ratio_percent_x100(phase.mxu_active, layer_cycles));
    xil_printf(" state_sum=");
    print_percent_x100_value(ratio_percent_x100(phase.exclusive_state_cycles, layer_cycles));
    xil_printf("\r\n");
    xil_printf("  PE util ");
    xil_printf("%s", name);
    xil_printf(": issued=");
    print_percent_x100_value(ratio_percent_x100(issued_mac_count, phase.mxu_active * 4ULL));
    xil_printf(" useful=");
    print_percent_x100_value(ratio_percent_x100(phase.useful_mac_count, phase.mxu_active * 4ULL));
    xil_printf(" useful/issued=");
    print_percent_x100_value(ratio_percent_x100(phase.useful_mac_count, issued_mac_count));
    xil_printf("\r\n");
    xil_printf("  MAC count ");
    xil_printf("%s", name);
    xil_printf(": issued_avg=%u useful_avg=%u issued_total=%u useful_total=%u state_avg=%u\r\n",
               avg_issued_mac,
               avg_useful_mac,
               (u32)issued_mac_count,
               (u32)phase.useful_mac_count,
               avg_exclusive_state);
}

static void print_rtl_batch(u32 count, rtl_batch_stats_t stats)
{
    u32 completed = count - stats.hw_fail;
    u32 avg_cycles = (completed == 0U) ? 0U : (u32)(stats.total_cycles / (u64)completed);

    xil_printf("RTL PL inference\r\n");
    report_percent("  logits match : ", stats.logit_pass, count);
    report_percent("  class label  : ", stats.class_pass, count);
    report_percent("  pred golden  : ", stats.prediction_pass, count);
    xil_printf("  hw failures  : %u\r\n", stats.hw_fail);
    xil_printf("  kernel cycles: total=%u avg=%u min=%u max=%u\r\n",
               (u32)stats.total_cycles,
               avg_cycles,
               stats.min_cycles,
               stats.max_cycles);
    xil_printf("  layer cycles : conv1=%u pool1=%u conv2=%u pool2=%u fc1=%u fc2=%u\r\n",
               (u32)((completed == 0U) ? 0ULL : (stats.conv1_cycles / completed)),
               (u32)((completed == 0U) ? 0ULL : (stats.pool1_cycles / completed)),
               (u32)((completed == 0U) ? 0ULL : (stats.conv2_cycles / completed)),
               (u32)((completed == 0U) ? 0ULL : (stats.pool2_cycles / completed)),
               (u32)((completed == 0U) ? 0ULL : (stats.fc1_cycles / completed)),
               (u32)((completed == 0U) ? 0ULL : (stats.fc2_cycles / completed)));
    print_phase_batch("conv1", completed, stats.conv1_cycles, stats.conv1_phase);
    print_phase_batch("conv2", completed, stats.conv2_cycles, stats.conv2_phase);
    print_phase_batch("fc1", completed, stats.fc1_cycles, stats.fc1_phase);
    xil_printf("  kernel time  : %u ms avg=%u us/img\r\n",
               pl_cycles_to_ms(stats.total_cycles),
               (completed == 0U) ? 0U :
               (u32)((stats.total_cycles * 1000000ULL) / ((u64)APP_PL_CLOCK_HZ * completed)));
    report_fixed2("  kernel FPS   : ", pl_fps_x100(completed, stats.total_cycles));
    xil_printf("  e2e time     : %u ms avg=%u us/img\r\n",
               app_timer_ms(stats.total_wall_ticks),
               app_timer_us_per_item(stats.total_wall_ticks, completed));
    report_fixed2("  e2e FPS      : ", app_timer_fps_x100(completed, stats.total_wall_ticks));
    xil_printf("  sw overhead  : write=%u ms wait=%u ms read=%u ms\r\n",
               app_timer_ms(stats.input_write_ticks),
               app_timer_ms(stats.wait_ticks),
               app_timer_ms(stats.output_read_ticks));
}

static u32 run_batch(u32 count)
{
    cpu_batch_stats_t cpu_stats;
    rtl_batch_stats_t rtl_stats;
    u32 fail_count = 0U;

    xil_printf("\r\nBATCH %u image(s)\r\n", count);
    report_line();

    cpu_stats = run_cpu_batch(count);
    print_cpu_batch(count, cpu_stats);

    rtl_stats = run_rtl_batch(count);
    print_rtl_batch(count, rtl_stats);

    if (cpu_stats.logit_pass != count) {
        fail_count++;
    }
    if (rtl_stats.logit_pass != count || rtl_stats.hw_fail != 0U) {
        fail_count++;
    }

    return fail_count;
}

int main(void)
{
    u32 fail_count = 0U;

    app_timer_init();

    xil_printf("\r\nTPU MNIST ZCU104 layer/debug app\r\n");
    xil_printf("TPU_BASEADDR=0x%08x\r\n", TPU_BASEADDR);
    xil_printf("cases embedded=%u start=%u\r\n", MNIST_REAL_CASE_COUNT, MNIST_REAL_CASE_START);
    xil_printf("timer_hz=%u pl_clock_hz=%u\r\n", app_timer_ticks_per_second(), APP_PL_CLOCK_HZ);
    xil_printf("CPU batch benchmark uses final-logit-only fast path.\r\n");
    xil_printf("RTL cycle counters: layer totals, phase counters, issued/useful MACs, state sums.\r\n");

    if (MNIST_REAL_CASE_COUNT < APP_BATCH_100) {
        xil_printf("FAIL: embedded cases must be at least %u\r\n", APP_BATCH_100);
        return -1;
    }

    fail_count += run_single_case_layer_check();
    fail_count += run_batch(APP_BATCH_1);
    fail_count += run_batch(APP_BATCH_10);
    fail_count += run_batch(APP_BATCH_100);

    if (fail_count == 0U) {
        xil_printf("\r\nRESULT: PASS\r\n");
        return 0;
    }

    xil_printf("\r\nRESULT: FAIL checks=%u\r\n", fail_count);
    return -1;
}

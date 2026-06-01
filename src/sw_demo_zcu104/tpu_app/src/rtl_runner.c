#include "rtl_runner.h"

#include "app_config.h"
#include "app_timer.h"

static int load_image(const s8 image[TPU_IMAGE_SIZE])
{
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {
        if (tpu_ub_write(0U, idx, image[idx]) != 0) {
            return -1;
        }
    }

    return 0;
}

static int read_logits(s8 logits[TPU_LOGIT_COUNT])
{
    for (u32 idx = 0U; idx < TPU_LOGIT_COUNT; idx++) {
        if (tpu_ub_read(0U, idx, &logits[idx]) != 0) {
            return -1;
        }
    }

    return 0;
}

int rtl_run_image(const s8 image[TPU_IMAGE_SIZE], rtl_result_t *result)
{
    u64 t0;
    u64 t1;
    u64 t2;
    u64 t3;
    u64 t4;
    u32 final_status = 0U;

    if (result == 0) {
        return -1;
    }

    result->status_code = -1;
    result->status_reg = 0U;
    result->error_reg = 0U;
    result->cycles = 0U;
    result->layer_cycles.conv1 = 0U;
    result->layer_cycles.pool1 = 0U;
    result->layer_cycles.conv2 = 0U;
    result->layer_cycles.pool2 = 0U;
    result->layer_cycles.fc1 = 0U;
    result->layer_cycles.fc2 = 0U;
    result->phase_profile.conv1 = (tpu_phase_cycles_t){0};
    result->phase_profile.conv2 = (tpu_phase_cycles_t){0};
    result->phase_profile.fc1 = (tpu_phase_cycles_t){0};
    result->wall_ticks = 0ULL;
    result->input_write_ticks = 0ULL;
    result->wait_ticks = 0ULL;
    result->output_read_ticks = 0ULL;

    tpu_clear_status();
    t0 = app_timer_ticks();
    if (load_image(image) != 0) {
        result->status_reg = tpu_status();
        result->error_reg = tpu_error();
        return -1;
    }
    t1 = app_timer_ticks();

    tpu_clear_status();
    tpu_write_reg(TPU_REG_CONTROL, TPU_CONTROL_START);
    if (tpu_wait_done(APP_RTL_TIMEOUT_POLLS, &final_status) != 0) {
        result->status_reg = final_status;
        result->error_reg = tpu_error();
        return -1;
    }
    t2 = app_timer_ticks();

    result->cycles = tpu_cycles();
    tpu_get_layer_cycles(&result->layer_cycles);
    tpu_get_phase_profile(&result->phase_profile);
    if (read_logits(result->logits) != 0) {
        result->status_reg = tpu_status();
        result->error_reg = tpu_error();
        return -1;
    }
    t3 = app_timer_ticks();

    t4 = t3;
    result->status_code = 0;
    result->status_reg = final_status;
    result->error_reg = tpu_error();
    result->input_write_ticks = t1 - t0;
    result->wait_ticks = t2 - t1;
    result->output_read_ticks = t3 - t2;
    result->wall_ticks = t4 - t0;
    return 0;
}

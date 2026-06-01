#include "golden_model.h"

#include "app_timer.h"
#include "cpu_model_params.h"

#define CONV1_W_BASE 0U
#define CONV2_W_BASE 72U
#define FC1_W_BASE   792U
#define FC2_W_BASE   4792U

#define CONV1_B_BASE 0U
#define CONV2_B_BASE 8U
#define FC1_B_BASE   18U
#define FC2_B_BASE   34U

static u32 conv1_idx(u32 c, u32 y, u32 x)
{
    return (c * 676U) + (y * 26U) + x;
}

static u32 pool1_idx(u32 c, u32 y, u32 x)
{
    return (c * 169U) + (y * 13U) + x;
}

static u32 conv2_idx(u32 c, u32 y, u32 x)
{
    return (c * 121U) + (y * 11U) + x;
}

static u32 pool2_idx(u32 c, u32 y, u32 x)
{
    return (c * 25U) + (y * 5U) + x;
}

static s32 round_shift_s64(s64 value, u8 shift)
{
    s64 offset;

    if (shift == 0U) {
        return (s32)value;
    }

    offset = ((s64)1) << (shift - 1U);
    if (value >= 0) {
        return (s32)((value + offset) >> shift);
    }
    return (s32)((value - offset) >> shift);
}

static s8 requant_i8(s32 acc, u32 channel, u32 bias_base, int relu)
{
    s64 value = (s64)acc + (s64)cpu_model_biases[bias_base + channel];
    s32 shifted;

    value *= (s64)cpu_model_requant_mult[bias_base + channel];
    shifted = round_shift_s64(value, cpu_model_requant_shift[bias_base + channel]);

    if (shifted > 127) {
        shifted = 127;
    } else if (shifted < -128) {
        shifted = -128;
    }

    if ((relu != 0) && (shifted < 0)) {
        shifted = 0;
    }

    return (s8)shifted;
}

static void conv1_layer(const s8 input[TPU_IMAGE_SIZE], golden_layers_t *layers)
{
    for (u32 oc = 0U; oc < 8U; oc++) {
        for (u32 oy = 0U; oy < 26U; oy++) {
            for (u32 ox = 0U; ox < 26U; ox++) {
                s32 acc = 0;
                u32 out_idx = conv1_idx(oc, oy, ox);

                for (u32 ky = 0U; ky < 3U; ky++) {
                    for (u32 kx = 0U; kx < 3U; kx++) {
                        u32 input_idx = ((oy + ky) * 28U) + (ox + kx);
                        u32 weight_idx = CONV1_W_BASE + (oc * 9U) + (ky * 3U) + kx;
                        acc += (s32)input[input_idx] * (s32)cpu_model_weights[weight_idx];
                    }
                }

                layers->conv1_acc[out_idx] = acc;
                layers->conv1_out[out_idx] = requant_i8(acc, oc, CONV1_B_BASE, 1);
            }
        }
    }
}

static void pool1_layer(golden_layers_t *layers)
{
    for (u32 c = 0U; c < 8U; c++) {
        for (u32 oy = 0U; oy < 13U; oy++) {
            for (u32 ox = 0U; ox < 13U; ox++) {
                s8 max_value = layers->conv1_out[conv1_idx(c, oy * 2U, ox * 2U)];
                s8 value = layers->conv1_out[conv1_idx(c, oy * 2U, (ox * 2U) + 1U)];

                if (value > max_value) {
                    max_value = value;
                }
                value = layers->conv1_out[conv1_idx(c, (oy * 2U) + 1U, ox * 2U)];
                if (value > max_value) {
                    max_value = value;
                }
                value = layers->conv1_out[conv1_idx(c, (oy * 2U) + 1U, (ox * 2U) + 1U)];
                if (value > max_value) {
                    max_value = value;
                }

                layers->pool1_out[pool1_idx(c, oy, ox)] = max_value;
            }
        }
    }
}

static void conv2_layer(golden_layers_t *layers)
{
    for (u32 oc = 0U; oc < 10U; oc++) {
        for (u32 oy = 0U; oy < 11U; oy++) {
            for (u32 ox = 0U; ox < 11U; ox++) {
                s32 acc = 0;
                u32 out_idx = conv2_idx(oc, oy, ox);

                for (u32 ic = 0U; ic < 8U; ic++) {
                    for (u32 ky = 0U; ky < 3U; ky++) {
                        for (u32 kx = 0U; kx < 3U; kx++) {
                            u32 weight_idx = CONV2_W_BASE + (oc * 72U) + (ic * 9U) +
                                             (ky * 3U) + kx;
                            acc += (s32)layers->pool1_out[pool1_idx(ic, oy + ky, ox + kx)] *
                                   (s32)cpu_model_weights[weight_idx];
                        }
                    }
                }

                layers->conv2_acc[out_idx] = acc;
                layers->conv2_out[out_idx] = requant_i8(acc, oc, CONV2_B_BASE, 1);
            }
        }
    }
}

static void pool2_layer(golden_layers_t *layers)
{
    for (u32 c = 0U; c < 10U; c++) {
        for (u32 oy = 0U; oy < 5U; oy++) {
            for (u32 ox = 0U; ox < 5U; ox++) {
                s8 max_value = layers->conv2_out[conv2_idx(c, oy * 2U, ox * 2U)];
                s8 value = layers->conv2_out[conv2_idx(c, oy * 2U, (ox * 2U) + 1U)];

                if (value > max_value) {
                    max_value = value;
                }
                value = layers->conv2_out[conv2_idx(c, (oy * 2U) + 1U, ox * 2U)];
                if (value > max_value) {
                    max_value = value;
                }
                value = layers->conv2_out[conv2_idx(c, (oy * 2U) + 1U, (ox * 2U) + 1U)];
                if (value > max_value) {
                    max_value = value;
                }

                layers->pool2_out[pool2_idx(c, oy, ox)] = max_value;
            }
        }
    }
}

static void fc1_layer(golden_layers_t *layers)
{
    for (u32 oc = 0U; oc < 16U; oc++) {
        s32 acc = 0;

        for (u32 input_idx = 0U; input_idx < GOLDEN_POOL2_OUT_COUNT; input_idx++) {
            u32 weight_idx = FC1_W_BASE + (input_idx * 16U) + oc;
            acc += (s32)layers->pool2_out[input_idx] * (s32)cpu_model_weights[weight_idx];
        }

        layers->fc1_acc[oc] = acc;
        layers->fc1_out[oc] = requant_i8(acc, oc, FC1_B_BASE, 1);
    }
}

static void fc2_layer(golden_layers_t *layers)
{
    for (u32 oc = 0U; oc < TPU_LOGIT_COUNT; oc++) {
        s32 acc = 0;

        for (u32 input_idx = 0U; input_idx < GOLDEN_FC1_OUT_COUNT; input_idx++) {
            u32 weight_idx = FC2_W_BASE + (input_idx * 10U) + oc;
            acc += (s32)layers->fc1_out[input_idx] * (s32)cpu_model_weights[weight_idx];
        }

        layers->fc2_acc[oc] = acc;
        layers->logits[oc] = requant_i8(acc, oc, FC2_B_BASE, 0);
    }
}

void golden_model_run_profile(const s8 input[TPU_IMAGE_SIZE],
                              golden_layers_t *layers,
                              golden_profile_t *profile)
{
    u64 t0 = app_timer_ticks();
    u64 t1;
    u64 t2;
    u64 t3;
    u64 t4;
    u64 t5;
    u64 t6;

    conv1_layer(input, layers);
    t1 = app_timer_ticks();
    pool1_layer(layers);
    t2 = app_timer_ticks();
    conv2_layer(layers);
    t3 = app_timer_ticks();
    pool2_layer(layers);
    t4 = app_timer_ticks();
    fc1_layer(layers);
    t5 = app_timer_ticks();
    fc2_layer(layers);
    t6 = app_timer_ticks();

    if (profile != 0) {
        profile->conv1_ticks = t1 - t0;
        profile->pool1_ticks = t2 - t1;
        profile->conv2_ticks = t3 - t2;
        profile->pool2_ticks = t4 - t3;
        profile->fc1_ticks = t5 - t4;
        profile->fc2_ticks = t6 - t5;
        profile->total_ticks = t6 - t0;
    }
}

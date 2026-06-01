#include "cpu_mnist_int8.h"

#include "cpu_model_params.h"

#define CONV1_W_BASE 0U
#define CONV2_W_BASE 72U
#define FC1_W_BASE   792U
#define FC2_W_BASE   4792U

#define CONV1_B_BASE 0U
#define CONV2_B_BASE 8U
#define FC1_B_BASE   18U
#define FC2_B_BASE   34U

static s32 conv1_acc[8][26][26];
static s8 conv1_out[8][26][26];
static s8 pool1_out[8][13][13];
static s32 conv2_acc[10][11][11];
static s8 conv2_out[10][11][11];
static s8 pool2_out[10][5][5];
static s8 fc1_out[16];

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

static void conv1_layer(const s8 input[TPU_IMAGE_SIZE])
{
    for (u32 oc = 0U; oc < 8U; oc++) {
        for (u32 oy = 0U; oy < 26U; oy++) {
            for (u32 ox = 0U; ox < 26U; ox++) {
                s32 acc = 0;
                for (u32 ky = 0U; ky < 3U; ky++) {
                    for (u32 kx = 0U; kx < 3U; kx++) {
                        u32 input_idx = ((oy + ky) * 28U) + (ox + kx);
                        u32 weight_idx = CONV1_W_BASE + (oc * 9U) + (ky * 3U) + kx;
                        acc += (s32)input[input_idx] * (s32)cpu_model_weights[weight_idx];
                    }
                }
                conv1_acc[oc][oy][ox] = acc;
                conv1_out[oc][oy][ox] = requant_i8(acc, oc, CONV1_B_BASE, 1);
            }
        }
    }
}

static void pool1_layer(void)
{
    for (u32 c = 0U; c < 8U; c++) {
        for (u32 oy = 0U; oy < 13U; oy++) {
            for (u32 ox = 0U; ox < 13U; ox++) {
                s8 max_value = conv1_out[c][oy * 2U][ox * 2U];
                s8 value = conv1_out[c][oy * 2U][(ox * 2U) + 1U];
                if (value > max_value) {
                    max_value = value;
                }
                value = conv1_out[c][(oy * 2U) + 1U][ox * 2U];
                if (value > max_value) {
                    max_value = value;
                }
                value = conv1_out[c][(oy * 2U) + 1U][(ox * 2U) + 1U];
                if (value > max_value) {
                    max_value = value;
                }
                pool1_out[c][oy][ox] = max_value;
            }
        }
    }
}

static void conv2_layer(void)
{
    for (u32 oc = 0U; oc < 10U; oc++) {
        for (u32 oy = 0U; oy < 11U; oy++) {
            for (u32 ox = 0U; ox < 11U; ox++) {
                s32 acc = 0;
                for (u32 ic = 0U; ic < 8U; ic++) {
                    for (u32 ky = 0U; ky < 3U; ky++) {
                        for (u32 kx = 0U; kx < 3U; kx++) {
                            u32 weight_idx = CONV2_W_BASE + (oc * 72U) + (ic * 9U) + (ky * 3U) + kx;
                            acc += (s32)pool1_out[ic][oy + ky][ox + kx] *
                                   (s32)cpu_model_weights[weight_idx];
                        }
                    }
                }
                conv2_acc[oc][oy][ox] = acc;
                conv2_out[oc][oy][ox] = requant_i8(acc, oc, CONV2_B_BASE, 1);
            }
        }
    }
}

static void pool2_layer(void)
{
    for (u32 c = 0U; c < 10U; c++) {
        for (u32 oy = 0U; oy < 5U; oy++) {
            for (u32 ox = 0U; ox < 5U; ox++) {
                s8 max_value = conv2_out[c][oy * 2U][ox * 2U];
                s8 value = conv2_out[c][oy * 2U][(ox * 2U) + 1U];
                if (value > max_value) {
                    max_value = value;
                }
                value = conv2_out[c][(oy * 2U) + 1U][ox * 2U];
                if (value > max_value) {
                    max_value = value;
                }
                value = conv2_out[c][(oy * 2U) + 1U][(ox * 2U) + 1U];
                if (value > max_value) {
                    max_value = value;
                }
                pool2_out[c][oy][ox] = max_value;
            }
        }
    }
}

static s8 pool2_flat(u32 idx)
{
    u32 channel = idx / 25U;
    u32 rem = idx % 25U;
    return pool2_out[channel][rem / 5U][rem % 5U];
}

static void fc1_layer(void)
{
    for (u32 oc = 0U; oc < 16U; oc++) {
        s32 acc = 0;
        for (u32 input_idx = 0U; input_idx < 250U; input_idx++) {
            u32 weight_idx = FC1_W_BASE + (input_idx * 16U) + oc;
            acc += (s32)pool2_flat(input_idx) * (s32)cpu_model_weights[weight_idx];
        }
        fc1_out[oc] = requant_i8(acc, oc, FC1_B_BASE, 1);
    }
}

static void fc2_layer(s8 logits[TPU_LOGIT_COUNT])
{
    for (u32 oc = 0U; oc < 10U; oc++) {
        s32 acc = 0;
        for (u32 input_idx = 0U; input_idx < 16U; input_idx++) {
            u32 weight_idx = FC2_W_BASE + (input_idx * 10U) + oc;
            acc += (s32)fc1_out[input_idx] * (s32)cpu_model_weights[weight_idx];
        }
        logits[oc] = requant_i8(acc, oc, FC2_B_BASE, 0);
    }
}

void cpu_mnist_infer_i8(const s8 input[TPU_IMAGE_SIZE], s8 logits[TPU_LOGIT_COUNT])
{
    conv1_layer(input);
    pool1_layer();
    conv2_layer();
    pool2_layer();
    fc1_layer();
    fc2_layer(logits);
}

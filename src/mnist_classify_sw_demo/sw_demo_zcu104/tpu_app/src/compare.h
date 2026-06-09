#ifndef COMPARE_H
#define COMPARE_H

#include "tpu_axi_lite.h"

typedef struct {
    u32 mismatches;
    u32 first_index;
    s32 actual_value;
    s32 expected_value;
} compare_result_t;

s8 compare_argmax_i8(const s8 *values, u32 count);
compare_result_t compare_i8_vector(const s8 *actual, const s8 *expected, u32 count);
compare_result_t compare_i32_vector(const s32 *actual, const s32 *expected, u32 count);
s32 checksum_i8_vector(const s8 *values, u32 count);
s32 checksum_i32_vector(const s32 *values, u32 count);

#endif

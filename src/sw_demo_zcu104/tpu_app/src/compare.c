#include "compare.h"

s8 compare_argmax_i8(const s8 *values, u32 count)
{
    s8 best_idx = 0;
    s8 best_value = values[0];

    for (u32 idx = 1U; idx < count; idx++) {
        if (values[idx] > best_value) {
            best_value = values[idx];
            best_idx = (s8)idx;
        }
    }

    return best_idx;
}

compare_result_t compare_i8_vector(const s8 *actual, const s8 *expected, u32 count)
{
    compare_result_t result = {0U, 0U, 0, 0};

    for (u32 idx = 0U; idx < count; idx++) {
        if (actual[idx] != expected[idx]) {
            if (result.mismatches == 0U) {
                result.first_index = idx;
                result.actual_value = (s32)actual[idx];
                result.expected_value = (s32)expected[idx];
            }
            result.mismatches++;
        }
    }

    return result;
}

compare_result_t compare_i32_vector(const s32 *actual, const s32 *expected, u32 count)
{
    compare_result_t result = {0U, 0U, 0, 0};

    for (u32 idx = 0U; idx < count; idx++) {
        if (actual[idx] != expected[idx]) {
            if (result.mismatches == 0U) {
                result.first_index = idx;
                result.actual_value = actual[idx];
                result.expected_value = expected[idx];
            }
            result.mismatches++;
        }
    }

    return result;
}

s32 checksum_i8_vector(const s8 *values, u32 count)
{
    s32 sum = 0;

    for (u32 idx = 0U; idx < count; idx++) {
        sum += (s32)values[idx];
    }

    return sum;
}

s32 checksum_i32_vector(const s32 *values, u32 count)
{
    s32 sum = 0;

    for (u32 idx = 0U; idx < count; idx++) {
        sum += values[idx];
    }

    return sum;
}

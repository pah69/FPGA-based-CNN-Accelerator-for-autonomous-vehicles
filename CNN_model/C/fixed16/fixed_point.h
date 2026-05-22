// ============================================
// fixed_point.h - Helper functions for Q3.12
// ============================================
#ifndef FIXED_POINT_H
#define FIXED_POINT_H

#include <stdint.h>
#include <math.h>

// 1 sign bit + 3 integer bits + 12 fractional bits = 16 bits
#define FRAC_BITS 12
#define FIXED_SCALE (1 << FRAC_BITS)  // 4096

// Convert float to fixed point
// Added roundf to ensure weights like 0.8586304 are mapped to the closest integer
inline int16_t float_to_fixed(float x) {
    return (int16_t)roundf(x * FIXED_SCALE);
}

// Convert fixed point to float 
inline float fixed_to_float(int16_t x) {
    return (float)x / FIXED_SCALE;
}

// ReLU activation for fixed point
inline int16_t fixed_relu(int16_t x) {
    return (x < 0) ? 0 : x;
}

// Multiplication helper (CRITICAL for Q-format)
// When you multiply two Q3.12 numbers, the result is Q6.24. 
// You must shift back to maintain the Q3.12 scale.
inline int16_t fixed_mul(int16_t a, int16_t b) {
    int32_t intermediate = (int32_t)a * (int32_t)b;
    return (int16_t)(intermediate >> FRAC_BITS);
}

#endif


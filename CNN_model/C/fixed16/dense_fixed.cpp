// ============================================
// Dense_Fixed.cpp - Fixed point dense layers
// ============================================
#include "fixed_point.h"
#include "dense_fixed.h"
#include <math.h>
#include <stdint.h>

void Dense_0_Fixed(int16_t input_Dense[250], int16_t output_Dense[16],
                   int16_t bias[16], int16_t weight[4000]) {
    
    int16_t out_Dense[16];
    
    DENSE0_OUTER: for (int i = 0; i < 16; i++) {
        int64_t sum = 0;
        
        DENSE0_INNER: for (int j = 0; j < 250; j++) {
            // Multiply Q3.12 * Q3.12 = Q6.24
            sum += (int32_t)input_Dense[j] * (int32_t)weight[j*16 + i];
        }
        
        // Scale back down (divide by 4096 using shift) to return to Q3.12
        sum = sum >> FRAC_BITS;
        
        // Add bias (already in Q3.12)
        out_Dense[i] = (int16_t)sum + bias[i];
    }
    
    // Apply ReLU activation
    DENSE0_RELU: for (int i = 0; i < 16; i++) {
        output_Dense[i] = fixed_relu(out_Dense[i]);
    }
}

void Dense_1_Fixed(int16_t input_Dense[16], int16_t &output_Dense0,
                   int16_t bias[10], int16_t weight[160]) {
    
    float logits[10];
    
    // Compute logits
    DENSE1_OUTER: for (int i = 0; i < 10; i++) {
        int64_t sum = 0;
        
        DENSE1_INNER: for (int j = 0; j < 16; j++) {
            sum += (int32_t)input_Dense[j] * (int32_t)weight[j*10 + i];
        }
        
        sum = sum >> FRAC_BITS;
        logits[i] = (int16_t)sum + bias[i];
    }
    
    // Find max index (argmax) 
    int maxindex = 0;
    float max_val = logits[0];
    
    ARGMAX: for (int i = 1; i < 10; i++) {
        if (logits[i] > max_val) {
            max_val = logits[i];
            maxindex = i;
        }
    }
    
    // Final Output: Cast the winning index to int16_t to match function signature
    output_Dense0 = (float)maxindex;
}
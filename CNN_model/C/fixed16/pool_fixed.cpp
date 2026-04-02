
// ============================================
// Pool_Fixed.cpp - Fixed point pooling
// ============================================
#include "fixed_point.h"
#include "pool_fixed.h"

void Max_Pool2D_0_Fixed(int16_t input_MaxPooling[5408], int16_t output_MaxPooling[1352]) {
    int PoolSize = 2;
    int stride = 2;
    
    for (int i = 0; i < 8; i++) {
        int index = 0;
        for (int z = 0; z < 13; z++) {
            for (int y = 0; y < 13; y++) {
                int16_t max_c = -32768;  // Use int16_t minimum
                
                for (int h = 0; h < PoolSize; h++) {
                    for (int w = 0; w < PoolSize; w++) {
                        int Pool_index = 26*26*i + 26*h + 26*stride*z + w + y*stride;
                        int16_t Pool_value = input_MaxPooling[Pool_index];
                        
                        if (Pool_value >= max_c) {
                            max_c = Pool_value;
                        }
                    }
                }
                
                output_MaxPooling[13*13*i + index] = max_c;
                index++;
            }
        }
    }
}

void Max_Pool2D_1_Fixed(int16_t input_MaxPooling[1210], int16_t output_MaxPooling[250]) {
    int PoolSize = 2;
    int stride = 2;
    
    for (int i = 0; i < 10; i++) {
        int index = 0;
        for (int z = 0; z < 5; z++) {
            for (int y = 0; y < 5; y++) {
                int16_t max_c = -32768;
                
                for (int h = 0; h < PoolSize; h++) {
                    for (int w = 0; w < PoolSize; w++) {
                        int Pool_index = 11*11*i + 11*h + 11*stride*z + w + y*stride;
                        int16_t Pool_value = input_MaxPooling[Pool_index];
                        
                        if (Pool_value >= max_c) {
                            max_c = Pool_value;
                        }
                    }
                }
                
                output_MaxPooling[5*5*i + index] = max_c;
                index++;
            }
        }
    }
}

// Flatten
void flatten0_Fixed(int16_t input_Flatten[250], int16_t output_Flatten[250]) {
    int hs = 0;
    for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
            for (int k = 0; k < 10; k++) {
                output_Flatten[hs] = input_Flatten[5*i + 5*5*k + j];
                hs++;
            }
        }
    }
}
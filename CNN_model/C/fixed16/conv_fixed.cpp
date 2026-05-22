// // ============================================
// // Conv_Fixed.cpp - Fixed point convolution
// // ============================================
// #include "fixed_point.h"
// #include "conv_fixed.h"
// void Conv2D_0_Fixed(int16_t Input_Conv[784], int16_t Output_Conv[5408],
//                     int16_t bias[8], int16_t kernel[72]) {
//     int stride = 1;
    
//     for (int n = 0; n < 8; n++) {
//         for (int x = 0; x < 26; x++) {
//             for (int y = 0; y < 26; y++) {
//                 int32_t sum = 0;  // 32-bit accumulator
                
//                 for (int k = 0; k < 1; k++) {
//                     for (int i = 0; i < 3; i++) {
//                         for (int j = 0; j < 3; j++) {
//                             int kernelIdx = 1*3*3*n + 3*3*k + 3*i + j;
//                             int inputIdx = 28*28*k + 28*(i+x*stride) + j+y*stride;
                            
//                             sum += (int32_t)kernel[kernelIdx] * (int32_t)Input_Conv[inputIdx];
//                         }
//                     }
//                 }
                
//                 // Scale and add bias
//                 sum = sum >> FRAC_BITS;
//                 int16_t result = (int16_t)sum + bias[n];
                
//                 // Apply ReLU
//                 Output_Conv[26*26*n + 26*x + y] = fixed_relu(result);
//             }
//         }
//     }
// }

// void Conv2D_1_Fixed(int16_t Input_Conv[1352], int16_t Output_Conv[1210],
//                     int16_t bias[10], int16_t kernel[720]) {
//     int stride = 1;
    
//     for (int n = 0; n < 10; n++) {
//         for (int x = 0; x < 11; x++) {
//             for (int y = 0; y < 11; y++) {
//                 int32_t sum = 0;
                
//                 for (int k = 0; k < 8; k++) {
//                     for (int i = 0; i < 3; i++) {
//                         for (int j = 0; j < 3; j++) {
//                             int kernelIdx = 8*3*3*n + 3*3*k + 3*i + j;
//                             int inputIdx = 13*13*k + 13*(i+x*stride) + j+y*stride;
                            
//                             sum += (int32_t)kernel[kernelIdx] * (int32_t)Input_Conv[inputIdx];
//                         }
//                     }
//                 }
                
//                 sum = sum >> FRAC_BITS;
//                 int16_t result = (int16_t)sum + bias[n];
                
//                 Output_Conv[11*11*n + 11*x + y] = fixed_relu(result);
//             }
//         }
//     }
// }

// ============================================
// Conv_Fixed.cpp - Fixed point convolution
// ============================================

#include "fixed_point.h"
#include "conv_fixed.h"

void Conv2D_0_Fixed(int16_t Input_Conv[784], int16_t Output_Conv[5408],
                    int16_t bias[8], int16_t kernel[72]) {
    int stride = 1;
    
    // Partition arrays for parallel access
    // #pragma HLS ARRAY_PARTITION variable=Input_Conv cyclic factor=4 dim=1
    // #pragma HLS ARRAY_PARTITION variable=kernel cyclic factor=9 dim=1
    // #pragma HLS ARRAY_PARTITION variable=bias complete dim=1
    // #pragma HLS ARRAY_PARTITION variable=Output_Conv cyclic factor=4 dim=1
    
    // Only pipeline the innermost productive loop
    CONV1_OUTER: for (int n = 0; n < 8; n++) {
        CONV1_X: for (int x = 0; x < 26; x++) {
            CONV1_Y: for (int y = 0; y < 26; y++) {
                // #pragma HLS PIPELINE II=1
                
                int64_t sum = 0;
                
                CONV1_K: for (int k = 0; k < 1; k++) {
                    CONV1_I: for (int i = 0; i < 3; i++) {
                        CONV1_J: for (int j = 0; j < 3; j++) {
                            // #pragma HLS UNROLL
                            // OR use: #pragma HLS UNROLL factor=9 for full unroll of 3x3
                            
                            int kernelIdx = 1*3*3*n + 3*3*k + 3*i + j;
                            int inputIdx = 28*28*k + 28*(i+x*stride) + j+y*stride;
                            
                            sum += (int32_t)kernel[kernelIdx] * (int32_t)Input_Conv[inputIdx];
                        }
                    }
                }
                
                // Scale and add bias
                sum = sum >> FRAC_BITS;
                int16_t result = (int16_t)sum + bias[n];
                
                // Apply ReLU
                Output_Conv[26*26*n + 26*x + y] = fixed_relu(result);
            }
        }
    }
}

void Conv2D_1_Fixed(int16_t Input_Conv[1352], int16_t Output_Conv[1210],
                    int16_t bias[10], int16_t kernel[720]) {
    int stride = 1;
    
    // Partition arrays - be more conservative
    // #pragma HLS ARRAY_PARTITION variable=Input_Conv cyclic factor=4 dim=1
    // #pragma HLS ARRAY_PARTITION variable=kernel cyclic factor=8 dim=1
    // #pragma HLS ARRAY_PARTITION variable=bias complete dim=1
    // #pragma HLS ARRAY_PARTITION variable=Output_Conv cyclic factor=4 dim=1
    
    CONV2_OUTER: for (int n = 0; n < 10; n++) {
        CONV2_X: for (int x = 0; x < 11; x++) {
            CONV2_Y: for (int y = 0; y < 11; y++) {
                // #pragma HLS PIPELINE II=1
                
                int64_t sum = 0;
                
                CONV2_K: for (int k = 0; k < 8; k++) {
                    CONV2_I: for (int i = 0; i < 3; i++) {
                        CONV2_J: for (int j = 0; j < 3; j++) {
                            // #pragma HLS UNROLL factor=3
                            // Unroll the 3x3 kernel computation
                            
                            int kernelIdx = 8*3*3*n + 3*3*k + 3*i + j;
                            int inputIdx = 13*13*k + 13*(i+x*stride) + j+y*stride;
                            
                            sum += (int32_t)kernel[kernelIdx] * (int32_t)Input_Conv[inputIdx];
                        }
                    }
                }
                
                sum = sum >> FRAC_BITS;
                int16_t result = (int16_t)sum + bias[n];
                
                Output_Conv[11*11*n + 11*x + y] = fixed_relu(result);
            }
        }
    }
}
#include "fixed_point.h"
#include "cnn_fixed.h"
#include "conv_fixed.h"
#include "dense_fixed.h"
#include "pool_fixed.h"
#include <algorithm>
#include <stdint.h>

// Constants for maintainability
#define INPUT_SIZE 784
#define WEIGHTS_SIZE 4996
#define CONV1_SIZE 5408
#define POOL1_SIZE 1352
#define CONV2_SIZE 1210
#define POOL2_SIZE 250
#define FLATTEN_SIZE 250
#define FC1_SIZE 16

void CNN_Fixed(int16_t InModel[INPUT_SIZE],     
               int16_t &OutModel0,        
               int16_t Weights[WEIGHTS_SIZE]) {  
                
    // Local intermediate buffers with conservative partitioning
    int16_t conv1[CONV1_SIZE];
    int16_t max_pooling2d[POOL1_SIZE];
    int16_t conv2[CONV2_SIZE];
    int16_t max_pooling2d_1[POOL2_SIZE];
    int16_t flatten[FLATTEN_SIZE];
    int16_t fc1[FC1_SIZE];
    
    // #pragma HLS ARRAY_PARTITION variable=conv1 cyclic factor=2 dim=1
    // #pragma HLS ARRAY_PARTITION variable=max_pooling2d cyclic factor=2 dim=1
    // #pragma HLS ARRAY_PARTITION variable=conv2 cyclic factor=2 dim=1
    // #pragma HLS ARRAY_PARTITION variable=max_pooling2d_1 cyclic factor=2 dim=1
    // #pragma HLS ARRAY_PARTITION variable=fc1 complete dim=1
    
    // AXI Master interfaces with burst optimizations
    // #pragma HLS INTERFACE m_axi port=InModel depth=784 offset=slave bundle=gmem0
    // #pragma HLS INTERFACE m_axi port=Weights depth=4996 offset=slave bundle=gmem1
    
    // // AXI-Lite for control
    // #pragma HLS INTERFACE s_axilite port=InModel bundle=control
    // #pragma HLS INTERFACE s_axilite port=Weights bundle=control
    // #pragma HLS INTERFACE s_axilite port=OutModel0 bundle=control
    // #pragma HLS INTERFACE s_axilite port=return bundle=control


    Conv2D_0_Fixed(InModel, conv1, &Weights[72], &Weights[0]);
    Max_Pool2D_0_Fixed(conv1, max_pooling2d);
    Conv2D_1_Fixed(max_pooling2d, conv2, &Weights[800], &Weights[80]);
    Max_Pool2D_1_Fixed(conv2, max_pooling2d_1);
    flatten0_Fixed(max_pooling2d_1, flatten);
    Dense_0_Fixed(flatten, fc1, &Weights[4810], &Weights[810]);
    Dense_1_Fixed(fc1, OutModel0, &Weights[4986], &Weights[4826]);
}
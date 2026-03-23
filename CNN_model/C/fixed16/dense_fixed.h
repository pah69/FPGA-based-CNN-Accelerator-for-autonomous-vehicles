#include "fixed_point.h"
#include <stdint.h>

void Dense_0_Fixed(
    int16_t input_Dense[250], 
    int16_t output_Dense[16],               
    int16_t bias[16], 
    int16_t weight[4000]);

void Dense_1_Fixed(
    int16_t input_Dense[16], 
    int16_t &output_Dense0, 
    int16_t bias[10], 
    int16_t weight[160]) ;
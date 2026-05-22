#ifndef POOL_FIXED_H
#define POOL_FIXED_H
#include "fixed_point.h"

void Max_Pool2D_0_Fixed(int16_t input_MaxPooling[5408], int16_t output_MaxPooling[1352]) ;
void Max_Pool2D_1_Fixed(int16_t input_MaxPooling[1210], int16_t output_MaxPooling[250]);
void flatten0_Fixed(int16_t input_Flatten[250], int16_t output_Flatten[250]) ;
#endif // POOL_FIXED
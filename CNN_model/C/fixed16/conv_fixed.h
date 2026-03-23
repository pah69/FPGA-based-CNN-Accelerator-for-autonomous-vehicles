#include "fixed_point.h"

void Conv2D_0_Fixed(
    int16_t Input_Conv[784], 
    int16_t Output_Conv[5408],
    int16_t bias[8], 
    int16_t kernel[72]) ;

void Conv2D_1_Fixed(
    int16_t Input_Conv[1352], 
    int16_t Output_Conv[1210],
    int16_t bias[10], 
    int16_t kernel[720]); 

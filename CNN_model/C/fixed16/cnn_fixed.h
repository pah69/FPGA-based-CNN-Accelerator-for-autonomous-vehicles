#ifndef CNN_FIXED_H
#define CNN_FIXED_H


#include "fixed_point.h"
#include <stdint.h>

// void CNN_Fixed(int16_t InModel[784], int16_t &OutModel0, int16_t Weights[4996]) ;
void CNN_Fixed(int16_t InModel[784],
               int16_t &OutModel0,
               int16_t Weights[4996]) ;
#endif // CNN_H
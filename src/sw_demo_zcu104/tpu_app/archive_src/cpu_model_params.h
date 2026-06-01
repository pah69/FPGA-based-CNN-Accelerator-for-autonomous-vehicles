#ifndef CPU_MODEL_PARAMS_H
#define CPU_MODEL_PARAMS_H

#include "xil_types.h"

#define CPU_MODEL_WEIGHT_COUNT 4952U
#define CPU_MODEL_BIAS_COUNT 44U

extern const s8 cpu_model_weights[CPU_MODEL_WEIGHT_COUNT];
extern const s32 cpu_model_biases[CPU_MODEL_BIAS_COUNT];
extern const s32 cpu_model_requant_mult[CPU_MODEL_BIAS_COUNT];
extern const u8 cpu_model_requant_shift[CPU_MODEL_BIAS_COUNT];

#endif

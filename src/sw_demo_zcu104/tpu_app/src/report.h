#ifndef REPORT_H
#define REPORT_H

#include "xil_types.h"

void report_fixed2(const char *label, u32 value_x100);
void report_percent(const char *label, u32 pass_count, u32 total_count);
void report_line(void);

#endif

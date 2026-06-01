#include "report.h"

#include "xil_printf.h"

void report_fixed2(const char *label, u32 value_x100)
{
    u32 frac = value_x100 % 100U;

    xil_printf("%s%u.", label, value_x100 / 100U);
    if (frac < 10U) {
        xil_printf("0");
    }
    xil_printf("%u\r\n", frac);
}

void report_percent(const char *label, u32 pass_count, u32 total_count)
{
    u32 pct_x100 = 0U;

    if (total_count != 0U) {
        pct_x100 = (u32)((((u64)pass_count * 10000ULL) + ((u64)total_count / 2ULL)) /
                         (u64)total_count);
    }

    xil_printf("%s%u/%u (", label, pass_count, total_count);
    xil_printf("%u.", pct_x100 / 100U);
    if ((pct_x100 % 100U) < 10U) {
        xil_printf("0");
    }
    xil_printf("%u%%)\r\n", pct_x100 % 100U);
}

void report_line(void)
{
    xil_printf("----------------------------------------\r\n");
}

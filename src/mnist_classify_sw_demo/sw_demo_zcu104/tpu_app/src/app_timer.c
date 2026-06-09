#include "app_timer.h"

#include "xiltimer.h"

void app_timer_init(void)
{
}

u64 app_timer_ticks(void)
{
    XTime now;

    XTime_GetTime(&now);
    return (u64)now;
}

u32 app_timer_ticks_per_second(void)
{
    return (u32)COUNTS_PER_SECOND;
}

u32 app_timer_ms(u64 ticks)
{
    return (u32)((ticks * 1000ULL) / (u64)COUNTS_PER_SECOND);
}

u32 app_timer_us_per_item(u64 ticks, u32 item_count)
{
    if (item_count == 0U) {
        return 0U;
    }

    return (u32)(((ticks * 1000000ULL) / (u64)COUNTS_PER_SECOND) / (u64)item_count);
}

u32 app_timer_fps_x100(u32 item_count, u64 ticks)
{
    if (ticks == 0ULL) {
        return 0U;
    }

    return (u32)((((u64)item_count * (u64)COUNTS_PER_SECOND * 100ULL) + (ticks / 2ULL)) / ticks);
}

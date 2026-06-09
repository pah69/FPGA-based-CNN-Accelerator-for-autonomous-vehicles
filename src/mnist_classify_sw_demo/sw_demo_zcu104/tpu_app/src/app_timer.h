#ifndef APP_TIMER_H
#define APP_TIMER_H

#include "xil_types.h"

void app_timer_init(void);
u64 app_timer_ticks(void);
u32 app_timer_ticks_per_second(void);
u32 app_timer_ms(u64 ticks);
u32 app_timer_us_per_item(u64 ticks, u32 item_count);
u32 app_timer_fps_x100(u32 item_count, u64 ticks);

#endif

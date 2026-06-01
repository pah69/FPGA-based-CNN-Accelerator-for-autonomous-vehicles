#ifndef TPU_AXI_LITE_H
#define TPU_AXI_LITE_H

#include "xil_types.h"
#include "xparameters.h"

#ifdef XPAR_TPU_MNIST_0_BASEADDR
#define TPU_BASEADDR XPAR_TPU_MNIST_0_BASEADDR
#else
#define TPU_BASEADDR 0xA0000000U
#endif

#define TPU_REG_CONTROL     0x00U
#define TPU_REG_STATUS      0x04U
#define TPU_REG_ERROR       0x08U
#define TPU_REG_CYCLES      0x0CU
#define TPU_REG_DEBUG0      0x10U
#define TPU_REG_DEBUG1      0x14U
#define TPU_REG_DEBUG2      0x18U
#define TPU_REG_DEBUG3      0x1CU
#define TPU_REG_UB_ADDR     0x20U
#define TPU_REG_UB_WDATA    0x24U
#define TPU_REG_UB_RDATA    0x28U
#define TPU_REG_UB_CONTROL  0x2CU

#define TPU_CONTROL_START       0x00000001U
#define TPU_CONTROL_CLR_OVF     0x00000002U
#define TPU_CONTROL_CLR_STATUS  0x00000004U

#define TPU_STATUS_DONE         0x00000001U
#define TPU_STATUS_BUSY         0x00000002U
#define TPU_STATUS_ERROR        0x00000004U
#define TPU_STATUS_OVERFLOW     0x00000008U
#define TPU_STATUS_UB_RD_VALID  0x00000010U
#define TPU_STATUS_CMD_ERROR    0x00000020U

#define TPU_UB_BANK_SHIFT       31U
#define TPU_UB_ADDR_MASK        0x00001FFFU
#define TPU_UB_CONTROL_WRITE    0x00000001U
#define TPU_UB_CONTROL_READ     0x00000002U

#define TPU_IMAGE_SIZE          784U
#define TPU_LOGIT_COUNT         10U

u32 tpu_read_reg(u32 offset);
void tpu_write_reg(u32 offset, u32 value);

void tpu_clear_status(void);
u32 tpu_status(void);
u32 tpu_error(void);
u32 tpu_cycles(void);

int tpu_ub_write(u32 bank, u32 addr, s8 value);
int tpu_ub_read(u32 bank, u32 addr, s8 *value);
int tpu_wait_done(u32 timeout_polls, u32 *final_status);

#endif

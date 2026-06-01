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
#define TPU_REG_CONV1_CYCLES 0x30U
#define TPU_REG_POOL1_CYCLES 0x34U
#define TPU_REG_CONV2_CYCLES 0x38U
#define TPU_REG_POOL2_CYCLES 0x3CU
#define TPU_REG_FC1_CYCLES   0x40U
#define TPU_REG_FC2_CYCLES   0x44U
#define TPU_REG_CONV1_WEIGHT_LOAD_CYCLES      0x48U
#define TPU_REG_CONV1_ACTIVATION_FETCH_CYCLES 0x4CU
#define TPU_REG_CONV1_MXU_ACTIVE_CYCLES       0x50U
#define TPU_REG_CONV1_MXU_DRAIN_CYCLES        0x54U
#define TPU_REG_CONV1_ACCUMULATOR_CYCLES      0x58U
#define TPU_REG_CONV1_VPU_CYCLES              0x5CU
#define TPU_REG_CONV1_OUTPUT_WRITE_CYCLES     0x60U
#define TPU_REG_CONV1_CONTROLLER_IDLE_CYCLES  0x64U
#define TPU_REG_CONV1_VALID_MAC_COUNT         0x68U
#define TPU_REG_CONV2_WEIGHT_LOAD_CYCLES      0x6CU
#define TPU_REG_CONV2_ACTIVATION_FETCH_CYCLES 0x70U
#define TPU_REG_CONV2_MXU_ACTIVE_CYCLES       0x74U
#define TPU_REG_CONV2_MXU_DRAIN_CYCLES        0x78U
#define TPU_REG_CONV2_ACCUMULATOR_CYCLES      0x7CU
#define TPU_REG_CONV2_VPU_CYCLES              0x80U
#define TPU_REG_CONV2_OUTPUT_WRITE_CYCLES     0x84U
#define TPU_REG_CONV2_CONTROLLER_IDLE_CYCLES  0x88U
#define TPU_REG_CONV2_VALID_MAC_COUNT         0x8CU
#define TPU_REG_FC1_WEIGHT_LOAD_CYCLES        0x90U
#define TPU_REG_FC1_ACTIVATION_FETCH_CYCLES   0x94U
#define TPU_REG_FC1_MXU_ACTIVE_CYCLES         0x98U
#define TPU_REG_FC1_MXU_DRAIN_CYCLES          0x9CU
#define TPU_REG_FC1_ACCUMULATOR_CYCLES        0xA0U
#define TPU_REG_FC1_VPU_CYCLES                0xA4U
#define TPU_REG_FC1_OUTPUT_WRITE_CYCLES       0xA8U
#define TPU_REG_FC1_CONTROLLER_IDLE_CYCLES    0xACU
#define TPU_REG_FC1_VALID_MAC_COUNT           0xB0U
#define TPU_REG_CONV1_ISSUED_MAC_COUNT        0xB4U
#define TPU_REG_CONV1_USEFUL_MAC_COUNT        0xB8U
#define TPU_REG_CONV1_EXCLUSIVE_STATE_CYCLES  0xBCU
#define TPU_REG_CONV2_ISSUED_MAC_COUNT        0xC0U
#define TPU_REG_CONV2_USEFUL_MAC_COUNT        0xC4U
#define TPU_REG_CONV2_EXCLUSIVE_STATE_CYCLES  0xC8U
#define TPU_REG_FC1_ISSUED_MAC_COUNT          0xCCU
#define TPU_REG_FC1_USEFUL_MAC_COUNT          0xD0U
#define TPU_REG_FC1_EXCLUSIVE_STATE_CYCLES    0xD4U

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

typedef struct {
    u32 conv1;
    u32 pool1;
    u32 conv2;
    u32 pool2;
    u32 fc1;
    u32 fc2;
} tpu_layer_cycles_t;

typedef struct {
    u32 weight_load;
    u32 activation_fetch;
    u32 mxu_active;
    u32 mxu_drain;
    u32 accumulator;
    u32 vpu;
    u32 output_write;
    u32 controller_idle;
    u32 valid_mac_count;
    u32 issued_mac_count;
    u32 useful_mac_count;
    u32 exclusive_state_cycles;
} tpu_phase_cycles_t;

typedef struct {
    tpu_phase_cycles_t conv1;
    tpu_phase_cycles_t conv2;
    tpu_phase_cycles_t fc1;
} tpu_phase_profile_t;

u32 tpu_read_reg(u32 offset);
void tpu_write_reg(u32 offset, u32 value);

void tpu_clear_status(void);
u32 tpu_status(void);
u32 tpu_error(void);
u32 tpu_cycles(void);
void tpu_get_layer_cycles(tpu_layer_cycles_t *cycles);
void tpu_get_phase_profile(tpu_phase_profile_t *profile);

int tpu_ub_write(u32 bank, u32 addr, s8 value);
int tpu_ub_read(u32 bank, u32 addr, s8 *value);
int tpu_wait_done(u32 timeout_polls, u32 *final_status);

#endif

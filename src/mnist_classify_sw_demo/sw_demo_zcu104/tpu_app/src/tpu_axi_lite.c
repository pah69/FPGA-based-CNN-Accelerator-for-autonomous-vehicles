#include "tpu_axi_lite.h"

#include "xil_io.h"

#define TPU_UB_TIMEOUT_POLLS 1000000U

u32 tpu_read_reg(u32 offset)
{
    return Xil_In32(TPU_BASEADDR + offset);
}

void tpu_write_reg(u32 offset, u32 value)
{
    Xil_Out32(TPU_BASEADDR + offset, value);
}

void tpu_clear_status(void)
{
    tpu_write_reg(TPU_REG_CONTROL, TPU_CONTROL_CLR_STATUS | TPU_CONTROL_CLR_OVF);
}

u32 tpu_status(void)
{
    return tpu_read_reg(TPU_REG_STATUS);
}

u32 tpu_error(void)
{
    return tpu_read_reg(TPU_REG_ERROR);
}

u32 tpu_cycles(void)
{
    return tpu_read_reg(TPU_REG_CYCLES);
}

void tpu_get_layer_cycles(tpu_layer_cycles_t *cycles)
{
    if (cycles == 0) {
        return;
    }

    cycles->conv1 = tpu_read_reg(TPU_REG_CONV1_CYCLES);
    cycles->pool1 = tpu_read_reg(TPU_REG_POOL1_CYCLES);
    cycles->conv2 = tpu_read_reg(TPU_REG_CONV2_CYCLES);
    cycles->pool2 = tpu_read_reg(TPU_REG_POOL2_CYCLES);
    cycles->fc1 = tpu_read_reg(TPU_REG_FC1_CYCLES);
    cycles->fc2 = tpu_read_reg(TPU_REG_FC2_CYCLES);
}

static void read_phase_counters(tpu_phase_cycles_t *phase,
                                u32 weight_load_reg,
                                u32 activation_fetch_reg,
                                u32 mxu_active_reg,
                                u32 mxu_drain_reg,
                                u32 accumulator_reg,
                                u32 vpu_reg,
                                u32 output_write_reg,
                                u32 controller_idle_reg,
                                u32 valid_mac_count_reg,
                                u32 issued_mac_count_reg,
                                u32 useful_mac_count_reg,
                                u32 exclusive_state_cycles_reg)
{
    phase->weight_load = tpu_read_reg(weight_load_reg);
    phase->activation_fetch = tpu_read_reg(activation_fetch_reg);
    phase->mxu_active = tpu_read_reg(mxu_active_reg);
    phase->mxu_drain = tpu_read_reg(mxu_drain_reg);
    phase->accumulator = tpu_read_reg(accumulator_reg);
    phase->vpu = tpu_read_reg(vpu_reg);
    phase->output_write = tpu_read_reg(output_write_reg);
    phase->controller_idle = tpu_read_reg(controller_idle_reg);
    phase->valid_mac_count = tpu_read_reg(valid_mac_count_reg);
    phase->issued_mac_count = tpu_read_reg(issued_mac_count_reg);
    phase->useful_mac_count = tpu_read_reg(useful_mac_count_reg);
    phase->exclusive_state_cycles = tpu_read_reg(exclusive_state_cycles_reg);
}

void tpu_get_phase_profile(tpu_phase_profile_t *profile)
{
    if (profile == 0) {
        return;
    }

    read_phase_counters(&profile->conv1,
                        TPU_REG_CONV1_WEIGHT_LOAD_CYCLES,
                        TPU_REG_CONV1_ACTIVATION_FETCH_CYCLES,
                        TPU_REG_CONV1_MXU_ACTIVE_CYCLES,
                        TPU_REG_CONV1_MXU_DRAIN_CYCLES,
                        TPU_REG_CONV1_ACCUMULATOR_CYCLES,
                        TPU_REG_CONV1_VPU_CYCLES,
                        TPU_REG_CONV1_OUTPUT_WRITE_CYCLES,
                        TPU_REG_CONV1_CONTROLLER_IDLE_CYCLES,
                        TPU_REG_CONV1_VALID_MAC_COUNT,
                        TPU_REG_CONV1_ISSUED_MAC_COUNT,
                        TPU_REG_CONV1_USEFUL_MAC_COUNT,
                        TPU_REG_CONV1_EXCLUSIVE_STATE_CYCLES);
    read_phase_counters(&profile->conv2,
                        TPU_REG_CONV2_WEIGHT_LOAD_CYCLES,
                        TPU_REG_CONV2_ACTIVATION_FETCH_CYCLES,
                        TPU_REG_CONV2_MXU_ACTIVE_CYCLES,
                        TPU_REG_CONV2_MXU_DRAIN_CYCLES,
                        TPU_REG_CONV2_ACCUMULATOR_CYCLES,
                        TPU_REG_CONV2_VPU_CYCLES,
                        TPU_REG_CONV2_OUTPUT_WRITE_CYCLES,
                        TPU_REG_CONV2_CONTROLLER_IDLE_CYCLES,
                        TPU_REG_CONV2_VALID_MAC_COUNT,
                        TPU_REG_CONV2_ISSUED_MAC_COUNT,
                        TPU_REG_CONV2_USEFUL_MAC_COUNT,
                        TPU_REG_CONV2_EXCLUSIVE_STATE_CYCLES);
    read_phase_counters(&profile->fc1,
                        TPU_REG_FC1_WEIGHT_LOAD_CYCLES,
                        TPU_REG_FC1_ACTIVATION_FETCH_CYCLES,
                        TPU_REG_FC1_MXU_ACTIVE_CYCLES,
                        TPU_REG_FC1_MXU_DRAIN_CYCLES,
                        TPU_REG_FC1_ACCUMULATOR_CYCLES,
                        TPU_REG_FC1_VPU_CYCLES,
                        TPU_REG_FC1_OUTPUT_WRITE_CYCLES,
                        TPU_REG_FC1_CONTROLLER_IDLE_CYCLES,
                        TPU_REG_FC1_VALID_MAC_COUNT,
                        TPU_REG_FC1_ISSUED_MAC_COUNT,
                        TPU_REG_FC1_USEFUL_MAC_COUNT,
                        TPU_REG_FC1_EXCLUSIVE_STATE_CYCLES);
}

int tpu_ub_write(u32 bank, u32 addr, s8 value)
{
    u32 packed_addr = ((bank & 1U) << TPU_UB_BANK_SHIFT) | (addr & TPU_UB_ADDR_MASK);

    tpu_write_reg(TPU_REG_UB_ADDR, packed_addr);
    tpu_write_reg(TPU_REG_UB_WDATA, (u32)((u8)value));
    tpu_write_reg(TPU_REG_UB_CONTROL, TPU_UB_CONTROL_WRITE);

    if ((tpu_status() & TPU_STATUS_CMD_ERROR) != 0U) {
        return -1;
    }

    return 0;
}

int tpu_ub_read(u32 bank, u32 addr, s8 *value)
{
    u32 packed_addr = ((bank & 1U) << TPU_UB_BANK_SHIFT) | (addr & TPU_UB_ADDR_MASK);
    u32 timeout = TPU_UB_TIMEOUT_POLLS;

    if (value == 0) {
        return -1;
    }

    tpu_write_reg(TPU_REG_UB_ADDR, packed_addr);
    tpu_write_reg(TPU_REG_UB_CONTROL, TPU_UB_CONTROL_READ);

    while (timeout != 0U) {
        if ((tpu_status() & TPU_STATUS_UB_RD_VALID) != 0U) {
            *value = (s8)(u8)(tpu_read_reg(TPU_REG_UB_RDATA) & 0xFFU);
            return 0;
        }
        timeout--;
    }

    return -1;
}

int tpu_wait_done(u32 timeout_polls, u32 *final_status)
{
    u32 status = 0U;

    while (timeout_polls != 0U) {
        status = tpu_status();

        if ((status & (TPU_STATUS_ERROR | TPU_STATUS_CMD_ERROR)) != 0U) {
            if (final_status != 0) {
                *final_status = status;
            }
            return -1;
        }

        if ((status & TPU_STATUS_DONE) != 0U) {
            if (final_status != 0) {
                *final_status = status;
            }
            return 0;
        }

        timeout_polls--;
    }

    if (final_status != 0) {
        *final_status = status;
    }
    return -1;
}

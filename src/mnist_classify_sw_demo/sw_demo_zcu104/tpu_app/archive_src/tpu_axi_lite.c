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

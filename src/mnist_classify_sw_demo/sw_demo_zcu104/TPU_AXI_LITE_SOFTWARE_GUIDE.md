# TPU AXI-Lite Software Guide

This guide describes the bare-metal software sequence for `tpu_top_axi_lite`.

## Register Map

Base address should match Vivado Address Editor, normally:

```c
#define TPU_BASEADDR 0xA0000000U
```

Offsets:

```c
#define TPU_REG_CONTROL     0x00U
#define TPU_REG_STATUS      0x04U
#define TPU_REG_ERROR       0x08U
#define TPU_REG_CYCLES      0x0cU
#define TPU_REG_DEBUG0      0x10U
#define TPU_REG_DEBUG1      0x14U
#define TPU_REG_DEBUG2      0x18U
#define TPU_REG_DEBUG3      0x1cU
#define TPU_REG_UB_ADDR     0x20U
#define TPU_REG_UB_WDATA    0x24U
#define TPU_REG_UB_RDATA    0x28U
#define TPU_REG_UB_CONTROL  0x2cU
```

## Control Register

`TPU_REG_CONTROL` write bits:

```text
bit 0: start TPU inference
bit 1: clear overflow flags
bit 2: clear sticky done, command error, and UB read-valid
```

Typical use:

```c
TPU_WRITE(TPU_REG_CONTROL, 0x4); // clear sticky status
TPU_WRITE(TPU_REG_CONTROL, 0x1); // start inference
```

## Status Register

`TPU_REG_STATUS` read bits:

```text
bit 0: done_sticky
bit 1: busy
bit 2: error
bit 3: overflow
bit 4: UB read valid
bit 5: command error
bits 10:8: top stage
bit 16: raw done pulse/status
```

Polling condition:

```c
while ((TPU_READ(TPU_REG_STATUS) & 0x1U) == 0U) {
    /* wait */
}
```

Also check error bits:

```c
u32 status = TPU_READ(TPU_REG_STATUS);
if (status & ((1U << 2) | (1U << 5))) {
    u32 err = TPU_READ(TPU_REG_ERROR);
}
```

## Unified Buffer Access

The software accesses the internal unified buffer indirectly through address, data, and command registers.

`TPU_REG_UB_ADDR` format:

```text
bit 31: bank select
bits 12:0: byte address inside selected bank
```

Current bank usage in the full schedule:

```text
bank 0: input image and selected intermediate tensors
bank 1: selected intermediate tensors and final output logits
```

### Write One Signed INT8 Value

```c
static void tpu_ub_write(u32 bank, u32 addr, s8 value)
{
    TPU_WRITE(TPU_REG_UB_ADDR, ((bank & 1U) << 31) | (addr & 0x1FFFU));
    TPU_WRITE(TPU_REG_UB_WDATA, (u32)((u8)value));
    TPU_WRITE(TPU_REG_UB_CONTROL, 0x1U);
}
```

### Read One Signed INT8 Value

```c
static s8 tpu_ub_read(u32 bank, u32 addr)
{
    TPU_WRITE(TPU_REG_UB_ADDR, ((bank & 1U) << 31) | (addr & 0x1FFFU));
    TPU_WRITE(TPU_REG_UB_CONTROL, 0x2U);

    while ((TPU_READ(TPU_REG_STATUS) & (1U << 4)) == 0U) {
        /* wait for UB read valid */
    }

    return (s8)(TPU_READ(TPU_REG_UB_RDATA) & 0xFFU);
}
```

## Smoke Test Sequence

Run this before full inference:

```text
1. Clear status.
2. Write bank0[0] = 0x12.
3. Read bank0[0].
4. Check value equals 0x12.
5. Write bank1[10] = -5.
6. Read bank1[10].
7. Check value equals -5.
```

This proves:

- PS-to-PL AXI-Lite writes work.
- PL-to-PS AXI-Lite reads work.
- TPU unified buffer host access works.
- Base address and reset are correct.

## Single-Image Inference Sequence

1. Clear status:

```c
TPU_WRITE(TPU_REG_CONTROL, 0x4U);
```

2. Write signed INT8 image data to bank 0:

```c
for (u32 i = 0; i < 784; i++) {
    tpu_ub_write(0, i, image_i8[i]);
}
```

3. Start inference:

```c
TPU_WRITE(TPU_REG_CONTROL, 0x1U);
```

4. Poll done:

```c
while ((TPU_READ(TPU_REG_STATUS) & 0x1U) == 0U) {
    /* optional timeout counter */
}
```

5. Read cycle count:

```c
u32 cycles = TPU_READ(TPU_REG_CYCLES) & 0xFFFFU;
```

6. Read final logits from bank 0 addresses `0..9`:

```c
s8 logits[10];
for (u32 i = 0; i < 10; i++) {
    logits[i] = tpu_ub_read(0, i);
}
```

The expected FC2 logits are ten signed INT8 values. For the first exported test image used in RTL simulation, the known logits were:

```text
{-11, -30, 22, 23, -40, -26, -113, 87, 9, 13}
```

The current RTL top writes final FC2 output logits to unified-buffer bank 0 at addresses `0..9` after the full `Conv1 -> Pool1 -> Conv2 -> Pool2 -> FC1 -> FC2` schedule.

## Recommended Software Test Levels

```text
Level 0: STATUS read returns stable value
Level 1: UB write/read one byte
Level 2: UB write/read multiple signed bytes
Level 3: one MNIST image, compare all 10 logits
Level 4: 10 MNIST images
Level 5: 100+ MNIST images
```

Do not start with thousands of images. First prove exact register and buffer behavior on one image.

## Minimal MMIO Helpers

For standalone Vitis:

```c
#include "xil_io.h"
#include "xil_types.h"

#define TPU_BASEADDR 0xA0000000U

#define TPU_WRITE(offset, value) Xil_Out32(TPU_BASEADDR + (offset), (u32)(value))
#define TPU_READ(offset)        Xil_In32(TPU_BASEADDR + (offset))
```

Use the generated `xparameters.h` base-address macro instead of `0xA0000000U` if available.

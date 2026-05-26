# Zybo Z7 TPU Software Demo

This workspace targets Zybo Z7-10 / Zynq-7000 with a standalone Cortex-A9 application.

## Current Layout

```text
sw_demo_zyboz7/
  platform/
    hw/tpu_zyboz7.xsa
    export/platform/platform.xpfm
    zynq_fsbl/
  app_component/
    src/main.c
    src/tpu_axi_lite.c
    src/tpu_axi_lite.h
```

## Hardware Assumptions

- Board: Zybo Z7-10
- Processor: Zynq-7000 `ps7_cortexa9_0`
- OS/domain: standalone bare-metal
- TPU control path: AXI4-Lite through PS `M_AXI_GP0`
- TPU clock: PS `FCLK_CLK0`, currently recommended at 25 MHz for timing-clean bring-up
- DMA/AXI-Stream: not used
- TPU base address from generated BSP:

```c
XPAR_TPU_ZYBO_0_BASEADDR = 0x40000000
```

## App Behavior

The current app performs:

```text
1. AXI-Lite / unified-buffer smoke test
2. zero-image inference
3. final logit comparison against {-4,3,2,-3,-4,1,-2,3,0,-5}
```

Expected UART end state:

```text
PASS: UB smoke
PASS: zero-image inference
RESULT: PASS
```

If the UB smoke test fails, check the BD address map, reset, and base address first.

If UB smoke passes but inference fails, check ROM `.mem` initialization in the packaged IP and final-logit readback from bank 0 addresses `0..9`.


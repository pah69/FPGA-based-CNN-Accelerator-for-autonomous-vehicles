# ZCU104 TPU Software Demo

This folder is the Vitis-side workspace for running the MNIST TPU bitstream on the ZCU104 processing system.

## Current Layout

```text
sw_demo/
  platform/
    hw/tpu_mnist.xsa
    hw/tpi_mnist.bit
    export/platform/platform.xpfm
    zynqmp_fsbl/
  tpu_app/
    src/
      CMakeLists.txt
      lscript.ld
      README.txt
```

`platform/` is the hardware platform generated from the exported Vivado XSA. It targets `psu_cortexa53_0` with the standalone BSP.

`tpu_app/` is the bare-metal application that should write MNIST input pixels into the TPU unified buffer, start the accelerator, poll completion, and read final logits back through AXI-Lite.

Current application sources:

```text
tpu_app/src/main.c
tpu_app/src/tpu_axi_lite.c
tpu_app/src/tpu_axi_lite.h
```

The first app performs:

```text
1. AXI-Lite/UB smoke test
2. zero-image inference
3. final-logit comparison against {-4,3,2,-3,-4,1,-2,3,0,-5}
```

## Hardware Assumptions

- Board: ZCU104
- Processor: Zynq UltraScale+ MPSoC A53 core 0
- OS/domain: standalone bare-metal
- TPU control path: AXI4-Lite
- TPU data movement for bring-up: AXI4-Lite register writes/reads
- DMA/AXI-Stream: not used in this bring-up flow
- TPU base address: normally `0xA0000000`, but confirm in Vivado Address Editor or generated `xparameters.h`.

## Recommended Bring-Up Order

1. Confirm Vivado implementation passes timing.
2. Confirm all four ROM `.mem` files load without `$readmemh` warnings.
3. Generate bitstream.
4. Export hardware from Vivado with bitstream included.
5. Update or recreate the Vitis platform from the new XSA.
6. Build the standalone application.
7. Program FPGA and run the app from Vitis.
8. First test AXI-Lite register access and unified-buffer readback.
9. Run the built-in zero-image inference test.
10. Add one real MNIST image case.
11. Then scale to 10, 100, and more images.

## Documents

- [ZCU104_VITIS_APPLICATION_STEPS.md](ZCU104_VITIS_APPLICATION_STEPS.md): step-by-step Vitis application creation flow.
- [TPU_AXI_LITE_SOFTWARE_GUIDE.md](TPU_AXI_LITE_SOFTWARE_GUIDE.md): register map, driver sequence, and software test plan.

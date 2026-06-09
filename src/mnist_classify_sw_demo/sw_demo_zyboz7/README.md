# Zybo Z7 TPU Software Demo

This workspace targets Zybo Z7-10 / Zynq-7000 with a standalone Cortex-A9 app that drives the TPU through AXI4-Lite.

## Layout

```text
sw_demo_zyboz7/
  app/src/
    main.c
    tpu_axi_lite.c/.h
    mnist_cases.c/.h
    mnist_real_cases.c/.h
  tools/make_sw_demo_cases.py
  zybo_platform/
```

## Hardware Assumptions

- Board: Zybo Z7-10
- Domain: standalone bare-metal on `ps7_cortexa9_1`
- Control path: AXI4-Lite through PS `M_AXI_GP0`
- DMA/AXI-Stream: not used
- TPU base address from the generated BSP: `XPAR_TPU_ZYBO_0_BASEADDR = 0x40000000`
- Final logits are read from unified-buffer bank 0 addresses `0..9`

## App Behavior

The app runs:

1. AXI-Lite / unified-buffer smoke test
2. Fake MNIST cases generated in C:
   - `fake_zero_image`
   - `fake_impulse_center_127`
   - `fake_checker_pm32`
3. Real MNIST cases embedded from `CNN_model/python/mnist_classification/18_05/e2e_cases`

Each inference loads 784 signed INT8 pixels into UB bank 0, starts the TPU, waits for done, reads 10 signed INT8 logits, and compares them against the integer golden logits from the export flow.

Expected UART end state:

```text
PASS: UB smoke
PASS: case[0] fake_zero_image ...
...
SUMMARY: pass=13 fail=0 total=13
RESULT: PASS
```

## Regenerate Real Cases

The checked-in app source embeds a bounded case set so the bare-metal ELF stays small. To refresh it from your existing real MNIST golden files:

```bash
cd src/sw_demo_zyboz7
python3 tools/make_sw_demo_cases.py --case-start 0 --case-count 10
```

Use `-DTPU_CASE_LIMIT=N` in `UserConfig.cmake` if you want a shorter board bring-up run.

If UB smoke fails, check the BD address map, reset, and base address first. If UB smoke passes but inference fails, check packaged ROM `.mem` initialization and the final-logit readback path.

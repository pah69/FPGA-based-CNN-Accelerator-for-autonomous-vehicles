# ZCU104 Vitis Application Steps

This runbook recreates the standalone software flow for the packaged TPU IP on ZCU104.

## 1. Export Hardware From Vivado

After block design validation, synthesis, implementation, and bitstream generation:

1. Open Vivado.
2. Select **File -> Export -> Export Hardware**.
3. Enable **Include bitstream**.
4. Export the XSA.

Expected hardware artifact:

```text
platform/hw/tpu_mnist.xsa
```

The XSA must include the block design with:

```text
Zynq UltraScale+ PS -> AXI SmartConnect -> tpu_top_axi_lite wrapper/IP
```

Before moving to Vitis, check the Vivado synthesis log for no ROM init errors:

```text
small_cnn_sym_weights_i8.mem
small_cnn_sym_biases_i32.mem
small_cnn_sym_requant_mult_i32.mem
small_cnn_sym_requant_shift_u6.mem
```

## 2. Create Or Update Platform

In Vitis Unified IDE:

1. Open workspace:

```text
src/sw_demo/
```

2. Create a platform component if it does not exist:

```text
Name: platform
Hardware design: platform/hw/tpu_mnist.xsa
OS: standalone
Processor: psu_cortexa53_0
Architecture: 64-bit
Domain: standalone_psu_cortexa53_0
```

3. Build the platform.

Expected exported platform:

```text
platform/export/platform/platform.xpfm
```

If the Vivado XSA changes, update the platform hardware specification and rebuild the platform before rebuilding the app.

## 3. Create Application

Create a new embedded application component:

```text
Name: tpu_app
Platform: platform/export/platform/platform.xpfm
Domain: standalone_psu_cortexa53_0
Template: Empty Application
```

The current application folder is:

```text
tpu_app/src/
```

Add application sources there, for example:

```text
tpu_app/src/main.c
tpu_app/src/tpu_axi_lite.h
tpu_app/src/tpu_axi_lite.c
tpu_app/src/mnist_cases.h
```

The generated `CMakeLists.txt` already collects C files from `tpu_app/src/`, so new `.c` files placed there should be included automatically.

The current checked-in app already includes:

```text
tpu_app/src/main.c
tpu_app/src/tpu_axi_lite.h
tpu_app/src/tpu_axi_lite.c
```

It runs a unified-buffer smoke test and one zero-image inference test.

## 4. Confirm Base Address

Check one of these before writing the driver:

- Vivado Address Editor
- Vitis generated `xparameters.h`
- `platform/hw/sdt/pl.dtsi`

Expected base address from the current design:

```c
#define TPU_BASEADDR 0xA0000000U
```

If Vitis generated an `XPAR_*_BASEADDR` macro for the TPU IP, prefer that macro instead of hard-coding the address.

## 5. Build Application

Build order:

1. Build `platform`.
2. Build `tpu_app`.

Expected output:

```text
tpu_app/build/tpu_app.elf
```

If the app still builds only `dummy.c`, add `main.c` under `tpu_app/src/`.

If the command-line build fails because the bundled Vitis CMake cannot load `libssl.so.10`, build from the Vitis IDE or fix the host library/runtime path for the Vitis 2025.2 CMake binary.

## 6. Run On ZCU104

Connect:

- JTAG USB
- UART terminal
- ZCU104 power

In Vitis:

1. Program FPGA with the bitstream from the platform.
2. Launch the standalone application on `psu_cortexa53_0`.
3. Watch UART output.

Recommended first UART output:

```text
TPU AXI-Lite smoke test
status=...
UB write/read PASS
single image logits: ...
```

## 7. Debug If Bring-Up Fails

If AXI reads return all zeros:

- Confirm the TPU IP is present in the block design.
- Confirm the AXI address range is assigned under the PS master aperture.
- Confirm software uses the same base address as Address Editor.
- Confirm `S_AXI_ACLK` and `S_AXI_ARESETN` are connected.

If register read/write works but inference output is wrong:

- Recheck `$readmemh` warnings in synthesis.
- Confirm input image quantization is signed INT8.
- Confirm image bytes are written to UB bank 0 addresses `0..783`.
- Confirm final logits are read from the expected output bank/address range.

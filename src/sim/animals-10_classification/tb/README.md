# Animals-10 Conv1 Bring-Up Bench

This bench locks the first RTL contract against the Python INT8 export:

```text
input  : CHW 3x64x64 signed INT8
weight : OIHW 32x3x3x3 signed INT8, output-channel-major
acc    : signed INT32
bias   : signed INT32 per output channel
requant: signed INT32 multiplier plus signed 8-bit shift per output channel
output : CHW 32x64x64 signed INT8 after clamp and ReLU
```

Run from this directory:

```bash
make test_conv1_case0
```

The behavioral contract bench recomputes Conv1 inside the testbench. The DUT
bench loads the same files into `animals10_conv1_direct` and compares the RTL
output stream:

```bash
make test_conv1_dut_case0
```

Compile the 4x4 systolic core without running a simulation:

```bash
make compile_sa_core
```

The default export directory is:

```text
../../../../CNN_model/python/animals-10_classification/custom_cnn/int8_export
```

Override if needed:

```bash
make test_conv1_case0 EXPORT_DIR=/absolute/path/to/int8_export CASE_INDEX=0
```

The bench compares against:

```text
debug_case0/conv1_acc_i32.hex
debug_case0/conv1_out_i8.hex
```

`animals10_conv1_direct` is a correctness-first RTL reference block, not the
accelerator compute heart. The Animals-10 accelerator starts from the
parameterized `animals10_systolic_array` with `SIZE=4`; the direct block keeps
the address and arithmetic contract stable while the tiled/systolic Conv engine
is introduced.

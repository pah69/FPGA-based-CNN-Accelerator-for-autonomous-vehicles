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

The first systolic datapath bench loads the same files into
`animals10_conv1_systolic_4x4`, which maps Conv1 onto the SIZE=4 array as
seven 4-row K tiles and four output channels per group. The V1 path uses
`animals10_systolic_array_4x4`, an explicit PE-by-PE 4x4 array. Each PE has
active/shadow stationary weights; a tile is loaded into shadow weights, then
`weight_switch_i` makes the tile active before activation streaming starts.
After the first K tile, the Conv engines preload the next tile into shadow
weights during the current tile drain and switch at the drain boundary. This
keeps the MNIST-style shadow-weight behavior while avoiding a standalone
load/switch bubble on every K tile.

```bash
make test_conv1_systolic_case0
```

After Conv1 passes, validate Conv2 as a standalone systolic layer. This bench
uses `debug_case0/conv1_out_i8.hex` as its input feature map, loads only the
Conv2 slice of the exported model weights/params, and compares against
`debug_case0/conv2_*`:

```bash
make test_conv2_systolic_case0
```

Conv2 has 32 input channels, so its standalone systolic test is much longer
than Conv1. With the shadow-preload schedule, expected counters are:

```text
Conv1 cycles ~= 2064384, tiles = 229376, outputs = 131072
Conv2 cycles ~= 19103744, tiles = 2359296, outputs = 131072
```

After the standalone Conv1 and Conv2 paths pass, validate the first fused V1
sequence:

```bash
make test_conv1_conv2_pool1_case0
```

This bench loads the first input image, Conv1+Conv2 weights/params, runs
`animals10_conv1_conv2_pool1_systolic_4x4`, and compares the Pool1 stream
against:

```text
debug_case0/pool1_out_i8.hex
```

Expected layer counters should keep the standalone Conv counters and add one
Pool1 output per 2x2 pooled element:

```text
Conv1 outputs = 131072
Conv2 outputs = 131072
Pool1 outputs = 32768
```

The next standalone layer checks validate the second feature-map stage before
building the fused Conv3+Conv4+Pool2 wrapper:

```bash
make test_conv3_systolic_case0
make test_conv4_systolic_case0
```

Conv3 consumes `debug_case0/pool1_out_i8.hex`; Conv4 consumes
`debug_case0/conv3_out_i8.hex`. Expected counters are:

```text
Conv3 cycles ~= 9551872,  tiles = 1179648, outputs = 65536
Conv4 cycles ~= 18989056, tiles = 2359296, outputs = 65536
```

After Conv3 and Conv4 pass, validate the second fused V1 sequence:

```bash
make test_conv3_conv4_pool2_case0
```

This bench loads `debug_case0/pool1_out_i8.hex`, Conv3+Conv4 weights/params,
runs `animals10_conv3_conv4_pool2_systolic_4x4`, and compares the Pool2 stream
against:

```text
debug_case0/pool2_out_i8.hex
```

Expected layer counters:

```text
Conv3 outputs = 65536
Conv4 outputs = 65536
Pool2 outputs = 16384
```

The final standalone convolution checks validate the third feature-map stage
before building Conv5+Conv6+Pool3:

```bash
make test_conv5_systolic_case0
make test_conv6_systolic_case0
```

Conv5 consumes `debug_case0/pool2_out_i8.hex`; Conv6 consumes
`debug_case0/conv5_out_i8.hex`. Expected counters are:

```text
Conv5 cycles ~= 9494528,  tiles = 1179648, outputs = 32768
Conv6 cycles ~= 18931712, tiles = 2359296, outputs = 32768
```

After Conv5 and Conv6 pass, validate the final fused convolution sequence:

```bash
make test_conv5_conv6_pool3_case0
```

This bench loads `debug_case0/pool2_out_i8.hex`, Conv5+Conv6 weights/params,
runs `animals10_conv5_conv6_pool3_systolic_4x4`, and compares the Pool3 stream
against:

```text
debug_case0/pool3_out_i8.hex
```

Expected layer counters:

```text
Conv5 outputs = 32768
Conv6 outputs = 32768
Pool3 outputs = 8192
```

After Pool3 passes, validate the classifier tail one block at a time:

```bash
make test_gap_case0
make test_fc1_case0
make test_fc2_case0
```

GAP consumes `debug_case0/pool3_out_i8.hex` and compares against
`debug_case0/gap_out_i8.hex`. FC1 consumes `debug_case0/gap_out_i8.hex`;
FC2 consumes `debug_case0/fc1_out_i8.hex`. The FC benches load their slices
from the shared exported weight, bias, multiplier, and shift files, then compare
against the Python INT8 accumulator and output debug files:

```text
debug_case0/fc1_acc_i32.hex
debug_case0/fc1_out_i8.hex
debug_case0/fc2_acc_i32.hex
debug_case0/fc2_out_i8.hex
```

Expected tail counters:

```text
GAP outputs = 128
FC1 outputs = 128
FC2 outputs = 10
```

After the standalone tail blocks pass, validate the fused classifier tail:

```bash
make test_gap_fc1_fc2_case0
```

This bench loads `debug_case0/pool3_out_i8.hex`, the FC1+FC2 slices from the
shared exported weight/parameter files, runs `animals10_gap_fc1_fc2_i8`, and
compares the final FC2 stream against:

```text
debug_case0/fc2_acc_i32.hex
debug_case0/fc2_out_i8.hex
```

Expected fused-tail counters:

```text
GAP outputs = 128
FC1 outputs = 128
FC2 outputs = 10
Final outputs = 10
```

After the classifier tail passes, validate the complete final stage from Pool2
to final logits:

```bash
make test_conv5_conv6_pool3_gap_fc1_fc2_case0
```

This bench loads `debug_case0/pool2_out_i8.hex`, the contiguous Conv5 through
FC2 slices from the shared exported weight/parameter files, runs
`animals10_conv5_conv6_pool3_gap_fc1_fc2_i8`, and compares the final FC2 stream
against:

```text
debug_case0/fc2_acc_i32.hex
debug_case0/fc2_out_i8.hex
```

Expected final-stage counters:

```text
Conv5 outputs = 32768
Conv6 outputs = 32768
Pool3 outputs = 8192
GAP outputs = 128
FC1 outputs = 128
FC2 outputs = 10
Final outputs = 10
```

After the final stage passes, validate the complete case-0 network from RGB
input to final logits:

```bash
make test_full_network_case0
```

This bench loads `debug_case0/layer_00_input_i8.hex`, all exported
weights/params, runs `animals10_full_network_i8`, and compares against:

```text
debug_case0/fc2_acc_i32.hex
debug_case0/final_logits_i8.hex
```

Expected full-network counters should preserve the previously validated
per-layer output counts and produce ten final logits:

```text
Pool1 outputs = 32768
Pool2 outputs = 16384
Pool3 outputs = 8192
GAP outputs = 128
FC1 outputs = 128
FC2 outputs = 10
Final outputs = 10
```

After case 0 passes, validate the balanced 10-case export:

```bash
make test_full_network_10cases
```

This bench loads `animals10_test_inputs_i8.hex`, `animals10_test_logits_i8.hex`,
and `animals10_test_labels.hex`. It loads model weights/params once, then runs
the full-network DUT once per exported case and compares each final logit vector
against the Python INT8 export. For a shorter smoke run:

```bash
make run TEST=full_network_10cases XSIM_ARGS="--testplusarg MAX_CASES=1"
```

Expected balanced summary:

```text
ANIMALS10_FULL_NETWORK_BALANCED cases=10 outputs_seen=100 out_mismatches=0 duplicates=0
```

Validated V1 baseline result:

```text
cases = 10
outputs_seen = 100
out_mismatches = 0
duplicates = 0
elapsed xsim time ~= 1:18:41 on the local workstation
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

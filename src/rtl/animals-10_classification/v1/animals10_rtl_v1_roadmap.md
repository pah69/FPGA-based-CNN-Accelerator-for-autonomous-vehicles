# Animals-10 RTL V1 Roadmap

This roadmap is tied to the PyTorch Student A export under:

```text
CNN_model/python/animals-10_classification/custom_cnn/int8_export/
```

Do not begin full RTL integration until these files are produced from a frozen
student checkpoint:

```text
animals10_model_config.json
animals10_layer_shapes.json
animals10_weights_i8.hex
animals10_bias_i32.hex
animals10_requant_mult_i32.hex
animals10_requant_shift_i8.hex
animals10_test_inputs_i8.hex
animals10_test_logits_i8.hex
animals10_test_labels.hex
debug_case0/*.npy
```

## Frozen First Target

```text
Input layout  : CHW channel-major
Input shape   : 3x64x64 signed INT8
Compute heart : explicit weight-stationary systolic array, SIZE=4 first
Layer set     : Conv3x3, ReLU, MaxPool2x2, GAP, Dense
No first V1   : EfficientNet blocks, depthwise conv, residual add, SE, Swish
```

V1 PE/array policy:

```text
PE weights        : active + shadow stationary weights
Weight preload    : load first tile before compute, then preload next tile during drain
Weight commit     : weight_switch_i at tile boundary before the next activation stream
Array structure   : explicit PE00..PE33 module for SIZE=4 debug
Future scaling    : parameterized array kept for later SIZE=8 experiments
```

Student A layer flow:

```text
conv1  3x64x64    -> 32x64x64
conv2  32x64x64   -> 32x64x64
pool1  32x64x64   -> 32x32x32
conv3  32x32x32   -> 64x32x32
conv4  64x32x32   -> 64x32x32
pool2  64x32x32   -> 64x16x16
conv5  64x16x16   -> 128x16x16
conv6  128x16x16  -> 128x16x16
pool3  128x16x16  -> 128x8x8
gap    128x8x8    -> 128
fc1    128        -> 128
fc2    128        -> 10
```

## Bring-Up Order

1. RGB input loader and UB readback checksum.
2. Conv1 accumulator and output match against `debug_case0/conv1_*`.
3. Conv1 through the SIZE=4 systolic array matches `debug_case0/conv1_*`.
4. Standalone Conv2 through the SIZE=4 systolic array matches `debug_case0/conv2_*`.
5. Conv1 + Conv2 + Pool1 match through `animals10_conv1_conv2_pool1_systolic_4x4`.
6. Validate standalone Conv3 and Conv4 systolic layers.
7. Conv3 + Conv4 + Pool2 match through `animals10_conv3_conv4_pool2_systolic_4x4`.
8. Validate standalone Conv5 and Conv6 systolic layers.
9. Conv5 + Conv6 + Pool3 match through `animals10_conv5_conv6_pool3_systolic_4x4`.
10. Validate standalone GAP, FC1, and FC2 against `debug_case0/*`.
11. Fuse GAP + FC1 + FC2 and match `debug_case0/fc2_*`.
12. Fuse Conv5 + Conv6 + Pool3 + GAP + FC1 + FC2 and match `debug_case0/fc2_*`.
13. Connect Conv1 through FC2 and run full case-0 logits match against `debug_case0/final_logits_i8.hex`.
14. Extend full-network validation from case 0 to the balanced 10-case vector set. Completed with 10 cases, 100 logits, 0 mismatches.
15. Replace staged bring-up memories with shared UB/weight/control infrastructure.

The direct Conv1 block is only the address/arithmetic reference. The real V1
datapath uses `animals10_systolic_array_4x4` through
`animals10_conv1_systolic_4x4` and `animals10_conv_systolic_4x4`.

Current V1 performance policy:

```text
First K tile per dot : load shadow, switch active, feed, drain
Later K tiles        : preload shadow during previous drain, switch at drain boundary
Conv1 target counter : cycles ~= 2064384, tiles = 229376, outputs = 131072
Conv2 target counter : cycles ~= 19103744, tiles = 2359296, outputs = 131072
Pool1 target counter : outputs = 32768
Conv3 target counter : cycles ~= 9551872, tiles = 1179648, outputs = 65536
Conv4 target counter : cycles ~= 18989056, tiles = 2359296, outputs = 65536
Pool2 target counter : outputs = 16384
Conv5 target counter : cycles ~= 9494528, tiles = 1179648, outputs = 32768
Conv6 target counter : cycles ~= 18931712, tiles = 2359296, outputs = 32768
Pool3 target counter : outputs = 8192
GAP target counter   : outputs = 128
FC1 target counter   : outputs = 128
FC2 target counter   : outputs = 10
Tail target counter  : final outputs = 10
Final-stage target   : final outputs = 10
Full-network target  : final outputs = 10
Balanced target      : 10 cases, 100 final outputs
```

These targets preserve the exact Python INT8 arithmetic contract. Future
MNIST-v5-style performance work should move toward streamed activation launch,
weight FIFO/fetcher integration, psum packer counters, and local accumulation
only after the full case-0 logits path matches the Python INT8 export.

## RTL Parameters To Decide

```text
SIZE                : 4 for V1
UB logical banks    : ping-pong minimum
UB bank depth       : at least 131072 bytes for 32x64x64 feature maps
weight storage      : BRAM ROM from animals10_weights_i8.hex first
requant storage     : per-output-channel multiplier/shift ROMs
input write path    : 32-bit packed writes preferred over byte AXI-Lite
```

SIZE=8 is future work after the 4x4 design matches Python INT8 and bandwidth
counters justify scaling the array.

## Required Counters

Keep the MNIST counter style and extend it before optimizing:

```text
total cycles
per-layer cycles
activation fetch cycles
weight fetch cycles
MXU active cycles
drain cycles
pool/GAP cycles
VPU/requant cycles
output write cycles
idle cycles
issued MACs
useful MACs
prefetch hits/misses/drops
packer backlog
row latency
FIFO full/empty wait
```

The first success criterion is exact Python INT8 logit match, not peak
throughput.

## V1 Baseline Freeze

The staged golden RTL path is frozen against:

```text
CNN_model/python/animals-10_classification/custom_cnn/int8_export/
```

Validated result:

```text
full_network_case0      : pass, 10 logits, 0 mismatches
full_network_10cases    : pass, 10 cases, 100 logits, 0 mismatches
compute core            : 4x4 systolic array
student architecture    : Conv/ReLU/Pool/GAP/FC only
```

Do not retrain, re-export, or change the student architecture inside this RTL
baseline unless the full staged golden flow is rerun. Model-accuracy experiments
should use a separate export branch until the shared-memory accelerator top is
stable.

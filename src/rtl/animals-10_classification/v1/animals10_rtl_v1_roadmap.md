# Animals-10 RTL V1 Roadmap

This roadmap is tied to the PyTorch Student A export under:

```text
CNN_model/python/Animals-10_classification/custom_cnn/int8_export/
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
Compute heart : weight-stationary systolic array, SIZE=4 first
Layer set     : Conv3x3, ReLU, MaxPool2x2, GAP, Dense
No first V1   : EfficientNet blocks, depthwise conv, residual add, SE, Swish
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
3. Conv1 + Conv2 + Pool1 match.
4. Add Conv3 + Conv4 + Pool2.
5. Add Conv5 + Conv6 + Pool3.
6. Add GAP and FC layers.
7. Run full logits match against `animals10_test_logits_i8.hex`.

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

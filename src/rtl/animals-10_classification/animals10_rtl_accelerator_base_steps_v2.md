# Animals-10 RTL Accelerator Base Design Steps — Updated V2

## 1. Goal

Build the next-generation RTL accelerator for an Animals-10 custom student CNN.

The MNIST accelerator is the reference design, not the final target. The Animals-10 accelerator should scale both:

```text
model complexity
RTL memory bandwidth
systolic array size
layer descriptor flexibility
testbench/golden-model infrastructure
```

Current MNIST reference:

```text
Dataset              : MNIST
Input                : 28×28×1
Best optimized branch: ~111k cycles/image
Array                : 4×4
Arithmetic           : signed INT8
Golden match         : Python INT8 logits
```

Animals-10 target:

```text
Dataset              : Animals-10
Input first target    : 64×64×3 RGB
Model target          : custom RTL-compatible student CNN
Teacher model         : EfficientNetB0/B1/B2
Arithmetic            : signed INT8
Golden reference      : Python INT8
```

---

## 2. Design Principle

Do not implement full EfficientNet in RTL first.

Use EfficientNet as the teacher model and deploy a custom student CNN that uses layers supported by the accelerator.

Core principle:

```text
Teacher gives accuracy.
Student gives hardware feasibility.
RTL must match the student Python INT8 model exactly.
```

---

## 3. Required First-Version Layer Support

Support these first:

```text
Conv2D 3×3
Conv2D 1×1 if student Version B is selected
ReLU
MaxPool2D 2×2 stride 2
GlobalAveragePooling or small FC classifier
Dense / FC
Bias add
Requantization
INT8 clamp
```

Training-time only:

```text
BatchNorm
Dropout
Data augmentation
```

BatchNorm must be folded into Conv before RTL export.

Future layers:

```text
DepthwiseConv2D
Residual Add
ReLU6
Squeeze-and-Excitation
MobileNet-like blocks
```

Do not make these required for the first Animals-10 RTL milestone.

---

## 4. Why Not Direct EfficientNet RTL

EfficientNetB0/B1/B2 include operations that are not in the current accelerator:

```text
depthwise convolution
pointwise-heavy blocks
squeeze-and-excitation
swish/silu-like activation
residual/skip structures
global average pooling
larger input resolutions
many more layers
```

Therefore:

```text
EfficientNet = teacher/backbone in Python.
Custom CNN = RTL deployment model.
```

---

## 5. First RTL-Compatible Student Model Assumption

Recommended first student:

```text
Input: 64×64×3

Conv3×3 3->32
Conv3×3 32->32
MaxPool

Conv3×3 32->64
Conv3×3 64->64
MaxPool

Conv3×3 64->128
Conv3×3 128->128
MaxPool

GlobalAveragePool
Dense 128
Dense 10
```

Expected shape flow:

```text
64×64×3
32×32×32
16×16×64
8×8×128
128
10 logits
```

The exact model must be frozen in Python before RTL modification begins.

---

## 6. RTL Scaling Requirements

### 6.1 RGB Input

MNIST input:

```text
28×28×1 = 784 bytes
```

Animals-10 input:

```text
64×64×3 = 12,288 bytes
```

Required updates:

```text
input loader
UB addressing
host software
testbench input files
channel-major RGB tensor support
```

Recommended tensor layout first:

```text
channel-major:
addr = base + c * H * W + y * W + x
```

---

## 7. Unified Buffer Scaling

Large feature maps require a much larger UB.

Example feature maps:

```text
64×64×32 = 131,072 bytes
32×32×64 = 65,536 bytes
16×16×128 = 32,768 bytes
8×8×128  = 8,192 bytes
```

Recommended first design:

```text
ping-pong logical banks
BRAM-backed storage
larger bank depth
optional 4-bank sub-banking
optional 32-bit packed activation read
```

Preferred future UB direction:

```text
multi-bank activation buffer
vector read support
separate current-demand and prefetch arbitration
```

---

## 8. Systolic Array Scaling

The current 4×4 array worked well for MNIST. Animals-10 has larger channels, so a larger array is more justified.

Updated V1 roadmap:

```text
Reference : 4×4
V1        : 4×4
Future    : 8×8, only after the 4×4 RTL matches Python INT8 and bandwidth counters justify scaling
Stretch   : 16×16
```

Reason 8×8 is a better fit:

```text
Animals-10 student channels are likely 32, 64, 128.
These channel counts map better to 8 output lanes.
```

Do not scale to 8×8 unless activation bandwidth also scales.

Required modules to parameterize:

```text
systolic array
PE grid
weight fetcher
activation skew buffer
psum packer
accumulator array
VPU lanes
output writer
debug counters
```

Use for V1:

```systemverilog
parameter int SIZE = 4;
```

---

## 9. DSP and Resource Mapping

The MNIST MXU may synthesize INT8 multipliers into LUTs instead of DSPs. For the scaled design, decide explicitly.

Recommended policy:

```text
PE/MXU multiplier path : use_dsp = yes
VPU requant multiply   : use_dsp = yes
Address generation     : use_dsp = no if DSPs are being wasted
Large memories         : ram_style/rom_style = block
Small FIFOs            : distributed or registers
```

Example:

```systemverilog
(* use_dsp = "yes" *)
logic signed [15:0] product_s2;
```

For memories:

```systemverilog
(* ram_style = "block" *)
logic [7:0] ub_bank0 [0:DEPTH-1];

(* rom_style = "block" *)
logic [7:0] weight_rom [0:WEIGHT_DEPTH-1];
```

Important:

```text
Using more resources only improves performance if it increases parallelism, bandwidth, or Fmax.
It does not automatically reduce cycles.
```

---

## 10. Layer Descriptor ROM

The layer descriptor must become generic.

Recommended fields:

```text
layer_id
layer_type
input_h
input_w
input_c
output_h
output_w
output_c
kernel_h
kernel_w
stride_h
stride_w
padding_h
padding_w
num_k_tiles
num_oc_tiles
input_bank
output_bank
input_base
output_base
weight_base
bias_base
requant_base
activation_mode
is_last_layer
```

Layer types:

```text
LAYER_CONV
LAYER_MAXPOOL
LAYER_GAP
LAYER_FC
```

Activation modes:

```text
ACT_NONE
ACT_RELU
ACT_RELU6 optional future
```

---

## 11. Address Generator

Must support:

```text
C×H×W tensors
RGB input
3×3 Conv
1×1 Conv
padding
stride
pooling
GAP
FC flattening if needed
```

Conv address formulas:

```text
input_addr  = input_base + ic * input_h * input_w + iy * input_w + ix

weight_addr = weight_base
            + oc * (input_c * kernel_h * kernel_w)
            + ic * kernel_h * kernel_w
            + ky * kernel_w
            + kx

output_addr = output_base + oc * output_h * output_w + oy * output_w + ox
```

Padding rule:

```text
if iy/ix outside input bounds:
    activation = 0
```

Tail lane rule:

```text
if invalid K lane or OC lane:
    activation/weight = 0
```

---

## 12. Global Average Pool Unit

If the student uses GAP, implement a GAP unit.

Function:

```text
for each channel:
    sum all H×W INT8 values into INT32
    divide by H×W
    output INT8 or INT32 based on next layer
```

For `8×8`, average is divide by 64:

```text
avg = sum >> 6
```

if scale design allows power-of-two division.

Otherwise:

```text
avg = requant(sum, reciprocal_multiplier, reciprocal_shift)
```

GAP is strongly recommended because it avoids a huge Flatten + FC layer.

---

## 13. Weight Storage

First implementation:

```text
BRAM-based ROM initialized by hex files
```

Required files:

```text
animals10_weights_i8.hex
animals10_bias_i32.hex
animals10_requant_mult_i32.hex
animals10_requant_shift_i8.hex
```

Future implementation:

```text
DDR weight loading
AXI DMA
weight tile cache
double-buffered weight prefetch
```

---

## 14. Activation Fetch and Prefetch

The MNIST project showed activation fetch is a major bottleneck.

Start with these from the beginning:

```text
pipelined activation gather
tag-matched activation prefetch queue
drain-only prefetch first
opportunistic abort
mandatory-read priority
```

Priority rule:

```text
1. current mandatory activation read
2. pooling/GAP mandatory read
3. output-critical read
4. speculative prefetch
```

Do not allow prefetch to extend drain or delay mandatory reads.

For larger models, plan for:

```text
32-bit packed activation reads
multi-bank activation reads
wider UB bandwidth
```

---

## 15. Drain and Psum Packer Strategy

MNIST diagnostics proved:

```text
drain extra_wait = 0
packer complete_backlog = 0
lane skew is deterministic
drain cost is real
```

Therefore:

```text
Do not reduce drain counters blindly.
Reduce drain frequency instead.
```

Future optimization:

```text
spatial-block streaming
```

Concept:

```text
load weight tile once
stream multiple spatial activation vectors
drain once
```

This reduces fixed drain overhead.

First Animals-10 version may keep safe per-tile drain behavior. Optimize later.

---

## 16. Host Software / PS Integration

Animals-10 input is much larger, so avoid byte-wise AXI-Lite loading in the final version.

Required upgrades:

```text
RGB image load
larger UB writes
32-bit packed writes
auto-increment write address
batch inference
CPU vs PL benchmark
```

Future:

```text
AXI DMA
DDR-based batch input
PL master read
```

---

## 17. Testbench Strategy

Use progressive bring-up.

### Test 1: RGB Input Load

```text
Load 64×64×3 image into UB.
Read back checksum.
```

### Test 2: Conv1 Only

```text
Compare Conv1 accumulator and INT8 output against Python.
```

### Test 3: Conv1 + Pool

```text
Compare Pool1 output.
```

### Test 4: One Full Block

```text
Conv1 -> Conv2 -> Pool1
```

### Test 5: Full Student CNN

```text
Full logits match Python INT8.
```

Required checks:

```text
layer accumulator check
layer output check
pool output check
GAP output check
FC output check
final logits check
prediction check
```

---

## 18. Performance Counters

Reuse and extend MNIST counters.

Required:

```text
total cycles
per-layer cycles
weight cycles
activation fetch cycles
MXU active cycles
drain cycles
VPU cycles
output cycles
pool/GAP cycles
idle cycles
issued MAC count
useful MAC count
valid MAC count
```

Prefetch:

```text
attempts
pushes
hits
misses
no_entry
wrong_k
wrong_spatial
wrong_oc
UB busy
queue occupancy
drops
```

Drain/packer:

```text
drain entries
cycles per drain entry
mxu_valid
psum_busy
acc_write
extra_wait
row latency
complete backlog
fifo full
fifo empty wait
```

---

## 19. Performance Metrics

Report:

```text
accuracy
cycles/image
latency/image
kernel FPS
end-to-end FPS
useful MACs/image
useful GMAC/s
useful GOPS
peak GOPS
MAC utilization
LUT/FF/BRAM/DSP usage
power
energy/image if available
```

Because inference is INT8:

```text
Use GOPS or GMAC/s, not FLOPS.
```

---

## 20. Bring-Up Roadmap

### Phase 1: Freeze Python Student

```text
Train and quantize the model.
Export layer shapes, weights, biases, requant params, and golden vectors.
```

### Phase 2: Prepare RTL Parameters

```text
input_h = 64
input_w = 64
input_c = 3
SIZE = 4 or 8
UB depth enlarged
weight ROM depth enlarged
descriptor ROM updated
```

### Phase 3: RGB Conv1

```text
Implement only Conv1 first.
Compare against Python INT8.
```

### Phase 4: Add Full Blocks

```text
Add Conv/Pool blocks one by one.
Debug layer outputs.
```

### Phase 5: GAP and Classifier

```text
Add GAP.
Add FC/Dense classifier.
Check final logits.
```

### Phase 6: Performance Optimization

```text
activation prefetch
weight prefetch
VPU/output prefetch
packed UB reads
multi-bank UB
spatial-block streaming
```

### Phase 7: Board Benchmark

```text
Run selected test images.
Run 100-image benchmark.
Run larger test set if feasible.
Compare CPU PS vs RTL PL.
```

---

## 21. Minimum Viable Animals-10 RTL

Minimum successful version:

```text
64×64×3 input
custom Conv/ReLU/Pool/GAP/FC student
signed INT8 inference
Python INT8 golden logit match
per-layer debug counters
ZCU104 implementation
resource/timing reports
```

Not required for first version:

```text
full EfficientNet
full MobileNetV2
depthwise convolution
residual add
AXI DMA
16×16 array
external DDR weights
```

---

## 22. Immediate Next Steps

```text
1. Freeze the Python student CNN architecture.
2. Export layer shapes and MAC counts.
3. Estimate UB memory capacity.
4. Estimate weight ROM capacity.
5. Decide 4×4 vs 8×8 for first Animals-10 RTL.
6. Refactor RTL module parameters.
7. Implement RGB Conv1 only.
8. Match Python INT8 Conv1.
9. Add remaining layers progressively.
```

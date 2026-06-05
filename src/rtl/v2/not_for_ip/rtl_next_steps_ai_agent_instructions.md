# AI Agent Instructions: RTL Next Steps for FPGA-Based CNN Accelerator

## Objective

Implement the missing RTL system integration around the existing TPU-like datapath so the accelerator can run the completed **signed symmetric INT8 small CNN** end-to-end and compare against the Python integer golden model.

The RTL target is **correctness first**, then resource/timing/throughput reporting.

Target numeric contract:

```text
activation_q : signed int8  [-128, 127]
weight_q     : signed int8  [-128, 127]
bias_q       : signed int32
accumulator  : signed int32
output_q     : signed int8  [-128, 127]
zero_point   : 0 for all activations and weights
```

Do not implement asymmetric zero-point subtraction.  
Do not build a full TPU-style ISA yet.  
Use a deterministic FSM controller with a layer descriptor table.

---

## Existing RTL Baseline

The current datapath already contains these blocks:

```text
wgt_fetcher_2x2
fifo
act_skew_buffer_2x2
ws_sa_2x2 / mxu_2x2
psum_packer_v2
accumulator_array_v2
bias_requantize_v2
activation_array_v2
normalizer_v2
pooling_unit_v2
post_process_v2
vector_processing_unit_v2
tpu_datapath_v2
```

The missing system-level pieces are:

```text
1. top-level wrapper
2. controller FSM
3. layer descriptor table
4. unified buffer
5. weight/bias/requant parameter memories
6. activation/window address generator
7. maxpool handling
8. RTL-vs-Python testbench integration
```

---

## Recommended Top-Level Architecture

Implement this first working architecture:

```text
testbench / PS-side control
        ↓
top.sv
        ├── tpu_controller.sv
        ├── layer_descriptor_pkg.sv
        ├── unified_buffer.sv
        ├── weight_rom.sv
        ├── bias_rom.sv
        ├── requant_mult_rom.sv
        ├── requant_shift_rom.sv
        ├── address_generator.sv
        ├── maxpool2d.sv
        └── datapath.sv
```

For the first version, memory can be preloaded from `.mem` / `.hex` files in simulation.  
AXI integration can be added after the RTL inference path works.

---

## Global Parameters

Use these default parameters for the first working system:

```systemverilog
parameter int SIZE           = 2;
parameter int DATA_WIDTH     = 8;
parameter int ACC_WIDTH      = 32;
parameter int OUT_WIDTH      = 8;
parameter int ACC_DEPTH      = 16;
parameter int MAX_K_TILES    = 128;  // must cover fc1: ceil(250 / 2) = 125
parameter int TILE_COUNT_WIDTH = $clog2(MAX_K_TILES + 1);
```

Important correction:

```text
Do not keep NUM_TILES = SIZE.
NUM_TILES / MAX_K_TILES must be large enough for the maximum layer K tile count.
For this model, max K tiles = 125 for fc1.
Use 128 as a clean power-of-two ceiling.
```

---

## CNN Layer Schedule

The model is:

```text
Input: 1 × 28 × 28

conv1: 1 → 8, 3×3
ReLU
MaxPool2d(2)

conv2: 8 → 10, 3×3
ReLU
MaxPool2d(2)

flatten: 10 × 5 × 5 = 250

fc1: 250 → 16
ReLU

fc2: 16 → 10
```

Use this execution schedule:

```text
1. CONV1: read input image, write full conv1 output
2. POOL1: read conv1 output, write pool1 output
3. CONV2: read pool1 output, write full conv2 output
4. POOL2: read conv2 output, write pool2 output
5. FC1:   read flattened pool2 output, write fc1 output
6. FC2:   read fc1 output, write final logits
```

For first bring-up, implement maxpool as a separate pass.  
Do not rely on the existing temporal `pooling_unit_v2` for 2D pooling in the MVP.

---

## Tensor Shapes

| Stage | Shape | Element Count |
|---|---:|---:|
| input | `1 × 28 × 28` | 784 |
| conv1 output | `8 × 26 × 26` | 5408 |
| pool1 output | `8 × 13 × 13` | 1352 |
| conv2 output | `10 × 11 × 11` | 1210 |
| pool2 output | `10 × 5 × 5` | 250 |
| fc1 output | `16` | 16 |
| fc2 output | `10` | 10 |

All activation tensors are signed INT8.

---

## Unified Buffer Design

Implement a ping-pong BRAM-style unified buffer.

Recommended MVP sizing:

```text
bank0: 8192 signed INT8 entries
bank1: 8192 signed INT8 entries
```

This is enough because the largest intermediate tensor is conv1 output:

```text
8 × 26 × 26 = 5408 bytes
```

Use bank swapping:

```text
input image      stored in bank0
CONV1:  bank0 → bank1
POOL1:  bank1 → bank0
CONV2:  bank0 → bank1
POOL2:  bank1 → bank0
FC1:    bank0 → bank1
FC2:    bank1 → bank0
```

Unified buffer interface should support:

```systemverilog
// Read port
input  logic                  rd_en_i;
input  logic                  rd_bank_i;
input  logic [ADDR_WIDTH-1:0] rd_addr_i;
output logic signed [7:0]     rd_data_o;
output logic                  rd_valid_o;

// Write port
input  logic                  wr_en_i;
input  logic                  wr_bank_i;
input  logic [ADDR_WIDTH-1:0] wr_addr_i;
input  logic signed [7:0]     wr_data_i;
```

For a 2-lane datapath, either:
- instantiate two read ports/banks, or
- perform two sequential reads and assemble one activation vector.

For MVP, sequential reads are acceptable if the controller timing is simple and deterministic.

---

## Constant Parameter Memories

Create ROMs initialized from the symmetric Python export files:

```text
small_cnn_sym_weights_i8_c_order.txt
small_cnn_sym_biases_i32_c_order.txt
small_cnn_sym_requant_mult_i32_c_order.txt
small_cnn_sym_requant_shift_u6_c_order.txt
```

Recommended ROMs:

```text
weight_rom:        4952 entries × signed int8
bias_rom:            44 entries × signed int32
requant_mult_rom:    44 entries × signed int32
requant_shift_rom:   44 entries × unsigned 6-bit
```

Memory offsets:

### Weight Base Offsets

```text
conv1 weight base = 0
conv2 weight base = 72
fc1   weight base = 792
fc2   weight base = 4792
```

### Bias / Requant Base Offsets

```text
conv1 base = 0
conv2 base = 8
fc1   base = 18
fc2   base = 34
```

---

## Layer Descriptor Table

Create a package or local ROM named:

```text
layer_descriptor_pkg.sv
```

Define one descriptor per compute layer:

```systemverilog
typedef enum logic [1:0] {
    LAYER_CONV = 2'd0,
    LAYER_FC   = 2'd1
} layer_type_t;

typedef enum logic [1:0] {
    ACT_BYPASS = 2'd0,
    ACT_RELU   = 2'd1
} act_mode_t;

typedef struct packed {
    layer_type_t layer_type;

    logic [15:0] in_h;
    logic [15:0] in_w;
    logic [15:0] in_ch;

    logic [15:0] out_h;
    logic [15:0] out_w;
    logic [15:0] out_ch;

    logic [15:0] kernel_h;
    logic [15:0] kernel_w;

    logic [15:0] k_total;
    logic [15:0] num_k_tiles;
    logic [15:0] num_oc_tiles;
    logic [15:0] num_spatial;

    logic [15:0] weight_base;
    logic [15:0] bias_base;
    logic [15:0] requant_base;

    act_mode_t act_mode;

    logic read_bank;
    logic write_bank;
} layer_desc_t;
```

Descriptor values:

| Layer | Type | `K_total` | `out_ch` | `num_k_tiles` | `num_oc_tiles` | `num_spatial` | Weight Base | Bias Base | Act |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| conv1 | CONV | 9 | 8 | 5 | 4 | 676 | 0 | 0 | ReLU |
| conv2 | CONV | 72 | 10 | 36 | 5 | 121 | 72 | 8 | ReLU |
| fc1 | FC | 250 | 16 | 125 | 8 | 1 | 792 | 18 | ReLU |
| fc2 | FC | 16 | 10 | 8 | 5 | 1 | 4792 | 34 | Bypass |

Spatial shapes:

```text
conv1 input:  C=1,  H=28, W=28
conv1 output: C=8,  H=26, W=26

conv2 input:  C=8,  H=13, W=13
conv2 output: C=10, H=11, W=11

fc1 input:    K=250
fc1 output:   16

fc2 input:    K=16
fc2 output:   10
```

---

## Controller FSM

Implement an FSM controller, not a full instruction set.

Recommended states:

```systemverilog
typedef enum logic [4:0] {
    S_IDLE,
    S_LOAD_LAYER_DESC,
    S_CLEAR_ACC_BLOCK,

    S_PREP_WEIGHT_TILE,
    S_WRITE_WEIGHT_FIFO,
    S_START_WEIGHT_LOAD,
    S_WAIT_WEIGHT_LOAD,

    S_STREAM_ACT_BLOCK,
    S_DRAIN_MXU,

    S_WAIT_ACC_READY,
    S_READ_ACC_ROW,
    S_WAIT_VPU_OUTPUT,
    S_WRITE_OUTPUT,

    S_NEXT_BLOCK,
    S_NEXT_K_TILE,
    S_NEXT_OC_TILE,
    S_NEXT_LAYER,

    S_RUN_POOL,
    S_DONE,
    S_ERROR
} ctrl_state_t;
```

Required loop structure for compute layers:

```text
for each compute layer:
  for each output-channel tile:
    for each spatial block of up to ACC_DEPTH output positions:

      clear accumulator rows for the active block

      for each K tile:
        load 2×2 weight tile into weight FIFO, bottom row first
        pulse start_wgt_load_i
        wait for wgt_load_done_o / wgt_fetcher_ready_o

        stream activation vectors for each spatial position in the block
        keep accumulator_write_en_i asserted while psums are being produced

        drain MXU / psum packer

      read completed accumulator rows
      feed VPU with bias/requant parameters for current output-channel tile
      write VPU INT8 outputs to unified buffer

    advance output-channel tile
  advance layer
```

---

## Controller Counters

Implement these counters:

```text
layer_idx
oc_tile_idx
k_tile_idx
sp_block_base
sp_local_idx
spatial_idx
drain_count
acc_read_idx
vpu_write_idx
weight_row_idx
```

Derived values:

```text
oc0 = oc_tile_idx * SIZE
k0  = k_tile_idx  * SIZE

block_size = min(ACC_DEPTH, num_spatial - sp_block_base)
```

Tail handling:

```text
if k >= K_total: activation = 0, valid = 1
if oc >= out_ch: weight = 0, output store disabled
```

Important:

```text
For padded K lanes, drive data = 0 and valid = 1.
Do not drive valid = 0 for a padded K lane, because that can break psum propagation through the systolic array.
```

---

## Weight Tile Packing

For a 2×2 systolic array:

```text
rows = K dimension
cols = output channels
```

Logical weight tile:

```text
          oc0      oc1
k0        w00      w01
k1        w10      w11
```

The existing `wgt_fetcher_2x2` expects the FIFO to be filled bottom-row first.

Push FIFO words in this order:

```text
FIFO word 0 = {w11, w10}   // bottom K row
FIFO word 1 = {w01, w00}   // top K row
```

Lane packing:

```text
word[7:0]   = column 0
word[15:8]  = column 1
```

For convolution weights:

```text
w(k, oc) = weight_rom[weight_base + oc * K_total + k]
```

where:

```text
k = ic * kernel_h * kernel_w + ky * kernel_w + kx
```

For FC weights:

```text
w(k, oc) = weight_rom[weight_base + k * out_ch + oc]
```

Invalid tail weights must be zero.

---

## Activation Address Generation

### Convolution

For each output spatial index:

```text
oh = spatial_idx / out_w
ow = spatial_idx % out_w
```

For each K index:

```text
ic = k / (kernel_h * kernel_w)
rem = k % (kernel_h * kernel_w)
ky = rem / kernel_w
kx = rem % kernel_w
```

Input address:

```text
input_addr = ic * in_h * in_w + (oh + ky) * in_w + (ow + kx)
```

Activation lane mapping for a 2-lane array:

```text
lane0 = activation for k0
lane1 = activation for k1
```

If `k >= K_total`, drive:

```text
activation = 0
valid = 1
```

### Fully Connected

For FC:

```text
input_addr = k
```

Activation lane mapping:

```text
lane0 = input[k0]
lane1 = input[k1]
```

If `k >= K_total`, drive zero with valid asserted.

---

## Accumulator Address Alignment

This is critical.

The controller must ensure `accumulator_write_addr_i` is aligned with the psum group currently leaving the MXU.

Recommended fix:

```text
Add a small address FIFO/tag FIFO.
Push sp_local_idx whenever an activation vector is launched.
Pop the address when the first psum lane of a new psum group appears.
Drive accumulator_write_addr_i from the popped address.
```

Expose `psum_packer_v2.busy_o` from `tpu_datapath_v2`:

```systemverilog
output logic psum_packer_busy_o;
```

Then detect first psum of a packed group:

```systemverilog
first_psum_valid = (|mxu_psum_valid_o) && !psum_packer_busy_o;
```

Use `first_psum_valid` to pop the address FIFO.

Do not assume the activation launch address and MXU output address are in the same cycle.

---

## VPU / Post-Process Changes

For the symmetric INT8 model:

```text
QUANT_ENABLE      = 1
QUANT_CLAMP_MIN   = -128
QUANT_CLAMP_MAX   = 127
NORM_SHIFT        = 0
output_zero_point = 0
POOL_MODE         = BYPASS inside main VPU path
```

Main VPU should perform:

```text
accumulator + bias
fixed-point requantization
signed INT8 clamp
optional ReLU
```

Do not add output zero-point.

Required RTL cleanup:

```systemverilog
assign vpu_output_zero_point_i = '0;
```

### Runtime Activation Mode

Current `ACT_MODE` is a static parameter.  
The CNN needs:

```text
conv1: ReLU
conv2: ReLU
fc1:   ReLU
fc2:   Bypass
```

Modify activation/post-process/VPU to accept runtime activation mode:

```systemverilog
input logic [1:0] act_mode_i;
```

Use only:

```text
ACT_BYPASS = 0
ACT_RELU   = 1
```

Do not spend time on ReLU6, sigmoid, or tanh for this model.

### Pooling

For MVP, set the main VPU pooling path to bypass:

```text
POOL_MODE = 0
```

Implement 2D maxpool as a separate module/pass:

```text
maxpool2d.sv
```

---

## MaxPool2d Unit

Implement a separate 2D maxpool unit for correctness-first integration.

Pool1:

```text
input:  8 × 26 × 26
output: 8 × 13 × 13
kernel: 2 × 2
stride: 2
```

Pool2:

```text
input:  10 × 11 × 11
output: 10 × 5 × 5
kernel: 2 × 2
stride: 2
```

For each output:

```text
out[c, oh, ow] = max(
    in[c, 2*oh,     2*ow],
    in[c, 2*oh,     2*ow + 1],
    in[c, 2*oh + 1, 2*ow],
    in[c, 2*oh + 1, 2*ow + 1]
)
```

For 11×11 input to 5×5 output, ignore the last row and last column.  
This matches standard floor behavior for MaxPool2d kernel=2, stride=2.

---

## `tpu_datapath_v2` Required Edits

Make these edits:

### 1. Increase max tile support

Change parameters so the runtime tile count can represent 125:

```systemverilog
parameter int MAX_NUM_TILES = 128;
parameter int TILE_COUNT_WIDTH = $clog2(MAX_NUM_TILES + 1);
```

Pass `MAX_NUM_TILES` into `mxu_2x2` and `accumulator_array_v2`.

### 2. Expose psum packer busy

Change:

```systemverilog
.busy_o()
```

to:

```systemverilog
.busy_o(psum_packer_busy_o)
```

and add top-level output:

```systemverilog
output logic psum_packer_busy_o;
```

### 3. Remove no-op assignments

Replace:

```systemverilog
assign accumulator_read_flatten_o =
    accumulator_read_flatten_w | (mxu_local_acc_result_w & '0);

assign done_o = vpu_done_w | (mxu_local_acc_done_w & 1'b0);
```

with:

```systemverilog
assign accumulator_read_flatten_o = accumulator_read_flatten_w;
assign done_o = vpu_done_w;
```

### 4. Add runtime activation mode

Add:

```systemverilog
input logic [1:0] vpu_act_mode_i;
```

Propagate it into:

```text
vector_processing_unit_v2
post_process_v2
activation_array_v2
```

### 5. Force symmetric zero-point

Use:

```systemverilog
vpu_output_zero_point_i = '0;
```

at the top/controller level.

---

## Top-Level Control Interface

For MVP simulation, use a simple control/status interface:

```systemverilog
input  logic clk;
input  logic rst_n;
input  logic start_i;
output logic done_o;
output logic error_o;
output logic [7:0] predicted_class_o;
```

Optional debug outputs:

```systemverilog
output logic [4:0] dbg_state_o;
output logic [3:0] dbg_layer_idx_o;
output logic [15:0] dbg_cycle_count_o;
output logic [31:0] dbg_error_code_o;
```

Error conditions:

```text
FIFO underflow
FIFO overflow
invalid layer descriptor
invalid memory address
accumulator timeout
VPU timeout
output write beyond tensor size
```

---

## Verification Plan

Create tests in this order.

### Test 1: ROM Load Test

Verify:

```text
weight_rom[0]
weight_rom[71]
weight_rom[72]
weight_rom[791]
weight_rom[792]
weight_rom[4791]
weight_rom[4792]
weight_rom[4951]
```

Verify bias and requant memory offsets:

```text
bias base: 0, 8, 18, 34
requant base: 0, 8, 18, 34
```

### Test 2: Single FC Tile

Use FC2 or a tiny synthetic FC layer.

Verify:

```text
activation vector packing
weight FIFO packing
psum output
accumulator result
VPU output
```

### Test 3: Single Conv1 Output Pixel

Compute only:

```text
conv1 output channel tile 0
one spatial position
all K tiles
```

Compare:

```text
accumulator INT32 vs Python
requant INT8 vs Python
```

### Test 4: Full Conv1 Layer

Compare:

```text
conv1 full output tensor before pool
```

### Test 5: Pool1

Compare:

```text
pool1 output tensor
```

### Test 6: Conv2 + Pool2

Compare:

```text
conv2 full output tensor
pool2 output tensor
```

### Test 7: FC1

Compare:

```text
fc1 output tensor
```

### Test 8: FC2

Compare:

```text
fc2 logits
argmax class
```

### Test 9: End-to-End Inference

Run complete MNIST sample:

```text
input image → conv1 → pool1 → conv2 → pool2 → fc1 → fc2 → predicted class
```

Final comparison:

```text
RTL final_logits_i8 == Python final_logits_i8
RTL argmax == Python argmax
```

---

## Testbench Inputs From Python

Use files generated by the Python side:

```text
small_cnn_sym_weights_i8_c_order.txt
small_cnn_sym_biases_i32_c_order.txt
small_cnn_sym_requant_mult_i32_c_order.txt
small_cnn_sym_requant_shift_u6_c_order.txt

input_image_i8.hex
layer0_conv_acc_i32.hex
layer0_out_i8.hex
layer1_conv_acc_i32.hex
layer1_out_i8.hex
layer2_fc_acc_i32.hex
layer2_out_i8.hex
layer3_fc_acc_i32.hex
final_logits_i8.hex
```

Use layer-by-layer comparison.  
Do not only compare the final class.

---

## Assertions to Add

Add SystemVerilog assertions or testbench checks:

```text
No weight FIFO write when full
No weight FIFO read when empty
No accumulator read before row_ready
No unified buffer write beyond bank size
No invalid output-channel store on tail OC tile
No controller state timeout
No VPU output accepted without valid
No final done before FC2 output count reaches 10
```

For padded lanes:

```text
If k_tail is invalid, activation must be 0 and valid must be 1.
If oc_tail is invalid, weight must be 0 and output write must be masked.
```

---

## Synthesis Configuration After Simulation Works

Only after RTL matches Python:

```text
1. run synthesis
2. run implementation
3. collect utilization
4. collect timing
5. collect power
6. measure cycles per inference
```

Collect:

```text
LUT
FF
DSP
BRAM
URAM
WNS
Fmax
Power
cycles per inference
latency
throughput
accuracy vs Python golden model
```

Peak compute for the 2×2 systolic array:

```text
peak MAC/cycle = 4
peak OP/cycle  = 8
```

Throughput formulas:

```text
latency_seconds = cycles_per_inference / Fclk
inferences_per_second = Fclk / cycles_per_inference
peak_GOPS = 2 * SIZE * SIZE * Fclk / 1e9
```

---

## Implementation Priority

Do the work in this order:

```text
1. Fix tpu_datapath_v2 tile-count width and cleanup no-op assignments
2. Add runtime activation mode to VPU path
3. Add psum_packer_busy_o and address FIFO/tag alignment
4. Implement weight/bias/requant ROMs
5. Implement ping-pong unified_buffer
6. Implement conv/fc activation address generator
7. Implement controller FSM for one compute layer
8. Verify one FC or conv tile
9. Extend controller to full conv1
10. Implement separate maxpool2d_unit
11. Add conv2, fc1, fc2 descriptors
12. Run full end-to-end RTL simulation
13. Synthesize and report resources/timing/power
```

---

## Non-Goals for MVP

Do not implement these yet:

```text
full TPU-like instruction set
AXI DMA
PL DDR integration
dynamic model loading
batching
INT4
DSP packing optimization
average pooling
sigmoid/tanh/ReLU6
multi-clock internal datapath
```

These can be thesis stretch goals after the signed INT8 RTL inference path is correct.

---

## Final RTL Deliverable

The AI agent should produce or modify these files:

```text
top.sv
tpu_controller.sv
layer_descriptor_pkg.sv
unified_buffer.sv
weight_rom.sv
bias_rom.sv
requant_mult_rom.sv
requant_shift_rom.sv
address_generator.sv
maxpool2d.sv
datapath.sv
vector_processing_unit.sv
post_process.sv
activation_array.sv
tb_top.sv
```

The final system must execute:

```text
signed INT8 activations
signed INT8 weights
INT32 accumulation
INT32 bias
fixed-point requantization
ReLU where required
2D maxpool where required
final FC2 logits
argmax class
```

and must match the Python integer golden model layer by layer.

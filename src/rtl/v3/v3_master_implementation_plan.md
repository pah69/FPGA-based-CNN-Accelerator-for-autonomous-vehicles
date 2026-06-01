# V3 Master Implementation Plan

This plan combines the downloaded V3 proposal with the measured V2 board counters.
The goal is a V3 RTL that is faster than the optimized CPU fast path while keeping the current signed symmetric INT8 model contract and golden-output checks.

## Baseline

Current V2 baseline on ZCU104:

```text
Clock              : 100 MHz
Model              : signed symmetric INT8 MNIST CNN
Array              : 2x2 weight-stationary systolic array
RTL/golden logits  : PASS
Accuracy           : 98.57%
Kernel cycles/img  : 386174
Kernel latency/img : 3861 us
Kernel FPS         : 258.95
CPU fast latency   : about 1388 us/img
CPU fast FPS       : about 720
```

V3 performance target:

```text
Minimum success : cycles/image < 386174, correctness still PASS
Strong success  : cycles/image < 139000, PL kernel beats CPU fast path
```

## Latest V2 Counter Snapshot

```text
Layer cycles:
  Conv1 = 136104
  Pool1 = 18933
  Conv2 = 194149
  Pool2 = 3505
  FC1   = 32124
  FC2   = 1359

Conv1 phase:
  wgt=7740 act_fetch=75712 mxu_active=40560 drain=12040
  acc=2876 vpu=16224 out=5408 idle=16104
  issued_mac=54080 useful_mac=48672 useful/issued=90%

Conv2 phase:
  wgt=12960 act_fetch=130680 mxu_active=65340 drain=20160
  acc=645 vpu=3630 out=1210 idle=24864
  issued_mac=87120 useful_mac=87120 useful/issued=100%

FC1 phase:
  wgt=9000 act_fetch=6000 mxu_active=3000 drain=14000
  acc=16 vpu=48 out=16 idle=3044
  issued_mac=4000 useful_mac=4000 useful/issued=100%
```

Main bottleneck order:

```text
1. Conv2 activation fetch and controller overhead
2. Conv1 activation fetch and VPU/writeback cost
3. FC1 drain overhead
4. Pool1 standalone pass cost
```

## Comparison With Downloaded Plan

The downloaded plan is directionally correct:

```text
- Do not jump directly to 16x16.
- Improve dataflow before chasing array size.
- Add useful_mac_count and issued_mac_count.
- Use exclusive state counters.
- Preserve layer-by-layer golden checks.
- Target 4x4 before larger arrays.
```

Corrections and refinements:

```text
1. Conv1 idle is now 16104 cycles, not 13572.
   This changed after the exclusive state counter fix.

2. V2 already streams a spatial block through each K tile.
   The issue is not that spatial-block streaming is absent; the issue is that
   activation reads are still serial and drain/reload overhead is paid too often.

3. An activation gather buffer hides UB latency, but does not reduce memory traffic by itself.
   To materially reduce Conv cycles, V3 needs window/line reuse or a wider/banked activation path.

4. Scaling only the MXU is unsafe.
   The activation feeder, weight loader, accumulator lanes, VPU lanes, output writeback,
   and counter logic must scale together.

5. The 4x4 tile-loop reduction table is useful as a rough target, not a guaranteed result.
   Actual speedup depends on whether the feeder can sustain the 4x4 array.
```

## V3 Architecture Target

V3 should be staged, not a single risky rewrite.

```text
V3.1: Same 2x2 MXU, improved dataflow.
V3.2: Parameterized NxN datapath, still validated at 2x2.
V3.3: 4x4 datapath enabled.
V3.4: FC drain reduction and final tuning.
```

Final intended V3 architecture:

```text
HOST/PS
  |
AXI-Lite control and UB access
  |
unified_buffer
  |
layer controller v3
  |-- weight_tile_buffer
  |-- activation_window_gather
  |-- spatial_block_scheduler
  |
mxu_NxN / ws_sa_NxN
  |
psum_packer_N
  |
accumulator_array_N
  |
vector_processing_unit_N
  |
unified_buffer output bank
```

## Implementation Order

### Step 0: Freeze V2

Before V3 RTL edits:

```text
1. Save the current bitstream.
2. Save UART logs with the new counters.
3. Save timing, utilization, and power reports.
4. Keep V2 RTL untouched except bug fixes.
5. Keep current software app as V2 benchmark reference.
```

Recommended tag:

```text
v2_2x2_verified_mnist_int8_counters
```

### Step 1: Create V3 Baseline Tree

Create V3 RTL as a separate implementation under:

```text
src/rtl/v3/
```

Do not edit V2 modules for the first V3 implementation except for shared documentation.

Initial V3 files should start from copied/renamed V2 files:

```text
tpu_top_v3.sv
tpu_top_axi_lite_v3.sv
tpu_controller_layer_v3.sv
tpu_controller_kloop_v3.sv
tpu_datapath_v3.sv
mxu_v3.sv
ws_sa_v3.sv
weight_tile_buffer_v3.sv
activation_window_gather_v3.sv
psum_packer_v3.sv
accumulator_array_v3.sv
vector_processing_unit_v3.sv
```

### Step 2: Keep 2x2, Fix Activation Fetch

First V3 target:

```text
ARRAY_K  = 2
ARRAY_OC = 2
```

Add:

```text
activation_window_gather_v3.sv
```

This module should not just gather a vector. It should support Conv window reuse.

Recommended role:

```text
1. Accept layer descriptor fields, spatial index, K tile index, and block size.
2. Generate activation addresses for all lanes.
3. Read ahead from unified_buffer.
4. Store a small queue of ready activation vectors.
5. Present act_vec_valid/act_vec_ready to MXU.
6. Count fetch stalls and useful lanes.
```

Minimum interface direction:

```text
controller -> gather:
  start_i
  clear_i
  layer_type_i
  spatial_base_i
  k_tile_i
  block_size_i
  descriptor fields

gather -> UB:
  ub_rd_en_o
  ub_rd_bank_o
  ub_rd_addr_o

UB -> gather:
  ub_rd_data_i
  ub_rd_valid_i

gather -> MXU:
  act_vec_o
  act_valid_o
  act_ready_i
```

Success metrics:

```text
Conv1 act_fetch cycles reduce by at least 2x.
Conv2 act_fetch cycles reduce by at least 2x.
RTL/golden logits remain PASS.
```

### Step 3: Improve Spatial Block Scheduling

V2 already uses a spatial block with `ACC_DEPTH=16`.
V3 should test larger block sizes only if accumulator storage and controller complexity remain reasonable.

Candidate settings:

```text
ACC_DEPTH/block_size = 16 baseline
ACC_DEPTH/block_size = 32
ACC_DEPTH/block_size = 64
```

The goal is to reduce:

```text
drain cycles per output
weight reload overhead per useful MAC
controller idle cycles
```

Success metrics:

```text
Conv1 drain cycles decrease.
Conv2 drain cycles decrease.
state_sum remains 100%.
useful_mac_count remains correct.
```

### Step 4: Add Weight Tile Buffer

A 4x4 array needs 16 weights per tile.
If weights are loaded serially without buffering, the larger array will stall.

Add:

```text
weight_tile_buffer_v3.sv
```

Required behavior:

```text
1. Load a full KxOC tile from weight ROM.
2. Hold it stable for the systolic array.
3. Support reuse across all spatial entries in the active block.
4. Expose empty/full/stall counters.
```

Counters:

```text
weight_load_cycles
weight_reuse_count
weight_buffer_empty_cycles
weight_buffer_full_cycles
```

### Step 5: Parameterize Datapath

Parameter names:

```systemverilog
parameter int ARRAY_K  = 2;
parameter int ARRAY_OC = 2;
parameter int DATA_W   = 8;
parameter int ACC_W    = 32;
parameter int ADDR_W   = 13;
```

Convert these paths together:

```text
activation lanes
weight tile width
output-channel lanes
psum packer lanes
accumulator lanes
VPU lanes
output writeback lanes
counter formulas
```

Do not enable 4x4 until the parameterized 2x2 path matches V2 outputs.

### Step 6: Enable 4x4

Enable:

```text
ARRAY_K  = 4
ARRAY_OC = 4
```

Expected effects:

```text
Peak MAC/cycle: 4 -> 16
K tile count decreases for Conv1, Conv2, FC1, FC2
OC tile count decreases for Conv1, Conv2, FC1, FC2
```

Required validations:

```text
Conv1 acc/out PASS
Conv2 acc/out PASS
FC1 acc/out PASS
FC2 logits PASS
100-image and 10000-image classification behavior unchanged
```

### Step 7: Reduce FC1 Drain

FC1 has:

```text
drain=14000 cycles
total=32124 cycles
```

Target:

```text
FC1 cycles < 16000
stretch: FC1 cycles < 10000
```

Approach:

```text
1. Keep accumulator context active across more K work.
2. Avoid drain/restart after small work groups.
3. For 4x4, process more output channels per tile.
```

### Step 8: Benchmark and Reports

For every milestone, collect:

```text
UART benchmark log
layer cycle counters
phase counters
issued/useful MAC counters
exclusive state counter check
Vivado utilization report
Vivado timing summary
Vivado power report
```

## Mandatory Counter Contract

Keep these counters for Conv1, Conv2, and FC1:

```text
weight_cycles
activation_fetch_cycles
mxu_active_cycles
drain_cycles
accumulator_cycles
vpu_cycles
output_write_cycles
idle_cycles
issued_mac_count
useful_mac_count
exclusive_state_cycles
```

Definitions:

```text
issued_mac_count:
  PE MAC slots that were issued, including padded lanes.

useful_mac_count:
  Real CNN MACs only. Excludes invalid K lanes and invalid output-channel lanes.

exclusive_state_cycles:
  One and only one FSM state bucket counted per layer cycle.
```

Required equations:

```text
exclusive_state_cycles / layer_cycles = 100%

mxu_active_ratio =
  mxu_active_cycles / layer_cycles

effective_MAC_per_cycle =
  useful_mac_count / layer_cycles

total_peak_utilization =
  useful_mac_count / (layer_cycles * ARRAY_K * ARRAY_OC)

mxu_active_useful_utilization =
  useful_mac_count / (mxu_active_cycles * ARRAY_K * ARRAY_OC)

mxu_active_issued_utilization =
  issued_mac_count / (mxu_active_cycles * ARRAY_K * ARRAY_OC)

useful_issued_ratio =
  useful_mac_count / issued_mac_count
```

## Recommended V3 Test Order

```text
1. compile/lint V3 RTL
2. activation_window_gather direct test
3. weight_tile_buffer direct test
4. mxu_v3 2x2 compatibility test
5. tpu_datapath_v3 2x2 compatibility test
6. Conv1 single pixel
7. Conv1 full layer
8. Pool1
9. Conv2 full layer
10. Pool2
11. FC1
12. FC2
13. top end-to-end 1 image
14. top end-to-end 100 images
15. top end-to-end 10000 images
16. synth/implementation/timing/power
17. board benchmark
```

## Avoid During V3

Do not add these until V3 is stable:

```text
new dataset
camera input
AXI DMA
AXI stream
16x16 array
software rewrite
new model topology
```

## Final Recommendation

The best V3 implementation is:

```text
1. Freeze V2.
2. Build V3.1 with same 2x2 array but better activation/window gather.
3. Improve spatial block and drain amortization.
4. Parameterize the datapath.
5. Enable 4x4 only after the 2x2 V3 path is correct and faster.
6. Then tune FC1 drain and output writeback.
```

This gives the lowest engineering risk and the highest chance that a 4x4 array produces real speedup instead of more idle hardware.

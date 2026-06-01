# V2 RTL Design Notes and V3 Upgrade Direction

This note summarizes the current v2 TPU RTL architecture and the main design changes needed for a faster v3.

## Current V2 Top-Level Structure

```text
PS / Host
  |
  | AXI4-Lite registers
  v
tpu_top_axi_lite
  |
  v
tpu_top
  |
  +--> unified_buffer
  |
  +--> tpu_controller_rom_layer
  |      |
  |      +--> layer_descriptor_rom
  |      +--> tpu_controller_rom_kloop
  |             |
  |             +--> conv_fc_address_generator
  |             +--> weight_rom
  |             +--> bias_rom
  |             +--> requant_mult_rom
  |             +--> requant_shift_rom
  |
  +--> tpu_datapath_v2
  |      |
  |      +--> mxu_2x2
  |      |      |
  |      |      +--> fifo
  |      |      +--> wgt_fetcher_2x2
  |      |      +--> act_skew_buffer_2x2
  |      |      +--> ws_sa_2x2
  |      |             |
  |      |             +--> pe x4
  |      |
  |      +--> psum_packer_v2
  |      +--> accumulator_array_v2
  |      +--> vector_processing_unit_v2
  |             |
  |             +--> post_process_v2
  |                    |
  |                    +--> bias_requantize_v2
  |                    +--> activation_array_v2
  |                    +--> normalizer_v2
  |                    +--> pooling_unit_v2
  |
  +--> maxpool2d_unit
```

## Runtime Layer Schedule

The current top FSM runs the full MNIST CNN schedule:

```text
Conv1 -> Pool1 -> Conv2 -> Pool2 -> FC1 -> FC2 -> Done
```

Current unified-buffer bank usage:

```text
Input image      : UB bank0
Conv1 output     : UB bank1
Pool1 output     : UB bank0
Conv2 output     : UB bank1
Pool2 output     : UB bank0
FC1 output       : UB bank1
FC2 final logits : UB bank0[0:9]
```

Host access to the unified buffer is allowed only when the top is idle, done, or in error. During inference, the controller owns the unified buffer.

## Layer Descriptors

The layer descriptor package hard-codes the current small MNIST model.

```text
Layer   K     K tiles   OC tiles   Spatial outputs
Conv1   9     5         4          676
Conv2   72    36        5          121
FC1     250   125       8          1
FC2     16    8         5          1
```

The current compute tile size is fixed around `SIZE=2`, so:

```text
K tiles  = ceil(K / 2)
OC tiles = ceil(output_channels / 2)
```

## Compute-Layer Flow

For Conv and FC layers, `tpu_controller_rom_layer` loops over spatial blocks and output-channel tiles. For each tile, it starts `tpu_controller_rom_kloop`.

The K-loop sequence is mostly serial:

```text
1. Generate activation and weight addresses
2. Read weights from ROM
3. Push bottom weight row into FIFO
4. Push top weight row into FIFO
5. Start weight fetch/load into the systolic array
6. Wait for weights to reach PEs
7. Read activation lane0 from unified buffer
8. Read activation lane1 from unified buffer
9. Launch activation pair into MXU
10. Drain MXU partial sums
11. Repeat for every K tile
12. Wait until accumulator rows are ready
13. Read accumulator row
14. Run VPU bias/requant/ReLU
15. Write output lane0 to unified buffer
16. Write output lane1 to unified buffer
```

This is functionally correct, but it leaves performance on the table because the controller spends many cycles feeding a very small array.

## Datapath Details

The main compute datapath is:

```text
Activation lanes + Weight lanes
        |
        v
mxu_2x2
        |
        v
psum_packer_v2
        |
        v
accumulator_array_v2
        |
        v
vector_processing_unit_v2
        |
        v
INT8 output lanes
```

Inside `mxu_2x2`:

```text
Weight path:
  weight_rom -> controller -> weight FIFO -> weight fetcher -> ws_sa_2x2

Activation path:
  unified_buffer -> controller -> act_skew_buffer_2x2 -> ws_sa_2x2
```

The systolic array is weight-stationary. Weights are loaded into the PEs first, then skewed activations are streamed through the rows.

## Accumulation and VPU

The main accumulation path is:

```text
ws_sa_2x2 bottom-row partial sums
  -> psum_packer_v2
  -> accumulator_array_v2
  -> vector_processing_unit_v2
```

`output_accumulator_v2` exists inside `ws_sa_2x2` for optional local accumulation, but the current full TPU datapath uses `accumulator_array_v2` as the real layer accumulator.

The VPU applies:

```text
accumulator INT32
  -> bias add
  -> fixed-point requantize
  -> clamp to signed INT8
  -> optional ReLU
  -> output INT8
```

Current max pooling for full layers is handled by `maxpool2d_unit`, not by the small streaming `pooling_unit_v2` inside the VPU.

## Current Performance Bottlenecks

The current RTL is correct, but it is not fast enough to beat the optimized CPU path for this small model.

Observed board result:

```text
CPU fast avg     ~= 1388 us/image
RTL kernel avg   ~= 3861 us/image
RTL end-to-end   ~= 4332 us/image
RTL cycles/image = 386174 cycles at 100 MHz
```

Main bottlenecks:

1. Small `2x2` MXU
   - Only 4 PEs.
   - Many K tiles and output-channel tiles are required.

2. Serial activation fetch
   - Lane0 and lane1 are read in separate states.
   - A larger array would starve if this feeding pattern remains unchanged.

3. Serial output writeback
   - Output lane0 and lane1 are written in separate states.

4. Weight reload overhead
   - Every K tile fetches weights from ROM and reloads the systolic array.

5. AXI4-Lite host transfer
   - Input image bytes are written one at a time through AXI4-Lite.

6. No compute/data movement overlap
   - Host load, layer compute, VPU, pooling, and output writeback are serialized.

7. Low MXU utilization must now be measured directly
   - Current RTL exposes full-run, per-layer, and compute-layer phase counters.
   - The next v3 decisions should be based on the phase counters and PE utilization.

## V3 Design Direction

V3 should not be just a larger array dropped into the current controller. A larger array needs matching bandwidth and control changes.

Recommended v3 target:

```text
Host / DMA / AXI master
  |
  v
multi-bank unified buffer or line-buffered input system
  |
  v
parameterized tile controller
  |
  +--> N-lane activation fetch
  +--> N x N weight fetch/load
  |
  v
ws_sa_NxN
  |
  v
psum packer / accumulator array
  |
  v
bias + requant + activation
  |
  v
output buffer
```

## Recommended V3 Work Order

### 1. Add Per-Stage And Phase Cycle Counters

Implemented v2 counters:

```text
Total cycles
Conv1 cycles
Pool1 cycles
Conv2 cycles
Pool2 cycles
FC1 cycles
FC2 cycles
```

For Conv1, Conv2, and FC1, v2 also exposes:

```text
weight_load_cycles
activation_fetch_cycles
mxu_active_cycles
mxu_drain_cycles
accumulator_cycles
vpu_cycles
output_write_cycles
controller_idle_cycles
valid_mac_count
issued_mac_count
useful_mac_count
exclusive_state_cycles
```

Current v2 register map for these counters:

```text
0x0C : total cycles
0x30 : Conv1 cycles
0x34 : Pool1 cycles
0x38 : Conv2 cycles
0x3C : Pool2 cycles
0x40 : FC1 cycles
0x44 : FC2 cycles

0x48 : Conv1 weight_load_cycles
0x4C : Conv1 activation_fetch_cycles
0x50 : Conv1 mxu_active_cycles
0x54 : Conv1 mxu_drain_cycles
0x58 : Conv1 accumulator_cycles
0x5C : Conv1 vpu_cycles
0x60 : Conv1 output_write_cycles
0x64 : Conv1 controller_idle_cycles
0x68 : Conv1 valid_mac_count
0xB4 : Conv1 issued_mac_count
0xB8 : Conv1 useful_mac_count
0xBC : Conv1 exclusive_state_cycles

0x6C : Conv2 weight_load_cycles
0x70 : Conv2 activation_fetch_cycles
0x74 : Conv2 mxu_active_cycles
0x78 : Conv2 mxu_drain_cycles
0x7C : Conv2 accumulator_cycles
0x80 : Conv2 vpu_cycles
0x84 : Conv2 output_write_cycles
0x88 : Conv2 controller_idle_cycles
0x8C : Conv2 valid_mac_count
0xC0 : Conv2 issued_mac_count
0xC4 : Conv2 useful_mac_count
0xC8 : Conv2 exclusive_state_cycles

0x90 : FC1 weight_load_cycles
0x94 : FC1 activation_fetch_cycles
0x98 : FC1 mxu_active_cycles
0x9C : FC1 mxu_drain_cycles
0xA0 : FC1 accumulator_cycles
0xA4 : FC1 vpu_cycles
0xA8 : FC1 output_write_cycles
0xAC : FC1 controller_idle_cycles
0xB0 : FC1 valid_mac_count
0xCC : FC1 issued_mac_count
0xD0 : FC1 useful_mac_count
0xD4 : FC1 exclusive_state_cycles
```

The software computes:

```text
mxu_active_ratio = mxu_active_cycles / layer_cycles
issued_PE_utilization_during_mxu_active = issued_mac_count / (mxu_active_cycles * 4)
useful_PE_utilization_during_mxu_active = useful_mac_count / (mxu_active_cycles * 4)
useful_issued_ratio = useful_mac_count / issued_mac_count
exclusive_state_ratio = exclusive_state_cycles / layer_cycles
```

`mxu_active_cycles` is counted from actual PE-valid activity in the 2x2 array, not only from the controller launch state.
`issued_mac_count` mirrors the PE-slot activity that the older `valid_mac_count` register exposed.
`useful_mac_count` is counted from the address-generator valid weight mask, so padded K/OC lanes are excluded.
`exclusive_state_cycles` is the controller-state partition sanity counter and should track the corresponding layer cycle count.

### 2. Make the MXU Truly Parameterized

Move from:

```text
mxu_2x2 / ws_sa_2x2
```

to:

```text
mxu_NxN / ws_sa_NxN
```

Start with:

```text
SIZE=4
```

Then evaluate:

```text
SIZE=8
SIZE=16
```

Do not jump directly to `32x32` for MNIST unless timing/resource reports justify it.

### 3. Widen Activation Fetch

For `SIZE=N`, the controller must fetch `N` activation lanes efficiently.

V2 behavior:

```text
read lane0
read lane1
launch 2 lanes
```

V3 target:

```text
read/fetch N lanes
launch N lanes
```

Possible approaches:

- Wider unified-buffer read port.
- Multi-bank unified buffer.
- Small activation lane gather buffer.
- Line buffer for convolution layers.

### 4. Widen Weight Fetch and Load

For `NxN`, each tile needs `N x N` weights.

V2 pushes two weight rows through a small FIFO. V3 needs a scalable weight loader:

```text
weight ROM / memory -> N-row weight buffer -> ws_sa_NxN
```

Avoid reloading weights more often than necessary.

### 5. Improve Output Writeback

For `SIZE=N`, the VPU can produce `N` output lanes. The output path should write more than one byte per cycle or use a packed write path.

V2 writes:

```text
output0
output1
```

V3 should support:

```text
output[0:N-1]
```

with fewer controller states.

### 6. Improve Host Data Movement

AXI4-Lite is acceptable for control registers, but not ideal for moving image tensors.

For v3:

```text
AXI4-Lite: control/status only
AXI DMA / AXI Stream / AXI master: tensor movement
```

This matters more as model/input size increases.

## What To Keep From V2

Keep these concepts:

- Signed symmetric INT8 contract.
- ROM-backed model parameters for fixed MNIST.
- Descriptor-driven layer control.
- Unified-buffer bank scheduling.
- Separate full-layer `maxpool2d_unit`.
- Bias/requant/ReLU VPU structure.
- Directed tests and golden comparison flow.

## What To Replace Or Redesign

Replace or heavily revise:

- `mxu_2x2`
- `ws_sa_2x2`
- `act_skew_buffer_2x2`
- `wgt_fetcher_2x2`
- serial lane reads in `tpu_controller_rom_kloop`
- serial output writes in `tpu_controller_rom_kloop`

These are the main blocks that limit throughput.

## Practical V3 Milestones

1. Run board app and record layer/phase cycle breakdown.
2. Use `mxu_active_ratio` and PE utilization to choose the next bottleneck.
3. Create `ws_sa_NxN` with `SIZE=4` first.
4. Create matching `act_skew_buffer_NxN`.
5. Create matching `wgt_fetcher_NxN`.
6. Update datapath to instantiate `mxu_NxN`.
7. Update controller activation fetch for `SIZE` lanes.
8. Update controller output writeback for `SIZE` lanes.
9. Run existing layer and end-to-end tests.
10. Compare CPU fast vs RTL again.

## Summary

V2 proves correctness:

```text
PS -> AXI4-Lite -> unified buffer -> controller -> 2x2 MXU -> accumulator -> VPU -> final logits
```

V3 should target throughput:

```text
faster tensor movement + wider activation/weight feeding + larger systolic array
```

The first step should be per-layer counters, then a parameterized `NxN` compute path with enough memory bandwidth to keep it busy.

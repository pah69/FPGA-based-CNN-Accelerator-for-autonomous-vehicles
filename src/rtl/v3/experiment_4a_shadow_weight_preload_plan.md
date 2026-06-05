# Experiment 4A: Drain-Only Shadow-Weight Preload

## Objective

Implement a low-risk weight-loading optimization for the current V3.2 RTL accelerator.

Current V3.2 baseline:

```text
Array size          : 4×4
Current cycles/img  : 149,636 cycles
Clock               : 100 MHz
Kernel latency/img  : 1.496 ms
Kernel FPS          : 668.29 FPS
Correctness         : PASS
```

Experiment 4A aims to reduce cycles by overlapping **next weight-tile preload** with the **current tile drain phase**.

Target:

```text
Reduce weight-load / idle overhead
Keep correctness unchanged
Keep 4×4 array size
Avoid major controller redesign
```

Strong target:

```text
cycles/image < 139,000
```

---

## High-Level Architecture Idea

The PE already supports two weight registers:

```text
weight_shadow  = stores newly loaded / next tile weight
weight_active  = stores currently used compute weight
weight_switch  = copies shadow weight into active weight
```

Current behavior is mostly serial:

```text
load weight K
switch K active
compute K
drain K
load weight K+1
switch K+1 active
compute K+1
```

Experiment 4A changes this to:

```text
load weight K
switch K active
compute K
drain K while preloading K+1 into shadow
switch K+1 active
compute K+1
```

The key concept:

```text
preload next tile into shadow during current tile drain
```

This hides part of the next weight-load cost behind the current drain phase.

---

## Why Use Drain-Only Preload First?

There are two possible overlap strategies:

```text
Option A: preload during current tile drain only
Option B: preload during current tile compute + drain
```

Use **Option A first**.

Reason:

```text
Drain-only preload is safer.
It avoids modifying PE shadow weights while active computation is still launching activations.
It reduces risk of switching weights too early.
It requires fewer controller changes.
```

After drain-only preload is proven correct, compute+drain overlap can be considered later.

---

## Current Schedule

Current simplified K-tile schedule:

```text
for each K tile:
    fetch weight tile from ROM
    push weight rows into FIFO
    start weight fetch/load
    wait for weight load done
    switch weights active
    fetch activations
    launch MXU
    drain MXU
    accumulate psums
```

Problem:

```text
weight loading is serialized with compute/drain
```

---

## Target Schedule

### First K Tile

The first tile has no previous compute/drain phase to hide behind.

Keep it normal:

```text
load K0 into shadow
switch K0 shadow -> active
compute K0
```

### Middle K Tiles

For each tile K:

```text
compute K
during drain of K:
    preload K+1 into shadow
after drain_done and preload_done:
    switch K+1 shadow -> active
compute K+1
```

### Last K Tile

If the current tile is the last K tile:

```text
compute last K tile
drain last K tile
do not preload
continue to accumulator/VPU/output
```

---

## Required Safety Rules

### Rule 1: Never Switch Weights While Old Data Is In Flight

Do not assert `weight_switch_i` until all current-tile work is safe.

Safe switch condition:

```text
drain_done == 1
preload_done == 1
psum_packer_busy == 0
accumulator write for current tile is complete
```

Suggested expression:

```systemverilog
switch_allowed =
    drain_done &&
    preload_done_q &&
    !psum_packer_busy_i &&
    accum_write_done;
```

If weights switch too early, old activations or psums may use the wrong weights.

---

### Rule 2: Do Not Overwrite Shadow Before Switching

The PE only has one shadow slot.

Do not load K+2 into shadow if K+1 is already loaded but not yet switched active.

```text
if shadow_valid && !weight_switch_done:
    block next preload
```

---

### Rule 3: First Tile Is Normal

No overlap for K0.

```text
K0 must be loaded and switched before compute begins
```

---

### Rule 4: Last Tile Does Not Preload

If there is no next K tile, do not start preload.

```systemverilog
has_next_k_tile = (k_tile_idx_q + 1 < num_k_tiles);
```

---

### Rule 5: Tail Lanes Must Be Zeroed

For invalid K or output-channel lanes:

```text
weight = 0
```

Do not allow stale shadow weights to remain in padded lanes.

This matters for layers such as:

```text
Conv1: K = 9, SIZE = 4
Conv2: out_ch = 10, SIZE = 4
FC2  : out_ch = 10, SIZE = 4
```

---

## Signals / Flags To Add

Inside `tpu_controller_rom_kloop.sv`, add internal control flags:

```systemverilog
logic preload_busy_q;
logic preload_done_q;
logic shadow_valid_q;
logic switch_pending_q;

logic [K_TILE_W-1:0] active_k_tile_q;
logic [K_TILE_W-1:0] shadow_k_tile_q;
logic [K_TILE_W-1:0] preload_k_tile_q;
```

Meaning:

| Signal | Purpose |
|---|---|
| `active_k_tile_q` | K tile currently used by active PE weights |
| `shadow_k_tile_q` | K tile currently stored in PE shadow registers |
| `preload_k_tile_q` | Next K tile being loaded |
| `preload_busy_q` | Preload process is active |
| `preload_done_q` | Preload finished |
| `shadow_valid_q` | Shadow contains valid next tile |
| `switch_pending_q` | Weight switch should occur when safe |

---

## Required Interface Separation

Check the current weight-loader interface.

You need to know whether `weight_switch` is controlled by:

```text
wgt_fetcher
```

or by:

```text
tpu_controller_rom_kloop
```

For Experiment 4A, the desired separation is:

```text
weight preload done != weight switch
```

Recommended interface:

```systemverilog
input  logic start_wgt_preload_i;
output logic wgt_preload_done_o;
input  logic weight_switch_i;
output logic wgt_fetcher_busy_o;
```

Meaning:

| Signal | Meaning |
|---|---|
| `start_wgt_preload_i` | Begin loading weights into PE shadow registers |
| `wgt_preload_done_o` | Shadow registers now contain the next weight tile |
| `weight_switch_i` | Controller explicitly copies shadow -> active |
| `wgt_fetcher_busy_o` | Weight loader cannot accept new preload request |

If the current `wgt_fetcher` automatically generates `weight_switch_o`, split that behavior.

---

## Suggested FSM Changes

Current likely states:

```text
S_FETCH_ROM
S_WAIT_ROM
S_WRITE_WEIGHT_ROW
S_START_WEIGHT_LOAD
S_WAIT_WEIGHT_LOAD
S_LAUNCH_ACT
S_DRAIN
```

Add or modify states around drain:

```text
S_DRAIN_AND_PRELOAD_NEXT
S_WAIT_DRAIN_AND_PRELOAD
S_SWITCH_TO_PRELOADED
```

### Proposed Drain-Only Flow

```text
S_LAUNCH_ACT
    launch current tile activation vector(s)

S_DRAIN_AND_PRELOAD_NEXT
    run drain counter for current tile
    if has_next_k_tile and shadow is free:
        start preloading next weight tile into shadow

S_WAIT_DRAIN_AND_PRELOAD
    wait until:
        drain_done == 1
        preload_done == 1, if preload was started

S_SWITCH_TO_PRELOADED
    if has_next_k_tile:
        pulse weight_switch_i
        mark shadow as consumed
        advance active_k_tile
    else:
        finish layer/block path
```

---

## Implementation Steps

### Step 1: Freeze V3.2

Before starting:

```text
tag: v3_2_4x4_act_gather_pool_pipeline_pass
```

Save:

```text
RTL source
simulation logs
board logs
Vivado utilization report
Vivado timing summary
Vivado power report
```

### Step 2: Inspect Weight-Control Ownership

Check these files:

```text
wgt_fetcher_*.sv
tpu_controller_rom_kloop.sv
tpu_datapath_v2.sv
ws_sa_*.sv
pe.sv
```

Answer:

```text
Who generates weight_switch?
Does the fetcher auto-switch?
Can the controller delay weight_switch?
```

### Step 3: Separate Preload From Switch

Modify weight control so that:

```text
preload loads PE shadow registers only
switch copies shadow registers to active registers only when controller says so
```

Required behavior:

```text
preload_done does not imply active weights changed
```

### Step 4: Add Preload Flags In K-Loop Controller

Add:

```systemverilog
preload_busy_q
preload_done_q
shadow_valid_q
switch_pending_q
active_k_tile_q
shadow_k_tile_q
preload_k_tile_q
```

Reset them on:

```text
reset
new layer
new output-channel tile
new spatial block, if needed
```

### Step 5: Keep First Tile Normal

For K0:

```text
load K0
wait preload_done
pulse weight_switch
compute K0
```

Do not attempt overlap on the first tile.

### Step 6: Start Preload During Drain

In the drain phase of tile K:

```text
if has_next_k_tile && !shadow_valid_q && !preload_busy_q:
    start preload for K+1
```

Preload target:

```text
preload_k_tile_q = active_k_tile_q + 1
```

### Step 7: Wait For Both Drain and Preload

Before switching:

```text
wait until drain_done == 1
wait until preload_done_q == 1, if preload started
```

For last tile:

```text
only wait for drain_done
```

### Step 8: Switch To Preloaded Weights

When safe:

```text
pulse weight_switch_i for one cycle
active_k_tile_q <= shadow_k_tile_q
shadow_valid_q <= 0
preload_done_q <= 0
```

Then continue compute with the next K tile.

### Step 9: Handle Tail Lanes

When generating the preload weight tile:

```text
if k_index >= K_total:
    weight = 0

if oc_index >= OUT_CH:
    weight = 0
```

This prevents stale weights from affecting padded lanes.

### Step 10: Add Debug Counters

Add or reuse counters:

```text
weight_load_cycles
preload_overlap_cycles
switch_wait_cycles
idle_cycles
drain_cycles
```

Useful derived metrics:

```text
preload_overlap_efficiency = preload_overlap_cycles / weight_load_cycles_before
cycles_saved = baseline_cycles - experiment_cycles
```

### Step 11: Test Progressively

Run tests in this order:

```text
1. FC2 small test
2. FC1 test
3. Conv1 single image
4. Conv2 single image
5. Full end-to-end simulation
6. Full board benchmark
```

Required correctness checks:

```text
Conv1 acc  PASS
Conv1 out  PASS
Conv2 acc  PASS
Conv2 out  PASS
FC1 acc    PASS
FC1 out    PASS
FC2 logits PASS
RTL/golden logits PASS
```

### Step 12: Compare Results

Baseline:

```text
V3.2 cycles/image = 149,636
```

Experiment 4A result must satisfy:

```text
correctness PASS
cycles/image < 149,636
timing still passes
```

Good result:

```text
save 5,000 to 10,000 cycles/image
```

Strong result:

```text
cycles/image < 139,000
```

---

## What To Measure Before And After

| Metric | V3.2 Baseline | Experiment 4A |
|---|---:|---:|
| Total cycles/image | 149,636 | TBD |
| Conv1 cycles | 52,948 | TBD |
| Conv2 cycles | 69,751 | TBD |
| FC1 cycles | 13,420 | TBD |
| Weight load cycles | TBD | lower |
| Drain cycles | TBD | same or lower |
| Idle cycles | TBD | lower |
| PE utilization | TBD | same or higher |
| Correctness | PASS | must PASS |
| WNS/timing | TBD | must PASS |

---

## Expected Benefit

Experiment 4A targets:

```text
weight load cycles
idle cycles
part of visible drain/load overhead
```

Expected result:

```text
realistic saving: 3k–12k cycles/image
strong saving:   10k–15k cycles/image
```

Current remaining gap to CPU-fast target:

```text
149,636 - 138,900 ≈ 10,736 cycles/image
```

So Experiment 4A may be enough, but it is not guaranteed.

---

## Common Failure Modes

### Failure 1: Wrong Logits

Likely cause:

```text
weight_switch asserted too early
```

Fix:

```text
delay switch until drain_done and psum_packer_busy == 0
```

### Failure 2: No Speed Improvement

Likely cause:

```text
preload is not actually overlapping with drain
```

Check:

```text
preload_overlap_cycles
weight_load_cycles
idle_cycles
```

### Failure 3: FIFO Underflow / Overflow

Likely cause:

```text
preload FSM and existing weight FSM both drive the same FIFO controls
```

Fix:

```text
add clear ownership/arbitration for FIFO writes
```

### Failure 4: Tail-Lane Errors

Likely cause:

```text
invalid K or OC lanes keep stale shadow weights
```

Fix:

```text
explicitly write zero to invalid lanes during preload
```

---

## Recommended Implementation Strategy

Start with the safest version:

```text
Experiment 4A = drain-only shadow-weight preload
```

Do not start with compute+drain overlap.

Recommended order:

```text
1. Freeze V3.2.
2. Inspect current weight switch ownership.
3. Separate preload from switch.
4. Add preload flags.
5. Keep K0 normal.
6. During drain of K, preload K+1 into shadow.
7. Switch only after drain_done and preload_done.
8. Zero tail lanes.
9. Add counters.
10. Run progressive tests.
11. Compare against 149,636 cycles/image.
```

If Experiment 4A is correct and beneficial, keep it as V3.3.

If it saves less than ~3k cycles or creates too much risk, revert and document it as future work.

---

## Thesis Explanation Template

Use this if Experiment 4A works:

```text
Experiment 4A exploits the PE shadow-weight registers to overlap the next weight-tile preload with the drain phase of the current tile. In the previous schedule, weight loading and computation were serialized. The modified controller loads the next K-tile weights into the PE shadow registers while the current tile drains, then switches the shadow weights into the active registers only after the current psums are safely drained. This reduces visible weight-load and idle overhead while preserving the original systolic computation semantics.
```

Use this if Experiment 4A does not help enough:

```text
A shadow-weight preload experiment was evaluated to reduce visible weight-load overhead by overlapping next-tile loading with the current tile drain phase. Although the PE architecture supports separate shadow and active weights, the measured improvement was limited because the remaining performance bottleneck was dominated by convolution activation/dataflow and drain scheduling rather than isolated weight-load latency. Therefore, more aggressive compute/dataflow overlap is left as future work.
```

# V4 Optimization Plan

V4 improves the proven V2 design instead of continuing the V3 rewrite.

## Baseline Decision

Use V2 as the performance baseline:

- V2 full inference on ZCU104: about 386k cycles per image.
- V2 Conv1: about 136k cycles.
- V2 Conv2: about 194k cycles.
- V2 FC1: about 32k cycles.

V3 is paused because its spatial-block Conv1 prototype was functionally correct
but slower, about 350k cycles for Conv1. V3 reduced repeated weight traffic, but
the request/gather/control path serialized too much work and lost the fast V2
streaming behavior.

## Lessons From V3

1. Do not replace the whole V2 datapath unless the replacement wins layer by layer.
2. Weight reuse alone is not enough. Extra controller states, activation gather
   latency, and drain bubbles can erase the benefit.
3. The V2 K-loop already has useful streaming behavior through `block_size=16`
   and tag tracking, so preserve that structure.
4. Optimize the existing V2 schedule first:
   - compress avoidable FSM states,
   - overlap reads/writes where safe,
   - reduce drain/idle cycles,
   - keep correctness checks at every layer.
5. Keep V3 ideas only as references, not as direct RTL imports.

## Main V4 Files

- `tpu_top.sv`
  - End-to-end stage sequencer.
  - Owns layer/pool order and top-level cycle counters.
- `tpu_controller_rom_layer.sv`
  - Walks spatial blocks and output-channel tiles.
  - Starts one K-loop tile controller run per block/OC tile.
- `tpu_controller_rom_kloop.sv`
  - Main optimization target.
  - Drives ROM reads, weight FIFO writes, activation reads, MXU launch, drain,
    accumulator read, VPU, and UB output writes.
- `tpu_datapath_v2.sv`
  - MXU, psum packer, accumulator, and VPU datapath.
- `mxu_2x2.sv`, `wgt_fetcher_2x2.sv`, `act_skew_buffer.sv`, `ws_sa_2x2.sv`
  - Weight-stationary 2x2 compute core.

## Current K-Loop Schedule

Current `tpu_controller_rom_kloop.sv` flow:

```text
S_CLEAR_ACC_BLOCK
S_FETCH_ROM
S_WAIT_ROM
S_WRITE_WEIGHT_BOTTOM
S_WRITE_WEIGHT_TOP
S_START_WEIGHT_LOAD
S_WAIT_WEIGHT_LOAD
for each row in block:
  S_READ_ACT0_REQ
  S_READ_ACT0_WAIT
  S_READ_ACT1_REQ
  S_READ_ACT1_WAIT
  S_LAUNCH_ACT
S_DRAIN_MXU
S_WAIT_ACC_READY
for each row in block:
  S_READ_ACC_ROW
  S_WAIT_VPU_OUTPUT
  S_WRITE_OUTPUT0
  S_WRITE_OUTPUT1
S_DONE
```

This is correct and fast enough to beat the V3 prototype, but still has
optimization room.

## Step 1: Counter Audit

Goal: trust the numbers before changing behavior.

Actions:

- Confirm top counters still report:
  - layer total cycles,
  - weight load cycles,
  - activation fetch cycles,
  - MXU active cycles,
  - MXU drain cycles,
  - accumulator cycles,
  - VPU cycles,
  - output write cycles,
  - controller idle cycles,
  - valid/issued/useful MAC counts.
- Add missing K-loop local counters only if top-level counters are too coarse.
- Keep counters debug-only in purpose and avoid feeding them into scheduling.

Pass condition:

- V4 copied from V2 matches V2 test results and cycle counts before optimization.

Suggested tests:

```bash
make test_tpu_top_e2e RTL_VERSION=v4
make test_controller_conv1_layer RTL_VERSION=v4
make test_controller_conv2_layer RTL_VERSION=v4
```

## Step 2: Low-Risk FSM Compression

Goal: remove bubbles without changing memory or datapath timing.

Candidates:

- Merge `S_FETCH_ROM`/`S_WAIT_ROM` only if ROM valid timing still holds.
- Compress transitions after `S_WAIT_WEIGHT_LOAD` into first activation request.
- Compress `S_DRAIN_MXU` to enter next K tile immediately when the last psum is
  known drained.
- Compress accumulator/VPU/output row loop where valid signals allow it.

Risk:

- Low to medium. Must preserve one-cycle ROM/UB read latency and psum packer
  drain timing.

Pass condition:

- Layer outputs unchanged.
- Cycle count improves for Conv1 and Conv2.

## Step 3: Activation Fetch Overlap

Goal: reduce activation fetch cycles, a large visible cost.

Current activation fetch is lane-serial:

```text
READ_ACT0_REQ -> READ_ACT0_WAIT -> READ_ACT1_REQ -> READ_ACT1_WAIT
```

Possible improvements:

- Add a small activation prefetch register for the next row while current row is
  launching/draining.
- If UB remains single-read-port, do not expect same-cycle dual-lane reads.
- If future UB supports dual read, replace lane-serial fetch with two-lane fetch.

Risk:

- Medium. Prefetch must not corrupt row tags or launch order.

Pass condition:

- `activation_fetch_cycles` drops.
- `valid/useful MAC counts` unchanged.

## Step 4: Weight Load Overlap

Goal: hide weight ROM/FIFO/load latency under current MXU drain or row streaming.

Current weight flow is fully before activation launch:

```text
FETCH_ROM -> WAIT_ROM -> WRITE_WEIGHT_BOTTOM -> WRITE_WEIGHT_TOP
-> START_WEIGHT_LOAD -> WAIT_WEIGHT_LOAD
```

Possible improvements:

- Prefetch next K tile ROM data while current K tile is streaming activations.
- Write next tile into FIFO during current tile drain if FIFO space allows.
- Keep old `wgt_fetcher_2x2` load contract until a focused test proves a better
  replacement.

Risk:

- Medium to high. Need avoid overwriting active weight stream timing.

Pass condition:

- `weight_load_cycles` or `controller_idle_cycles` drops.
- Conv2 benefits more than Conv1 because it has many more K tiles.

## Step 5: Output Readback/VPU Loop Compression

Goal: reduce post-compute cycles after accumulator rows are ready.

Current output row loop:

```text
READ_ACC_ROW -> WAIT_VPU_OUTPUT -> WRITE_OUTPUT0 -> WRITE_OUTPUT1
```

Possible improvements:

- Pipeline next accumulator read while writing current output if VPU input/output
  timing allows it.
- Add a small output holding register if UB write latency blocks the next read.
- Keep channel-major output layout unchanged.

Risk:

- Medium. Must preserve `done_i` timing into VPU for the final row.

Pass condition:

- `vpu_cycles` or `output_write_cycles` drops.
- Final logits and intermediate tensors still match.

## Step 6: Only Then Consider Datapath Changes

Do not start here.

Possible later changes:

- Wider MXU, for example 4x4.
- Dual-read unified buffer.
- Double-buffered weights.
- Separate activation line/window buffer.

These are larger architectural changes and should happen only after V4 squeezes
the existing V2 schedule.

## Initial Implementation Order

1. Verify copied V4 equals V2.
2. Add any missing per-state debug counters.
3. Optimize K-loop FSM compression.
4. Re-run Conv1/Conv2/FC1 layer tests.
5. Optimize activation fetch overlap.
6. Optimize weight load overlap.
7. Optimize output readback/VPU loop.
8. Re-run full end-to-end tests and software benchmark.

## Success Metrics

Minimum useful target:

- V4 full inference below V2's about 386k cycles per image.

Good target:

- Conv1 below 120k cycles.
- Conv2 below 170k cycles.
- Full inference below 330k cycles.

Stretch target:

- Full inference below 300k cycles without increasing the array size.

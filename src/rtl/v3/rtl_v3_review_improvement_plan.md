# RTL Review and V3 Improvement Plan

## Context

This document summarizes the current RTL status after reviewing the uploaded SystemVerilog design files and the latest V2/V3 benchmark data.

Current verified baseline:

```text
Model                 : MNIST CNN, signed symmetric INT8
Board                 : ZCU104 / Zynq UltraScale+ MPSoC
Clock                 : 100 MHz
V2 array              : 2×2
V3 array              : 4×4
V2 cycles/image       : 386,174
V3 cycles/image       : 218,956
V3 speedup vs V2      : 1.76×
V3 kernel latency     : 2.189 ms/image
V3 kernel throughput  : 456.71 FPS
Accuracy              : 98.57%
Correctness           : RTL/golden logits PASS
```

V3 currently keeps the V2 control/dataflow structure and mainly changes the systolic array size from `2×2` to `4×4`, including the directly related MXU, weight-fetch, skew-buffer, accumulator, and VPU lane widths.

The current V3 is a valid improvement, but the design is still limited by data feeding and controller sequencing rather than raw PE count.

---

## 1. What Is Good Now

### 1.1 Functional Correctness Is Strong

The strongest part of the design is correctness.

Current validation flow includes:

```text
CPU golden layer check
Conv1 accumulator check
Conv1 output check
Conv2 accumulator check
Conv2 output check
FC1 accumulator check
FC1 output check
FC2 accumulator check
FC2 final logits check
CPU-vs-RTL classification check
```

This is much stronger than only checking final class accuracy.

Good result:

```text
RTL/golden logits: PASS
Accuracy         : 98.57%
Hardware failures: 0
```

### 1.2 V2 and V3 Are Measurable

The design now has useful cycle counters:

```text
total cycles
Conv1 cycles
Pool1 cycles
Conv2 cycles
Pool2 cycles
FC1 cycles
FC2 cycles
phase counters
issued MAC counters
useful MAC counters
state-sum checks
```

This is thesis-quality instrumentation. It allows architecture decisions to be driven by measured evidence instead of guesses.

### 1.3 V3 Scaling Works

V3 proves the array can scale from `2×2` to `4×4`.

Measured result:

| Layer | V2 Cycles | V3 4×4 Cycles | Speedup |
|---|---:|---:|---:|
| Conv1 | 136,104 | 71,876 | 1.89× |
| Pool1 | 18,933 | 18,933 | 1.00× |
| Conv2 | 194,149 | 108,955 | 1.78× |
| Pool2 | 3,505 | 3,505 | 1.00× |
| FC1 | 32,124 | 14,924 | 2.15× |
| FC2 | 1,359 | 763 | 1.78× |
| **Total** | **386,174** | **218,956** | **1.76×** |

This proves that the scalable MXU work is real.

### 1.4 Descriptor-Driven Layer Control Is Good

The layer-descriptor structure is a good architectural decision.

Good features:

```text
hard-coded layer descriptor ROM
layer-specific K, output channels, spatial size
runtime activation mode
runtime bank selection
per-layer schedule
clear layer-level control
```

This keeps the design more scalable than hardcoding every layer directly inside the datapath.

### 1.5 Unified Buffer Is Ping-Pong Capable

The unified buffer has two independent banks:

```text
bank0_mem
bank1_mem
```

The controller can use:

```text
read_bank_i
write_bank_i
```

This supports ping-pong scheduling:

```text
input image  -> bank0
conv1 output -> bank1
pool1 output -> bank0
conv2 output -> bank1
pool2 output -> bank0
fc1 output   -> bank1
fc2 logits   -> bank0
```

This is correct for the current MNIST pipeline.

### 1.6 PE Design Has Useful Features

The PE design includes:

```text
signed INT8 multiply
local psum pipeline alignment
shadow weight register
active weight register
weight switch control
overflow flag
valid propagation
```

The shadow/active weight structure is especially important because it can support future overlap:

```text
current active weights compute
next weights preload into shadow
switch when safe
```

### 1.7 Psum Packer and Accumulator Are Reasonable

The design has:

```text
psum_packer_v2
accumulator_array_v2
row_ready flags
packed psum valid
accumulator readback
VPU handoff
```

This is a good separation of concerns:

```text
MXU produces partial sums
psum packer aligns lanes
accumulator stores INT32 rows
VPU does bias/requant/ReLU
```

### 1.8 VPU Path Matches the INT8 Contract

The VPU path supports:

```text
INT32 accumulator
INT32 bias
fixed-point requantization
signed INT8 clamp
runtime ReLU/bypass
zero-point = 0
```

This matches the signed symmetric INT8 Python export.

### 1.9 Dedicated MaxPool2d Unit Is Correct

The design uses a separate full-layer `maxpool2d_unit`, not the small temporal pooling unit inside the VPU.

This is correct for:

```text
MaxPool2d(kernel=2, stride=2)
```

Pooling remaining unchanged between V2 and V3 is expected because it is outside the systolic array.

---

## 2. What Is Concerning Now

### 2.1 PE Utilization Is Still Low

Current V3 useful PE utilization:

```text
Conv1 useful PE util = 10.71%
Conv2 useful PE util = 11.90%
FC1 useful PE util   = 14.17%
```

This means the array is larger, but the design still cannot keep it busy.

Main reason:

```text
data/control sequencing is the bottleneck, not raw PE count
```

### 2.2 V3 Gives 1.76×, Not 4×

The 4×4 array has 4× the peak MAC capacity of the 2×2 array:

```text
2×2 peak = 4 MAC/cycle
4×4 peak = 16 MAC/cycle
```

But measured total speedup is:

```text
1.76×
```

This is not a failure. It means the larger array is starved by the surrounding architecture.

### 2.3 Unified Buffer Read Bandwidth Is Too Narrow

Current unified buffer read interface is:

```systemverilog
rd_en_i
rd_bank_i
rd_addr_i
rd_data_o  // one signed INT8 element
rd_valid_o
```

So the buffer provides:

```text
1 byte per read
```

But a 4×4 MXU needs:

```text
4 activation lanes per vector
```

The controller therefore fetches activation lanes serially.

### 2.4 Activation Fetch Is the Dominant Bottleneck

Measured V2 counters showed:

```text
Conv1 act_fetch = 75,712 cycles
Conv2 act_fetch = 130,680 cycles
```

Combined:

```text
206,392 cycles
```

That was more than half of the V2 kernel time.

The RTL confirms why:

```text
S_READ_ACT_REQ
S_READ_ACT_WAIT
```

These states fetch one activation lane at a time.

For `SIZE=4`, a complete activation vector requires:

```text
lane0 request + wait
lane1 request + wait
lane2 request + wait
lane3 request + wait
then launch vector
```

This makes the 4×4 MXU wait for the unified buffer.

### 2.5 Weight Loading Is Still Mostly Serial

Current weight flow:

```text
S_FETCH_ROM
S_WAIT_ROM
S_WRITE_WEIGHT_ROW
S_START_WEIGHT_LOAD
S_WAIT_WEIGHT_LOAD
```

For `SIZE=4`, each tile contains:

```text
4 rows × 4 columns = 16 weights
```

The weight ROM side is partially parallel, but rows are still pushed into the FIFO and loaded into the array sequentially.

This is functional, but it limits throughput.

### 2.6 Shadow Weights Are Not Fully Exploited Yet

The PE supports:

```text
weight_shadow
weight_active
weight_switch_i
```

But the controller still behaves mostly like:

```text
load weights
switch weights
compute
drain
load next weights
```

Future improvement should overlap:

```text
current tile compute/drain
next tile weight preload into shadow registers
```

### 2.7 Output Writeback Is Serial

Current output write state:

```text
S_WRITE_OUTPUT_LANE
```

For `SIZE=4`, up to four output lanes are written one at a time.

This is not currently the top bottleneck, but it becomes more important as compute is optimized.

### 2.8 MaxPool2d Is Serial

`maxpool2d_unit` reads four samples per output and then writes one output.

Current pooling cycles:

```text
Pool1 = 18,933 cycles
Pool2 = 3,505 cycles
```

Pooling is not the main bottleneck today, but as Conv1/Conv2 improve, Pool1 will become more visible.

### 2.9 Historical Module Names Are Confusing

Some modules are now parameterized but still named as `2x2`:

```text
mxu_2x2
ws_sa_2x2
wgt_fetcher_2x2
act_skew_buffer_2x2
```

This is not a functional issue, but it is confusing for documentation and thesis presentation.

Future cleanup:

```text
mxu.sv
ws_sa.sv
wgt_fetcher.sv
act_skew_buffer.sv
```

### 2.10 Some Debug Counters Are Too Narrow

Some debug cycle counters are declared as 16-bit:

```text
dbg_cycle_count_o [15:0]
```

For full-layer or full-inference counters, 16 bits is not enough.

Use 32-bit counters for all performance counters:

```systemverilog
logic [31:0] cycle_counter;
```

### 2.11 Dead/Unused Tag Logic Exists in K-loop

The k-loop contains tag FIFO-related signals:

```text
first_psum_valid_w
tag_stream_active_w
tag_push_w
tag_pop_w
```

But several are currently assigned zero.

This is not harmful if the current addressing is correct, but it is confusing and should either be:

```text
removed
```

or:

```text
fully implemented for more aggressive pipelining
```

### 2.12 AXI-Lite Input Loading Is Still Inefficient

The current host path still writes input through AXI-Lite.

This is no longer the main kernel bottleneck, but it still affects end-to-end time.

Current priority:

```text
kernel cycle reduction first
host transfer optimization second
```

---

## 3. Main Technical Diagnosis

The current V3 proves that a larger array helps, but the design is still limited by the V2-style schedule.

Current simplified compute flow:

```text
load weight tile
fetch activation lanes serially
launch one activation vector
repeat for spatial block
drain
read accumulator
run VPU
write output lanes serially
```

Main bottleneck:

```text
activation feeding cannot keep the MXU busy
```

The 4×4 array is not fully utilized because:

```text
1. unified buffer read width is only 8 bits
2. activation vector assembly is serial
3. weight load is not overlapped with compute
4. systolic fill/drain cost is still high
5. output writes remain lane-serial
```

---

## 4. Recommended Improvement Strategy

The next goal should not be `8×8` or `16×16` immediately.

The next goal should be:

```text
V3.1 = 4×4 array + better feeding/dataflow
```

Only after V3.1 improves utilization should the design scale to 8×8.

---

## 5. Experiment Plan

Each experiment should be implemented in a separate branch.

For every experiment, record:

```text
correctness: RTL/golden logits PASS/FAIL
accuracy
total cycles/image
Conv1 cycles
Conv2 cycles
FC1 cycles
Pool cycles
phase counters
useful PE utilization
LUT/FF/DSP/BRAM usage
WNS/timing
```

Use this common benchmark table:

| Metric | Baseline V3 | Experiment Result |
|---|---:|---:|
| Accuracy | 98.57% | TBD |
| Logits match | PASS | TBD |
| Total cycles/image | 218,956 | TBD |
| Kernel FPS | 456.71 | TBD |
| Conv1 cycles | 71,876 | TBD |
| Conv2 cycles | 108,955 | TBD |
| FC1 cycles | 14,924 | TBD |
| Useful PE util Conv1 | 10.71% | TBD |
| Useful PE util Conv2 | 11.90% | TBD |
| Useful PE util FC1 | 14.17% | TBD |

---

# Experiment 1: Pipelined Activation Lane Gather

## Goal

Reduce activation fetch cycles without changing the unified-buffer storage width.

## Current Problem

The controller uses:

```text
S_READ_ACT_REQ
S_READ_ACT_WAIT
```

for every activation lane.

For `SIZE=4`, this is approximately:

```text
2 cycles/lane × 4 lanes = 8 cycles
```

before one activation vector is ready.

## Idea

Issue UB read requests in consecutive cycles and collect returned data one cycle later.

Instead of:

```text
request lane0
wait lane0
request lane1
wait lane1
request lane2
wait lane2
request lane3
wait lane3
launch vector
```

use:

```text
cycle 0: request lane0
cycle 1: request lane1, capture lane0
cycle 2: request lane2, capture lane1
cycle 3: request lane3, capture lane2
cycle 4: capture lane3
cycle 5: launch vector
```

This reduces gather cost from roughly:

```text
8 cycles/vector
```

to roughly:

```text
5 cycles/vector
```

## Implementation Options

### Option 1A: Modify `tpu_controller_rom_kloop.sv`

Replace:

```text
S_READ_ACT_REQ
S_READ_ACT_WAIT
```

with a small pipelined gather FSM:

```text
S_ACT_GATHER
S_ACT_FINALIZE
S_LAUNCH_ACT
```

Track:

```text
request_lane_idx
capture_lane_idx
pending_read_count
act_lane_q[SIZE]
```

### Option 1B: Add `activation_gather_buffer.sv`

Add a new module between controller and unified buffer:

```text
controller
  -> activation_gather_buffer
  -> unified_buffer
```

The gather buffer handles requests/captures internally and presents:

```text
act_vec_o
act_vec_valid_o
```

This is cleaner and better for future 8×8.

## Expected Benefit

Target:

```text
Conv1/Conv2 activation fetch cycles reduce by 25–40%
```

## Risk

Low to medium.

This is the best first experiment.

---

# Experiment 2: 32-bit Packed Unified-Buffer Read

## Goal

Read four activation bytes in one memory access when addresses are contiguous.

## Current Problem

The unified buffer is 8-bit wide:

```text
one read = one INT8 activation
```

But a 4×4 array wants four activation lanes.

## Idea

Add a 32-bit read mode:

```text
rd_word_en_i
rd_word_addr_i
rd_word_data_o[31:0]
rd_word_valid_o
```

One read returns:

```text
byte0 = UB[addr + 0]
byte1 = UB[addr + 1]
byte2 = UB[addr + 2]
byte3 = UB[addr + 3]
```

## Important Constraint

This only works directly when activation addresses are contiguous.

Good cases:

```text
FC layers
conv lanes within the same input row and adjacent kx values
```

Bad cases:

```text
conv lanes crossing kernel row boundary
conv lanes crossing input channel boundary
padding lanes
```

## Implementation Options

### Option 2A: Fast Path + Fallback

Use packed read if:

```text
addr_lane1 = addr_lane0 + 1
addr_lane2 = addr_lane0 + 2
addr_lane3 = addr_lane0 + 3
```

Otherwise use serial lane gather.

### Option 2B: Change Activation Layout

Change tensor layout to make K-lane vectors contiguous more often.

This is higher risk because it affects:

```text
Python export
CPU golden model
address generator
pooling
FC flattening
```

Do not do this unless there is enough time.

## Expected Benefit

Target:

```text
large activation fetch reduction for FC1
partial reduction for Conv1/Conv2
```

## Risk

Medium.

Do after Experiment 1 if time allows.

---

# Experiment 3: Four-Bank Interleaved Unified Buffer

## Goal

Allow up to four activation reads per cycle for the 4×4 array.

## Idea

Replace each logical UB bank with four physical sub-banks:

```text
bank0_sub0
bank0_sub1
bank0_sub2
bank0_sub3

bank1_sub0
bank1_sub1
bank1_sub2
bank1_sub3
```

Map address to sub-bank:

```text
sub_bank = addr[1:0]
row_addr = addr >> 2
```

Then the gather unit can request up to four addresses per cycle.

## Bank Conflict Rule

If two requested lanes target the same sub-bank, service them over multiple cycles.

## Pros

```text
supports non-contiguous lane addresses better than packed read
scales naturally to 4×4
good architecture for thesis
```

## Cons

```text
more RTL changes
more complex read conflict handling
requires careful verification
```

## Expected Benefit

Target:

```text
activation fetch cycles reduce significantly
Conv1/Conv2 speed improve
PE utilization improve
```

## Risk

Medium to high.

Good stretch experiment if Experiment 1 succeeds quickly.

---

# Experiment 4: Weight Preload Using PE Shadow Registers

## Goal

Reduce weight load and idle cycles by loading the next weight tile while the current tile is still computing or draining.

## Current Situation

PE already has:

```text
weight_shadow
weight_active
weight_switch_i
```

This is good.

## Current Schedule

```text
load current weights
switch weights
compute
drain
load next weights
```

## Target Schedule

```text
active weights compute current tile
shadow weights preload next tile
drain current tile
switch to next weights
continue
```

## Implementation Steps

1. Add `next_weight_tile_valid`.
2. Add preload phase that writes PE shadow registers while current tile is active or draining.
3. Prevent `weight_switch_i` until current psums are safely drained.
4. Add hazard check:

```text
do not switch active weights while old activations/psums are still in flight
```

## Expected Benefit

Reduces:

```text
weight cycles
idle cycles
some drain-visible overhead
```

## Risk

Medium.

Do after activation gather because weight load is not currently the dominant bottleneck.

---

# Experiment 5: FC1 Drain Reduction

## Goal

Reduce FC1 drain overhead.

## Current Problem

FC1 has high drain cost.

V2 example:

```text
FC1 drain = 14,000 cycles
```

V3 improved but FC1 is still an important efficiency target.

## Likely Cause

FC1 has:

```text
spatial = 1
large K
many K tiles
```

The design pays a drain cost very often.

## Possible Implementations

### Option 5A: Overlap Weight Preload With FC Drain

This is safer than trying to eliminate drain.

Use Experiment 4's shadow-weight preload.

### Option 5B: Specialized FC Schedule

Create a simpler FC datapath schedule:

```text
for each output-channel tile:
    clear accumulator once
    stream K tiles as tightly as possible
    drain at tile-group boundaries
    VPU once
```

### Option 5C: FC-Specific Dot Product Mode

Bypass some systolic behavior for FC layers and use a lane-parallel vector dot-product style.

This is higher risk and less reusable.

## Expected Benefit

Target:

```text
FC1 cycles reduce by 20–40%
```

## Risk

Medium to high depending on option.

---

# Experiment 6: Pool1 Optimization

## Goal

Reduce Pool1 cycles after Conv1/Conv2 improve.

## Current Pooling Cost

```text
Pool1 = 18,933 cycles
Pool2 = 3,505 cycles
```

Pooling did not improve in V3 because it uses `maxpool2d_unit`, not the systolic array.

## Possible Implementations

### Option 6A: Pipelined 2×2 Pool Read

Current pool FSM reads samples serially:

```text
read sample0
read sample1
read sample2
read sample3
write max
```

Pipeline read requests similarly to Experiment 1.

### Option 6B: 32-bit Read for Pool Windows

If two or four pool samples are contiguous, read them in packed form.

### Option 6C: Fuse Conv + Pool

For Conv1 and Conv2, avoid writing full conv output to UB before pooling.

Instead:

```text
compute enough conv outputs for one 2×2 pool window
take max
write pooled output
```

This can save UB writes/reads, but it is complex.

## Recommendation

Do not optimize pooling first.

Only do this if Conv1/Conv2 have already improved and Pool1 becomes a large share of runtime.

---

# Experiment 7: Output Writeback Improvement

## Goal

Reduce serial output lane writes.

## Current Problem

Current output state writes one lane at a time:

```text
S_WRITE_OUTPUT_LANE
```

For `SIZE=4`, this can require four write cycles per output row.

## Constraint

Current tensor layout appears channel-major:

```text
addr = base + oc * spatial + spatial_idx
```

So output lanes for different output channels are not contiguous.

That makes 32-bit packed output writes difficult without changing tensor layout.

## Options

### Option 7A: Keep Output Writeback As Is

Recommended for now.

Output write is not the top bottleneck.

### Option 7B: Change Tensor Layout

Store output lanes contiguously:

```text
addr = base + spatial_idx * out_ch + oc
```

This improves packed output writes but affects:

```text
address generator
pooling
FC flattening
Python reference layout
CPU golden model
```

High risk.

## Recommendation

Do not do this before activation feeding is improved.

---

# Experiment 8: Host Transfer Optimization

## Goal

Reduce PS-to-PL end-to-end overhead.

## Current Status

The main current bottleneck is kernel cycles, not host overhead.

However, the host path still writes input through AXI-Lite byte-wise or word-wise.

## Possible Improvements

```text
32-bit packed UB write
auto-increment write address
batch mode
AXI DMA
AXI master read from DDR
```

## Recommendation

Keep this as a secondary task.

It improves end-to-end FPS, but it will not solve the current PE-utilization issue.

---

## 6. Recommended 29-Day Work Plan

### Week 1: Freeze Baselines and Set Up Experiments

Goals:

```text
freeze V2
freeze current V3
collect reports
make benchmark tables
prepare experiment branches
```

Tasks:

```text
1. Tag current V2 and V3 repositories.
2. Save V2/V3 bitstreams.
3. Save UART logs.
4. Save Vivado utilization/timing/power reports.
5. Create a standard benchmark script/report template.
6. Verify V3 correctness on the full test set.
7. Record V3 phase counters.
```

Deliverables:

```text
V2 baseline table
V3 baseline table
V2 vs V3 resource table
V2 vs V3 cycle table
V3 bottleneck table
```

### Week 2: Implement Experiment 1

Primary task:

```text
pipelined activation lane gather
```

Implementation strategy:

```text
1. Create branch: exp1_pipelined_act_gather
2. Implement new gather FSM or activation_gather_buffer.
3. Keep SIZE=4.
4. Do not change tensor layout.
5. Re-run layer-by-layer golden checks.
6. Re-run 100-image and full benchmark.
```

Success target:

```text
Conv1 cycles reduce
Conv2 cycles reduce
act_fetch cycles reduce by at least 25%
logits still PASS
timing still passes at 100 MHz
```

Decision gate:

```text
If Experiment 1 passes, keep it.
If it fails after 3 focused debugging days, revert and document it as future work.
```

### Week 3: Choose One Stretch Optimization

Choose based on Experiment 1 result.

#### If activation fetch is still dominant

Try:

```text
Experiment 2: 32-bit packed UB read
```

or:

```text
Experiment 3: four-bank interleaved UB
```

#### If weight/idle becomes dominant

Try:

```text
Experiment 4: shadow-weight preload
```

#### If FC1 remains disproportionately slow

Try:

```text
Experiment 5: FC1 drain reduction
```

Recommended order:

```text
1. 32-bit or pipelined activation read
2. shadow-weight preload
3. FC1 drain reduction
```

Do not attempt more than one high-risk redesign in Week 3.

### Week 4: Freeze, Report, and Prepare Submission

Tasks:

```text
1. Freeze the best working RTL version.
2. Run full correctness validation.
3. Run full benchmark.
4. Generate final Vivado reports.
5. Generate final tables.
6. Write thesis implementation chapter.
7. Write evaluation chapter.
8. Write limitations and future-work section.
9. Clean code comments and module names where safe.
```

Do not start a major new architecture in the final week.

---

## 7. Recommended Priority

### Highest Priority

```text
1. Freeze current V3.
2. Add pipelined activation gather.
3. Benchmark and compare.
```

### Medium Priority

```text
4. Add packed/faster activation reads.
5. Add weight preload using PE shadow registers.
6. Optimize FC1 drain.
```

### Lower Priority

```text
7. Pooling optimization.
8. Output writeback optimization.
9. Host AXI-Lite optimization.
```

### Do Not Prioritize Before Submission

```text
new dataset
camera input
8×8/16×16 without feed-path redesign
AXI DMA
major tensor layout change
```

---

## 8. Final Thesis Story

A strong final thesis story is:

```text
V2 established a correct 2×2 signed-INT8 CNN accelerator.
V3 scaled the systolic array to 4×4 and reduced cycles/image by 43.3%.
Layer and phase counters showed that performance remains limited by activation fetch and PE underutilization.
The next optimization direction is not simply a larger array, but a better dataflow that feeds the array continuously.
```

Use this conclusion:

```text
The accelerator demonstrates a complete RTL CNN inference pipeline with golden-model correctness, low resource usage, and measurable architectural scaling. The V3 4×4 implementation improves throughput over V2, but remaining PE utilization measurements show that future work should focus on activation gathering, memory bandwidth, and compute/data movement overlap.
```

---

## 9. Definition of Done for the Final Submission

Minimum successful final package:

```text
1. V2 RTL baseline
2. V3 4×4 RTL baseline
3. full correctness logs
4. full benchmark logs
5. utilization reports
6. timing reports
7. power reports
8. V2 vs V3 cycle comparison
9. V2 vs V3 resource comparison
10. bottleneck analysis
11. future-work plan
```

Strong final package:

```text
1. all minimum items
2. activation gather experiment implemented
3. improved V3.1 cycles
4. improved Conv1/Conv2 act_fetch cycles
5. updated resource/timing/power reports
```

Do not sacrifice correctness for performance. Every experiment must preserve:

```text
RTL/golden logits: PASS
accuracy unchanged
no hardware failures
```

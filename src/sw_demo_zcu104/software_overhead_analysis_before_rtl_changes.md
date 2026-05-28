# Software-Side Overhead Analysis Before RTL Changes

## Objective

Before modifying the RTL, quantify exactly where the PS-side overhead comes from.

Current known issue:

```text
784 pixels/image × 4 AXI-Lite transactions/pixel
= 3136 AXI-Lite transactions/image
```

For 10,000 images:

```text
3136 transactions/image × 10000 images
= 31,360,000 AXI-Lite transactions
```

The goal is to prove which software/PS-to-PL section dominates the current end-to-end runtime before redesigning the RTL interface.

---

## Current Bottleneck Hypothesis

Current software flow:

```c
for each image:
    for each pixel:
        tpu_ub_write(pixel_addr, pixel_data);
```

Each `tpu_ub_write()` currently performs:

```text
1. write UB_ADDR
2. write UB_WDATA
3. write UB_CONTROL
4. read STATUS
```

Therefore, input loading alone costs:

```text
784 pixels × 4 AXI-Lite transactions = 3136 AXI-Lite transactions/image
```

This likely explains why:

```text
PL kernel speedup     = 15.63×
PL end-to-end speedup = 2.09×
```

---

## Step 1 — Add Timing Regions in `main.c`

Wrap the complete PL inference loop with timestamp probes.

Measure these regions separately:

```text
1. input preparation / image pointer setup
2. input write to unified buffer
3. accelerator start register writes
4. wait/poll for accelerator done
5. output readback
6. argmax / result comparison
7. total end-to-end time
```

Example structure:

```c
t_total_start = timer_now();

for (int img = 0; img < NUM_IMAGES; img++) {
    t0 = timer_now();

    prepare_input(img);

    t1 = timer_now();

    load_input_to_unified_buffer(img);

    t2 = timer_now();

    tpu_start();

    t3 = timer_now();

    tpu_wait_done();

    t4 = timer_now();

    tpu_read_output(logits);

    t5 = timer_now();

    pred = argmax(logits);
    compare_result(pred, label[img]);

    t6 = timer_now();

    acc_prepare      += t1 - t0;
    acc_input_write  += t2 - t1;
    acc_start        += t3 - t2;
    acc_wait_done    += t4 - t3;
    acc_output_read  += t5 - t4;
    acc_postprocess  += t6 - t5;
}

t_total_end = timer_now();
```

Print only after the benchmark loop finishes.

Do not print inside the per-image loop.

---

## Step 2 — Count AXI-Lite Transactions

Add counters inside `tpu_axi_lite.c`.

For every low-level register write:

```c
axi_write_count++;
```

For every low-level register read:

```c
axi_read_count++;
```

Track transaction categories separately:

```text
UB address writes
UB data writes
UB control writes
UB status reads
accelerator start writes
accelerator status reads
output reads
other reads/writes
```

Expected current result per image:

```text
UB address writes  = 784
UB data writes     = 784
UB control writes  = 784
UB status reads    = 784
Total UB transfers = 3136 transactions/image
```

Expected current result for 10,000 images:

```text
UB address writes  = 7,840,000
UB data writes     = 7,840,000
UB control writes  = 7,840,000
UB status reads    = 7,840,000
Total UB transfers = 31,360,000
```

---

## Step 3 — Measure `tpu_ub_write()` Cost

Create a microbenchmark for only the unified-buffer write function.

Example:

```c
start = timer_now();

for (int i = 0; i < 784; i++) {
    tpu_ub_write(i, image[i]);
}

end = timer_now();

ub_write_time = end - start;
```

Repeat for:

```text
1 image
100 images
1000 images
10000 images
```

Report:

```text
time per tpu_ub_write()
time per image input load
effective input bandwidth
```

Formula:

```text
effective_input_bandwidth = total_bytes_written / input_write_time
```

This will show whether the AXI-Lite write path is the dominant overhead.

---

## Step 4 — Measure Accelerator Wait Time Separately

The RTL cycle counter currently reports:

```text
58494 cycles/image at 100 MHz
```

So the expected accelerator kernel time is:

```text
58494 / 100000000 = 0.00058494 seconds/image
= 0.58494 ms/image
```

The software-measured `tpu_wait_done()` time should be close to this.

If `tpu_wait_done()` is much larger than the RTL cycle-counter result, check for:

```text
usleep()
delay loops
printf inside wait loop
slow status driver calls
cache maintenance inside wait loop
inefficient polling
```

Bad polling example:

```c
while (!done) {
    usleep(1);
}
```

Better benchmarking polling:

```c
while ((Xil_In32(STATUS_REG) & DONE_MASK) == 0) {
    // tight polling
}
```

---

## Step 5 — Remove Benchmark Pollution

The timed region must not include:

```text
printf inside the image loop
file I/O
malloc/free
dataset loading from storage
debug register dumps
UART printing
per-image mismatch printing
heavy cache flush/invalidate unless required
```

Correct benchmark structure:

```text
1. Load dataset before timing starts.
2. Run CPU or PL inference timing loop.
3. Stop timer.
4. Print final summary.
```

---

## Step 6 — Compare CPU and PL Timing Fairly

Use consistent timing rules for both CPU and PL paths.

### CPU Timing Should Include

```text
CPU inference math
argmax
result comparison
```

### CPU Timing Should Exclude

```text
dataset loading
file I/O
debug printing
initialization outside inference loop
```

### PL End-to-End Timing Should Include

```text
input write to PL
accelerator start
wait/done polling
output readback
argmax
result comparison
```

### PL End-to-End Timing Should Exclude

```text
dataset loading
file I/O
debug printing
FPGA programming time
application startup time
```

### PL Kernel Timing Should Use

```text
RTL cycle counter only
start counter at accelerator start
stop counter at accelerator done
```

---

## Step 7 — Create a Software Overhead Table

After instrumentation, produce this table:

| Region | Total Time for 10,000 Images | Time/Image | Percent of End-to-End |
|---|---:|---:|---:|
| Input preparation | TBD | TBD | TBD |
| UB input writes | TBD | TBD | TBD |
| Accelerator start | TBD | TBD | TBD |
| Wait for done | TBD | TBD | TBD |
| Output readback | TBD | TBD | TBD |
| Argmax/compare | TBD | TBD | TBD |
| Total end-to-end | 43,723 ms | 4.3723 ms | 100% |

Expected dominant row:

```text
UB input writes
```

---

## Step 8 — Create an AXI-Lite Transaction Count Table

Produce this table:

| Transaction Type | Count/Image | Count/10,000 Images |
|---|---:|---:|
| UB_ADDR writes | 784 | 7,840,000 |
| UB_WDATA writes | 784 | 7,840,000 |
| UB_CONTROL writes | 784 | 7,840,000 |
| STATUS reads | 784 | 7,840,000 |
| Start/control writes | TBD | TBD |
| Done/status reads | TBD | TBD |
| Output reads | TBD | TBD |
| Other transactions | TBD | TBD |
| Total AXI-Lite transactions | TBD | TBD |

This table will justify the later RTL interface optimization.

---

## Step 9 — Estimate Benefit Before RTL Change

Estimate transaction reduction from alternative software/RTL protocols.

### Current Protocol

```text
784 byte writes × 4 transactions/write
= 3136 transactions/image
```

### Packed 32-Bit Writes Only

Pack 4 signed INT8 pixels into one 32-bit word:

```text
784 pixels / 4 = 196 packed words
```

If each packed write still uses address/data/control/status:

```text
196 word writes × 4 transactions/write
= 784 transactions/image
```

Reduction:

```text
3136 / 784 = 4× fewer transactions
```

### Packed 32-Bit Writes + Auto-Increment Stream

Improved protocol:

```text
1 address write
196 data writes
small control/status overhead
≈ 198 transactions/image
```

Reduction:

```text
3136 / 198 ≈ 15.8× fewer input-load transactions
```

---

## Step 10 — Decide RTL Change Based on Data

Choose the RTL/software optimization only after the timing and transaction data are collected.

| Dominant Bottleneck | Recommended Fix |
|---|---|
| UB input writes dominate | Add 32-bit packed streaming write with auto-increment |
| Polling/wait dominates | Use tighter polling or interrupt |
| Output readback dominates | Move argmax into PL and read only predicted class |
| Start/control dominates | Add batch mode |
| Cache maintenance dominates | Reduce cache operations or use uncached/coherent memory |
| Software copies dominate | Remove extra memory copies and use direct buffers |

---

## Expected First RTL Fix if UB Writes Dominate

If UB writes are confirmed as the dominant bottleneck, implement:

```text
32-bit packed UB stream write
auto-incrementing write address
no per-byte status read
optional small FIFO
4-cycle internal unpacker into existing 8-bit unified buffer
```

Software should change from:

```c
for (int p = 0; p < 784; p++) {
    tpu_ub_write(p, image[p]);
}
```

to:

```c
tpu_ub_stream_begin(0, BANK0);

for (int w = 0; w < 196; w++) {
    uint32_t packed =
        ((uint8_t)image[4*w + 0] << 0)  |
        ((uint8_t)image[4*w + 1] << 8)  |
        ((uint8_t)image[4*w + 2] << 16) |
        ((uint8_t)image[4*w + 3] << 24);

    tpu_ub_stream_write32(packed);
}

tpu_start();
tpu_wait_done();
```

---

## Final Checklist Before RTL Modification

Before changing RTL, produce:

```text
1. timing breakdown table
2. AXI-Lite transaction count table
3. tpu_ub_write() microbenchmark
4. wait_done() timing validation
5. cleaned benchmark loop with no printf/file I/O pollution
6. estimated speedup from packed streaming write
7. clear decision on which RTL interface change gives highest ROI
```

---

## Thesis Explanation Template

Use this explanation in the report after the analysis is complete:

```text
The initial end-to-end implementation used an AXI-Lite byte-wise unified-buffer loading protocol. Each input pixel required four AXI-Lite transactions: address write, data write, control write, and status read. Since each MNIST image contains 784 pixels, input loading required 3136 AXI-Lite transactions per inference. For the 10,000-image test set, this resulted in approximately 31.36 million AXI-Lite transactions. Software-side timing instrumentation and transaction counters were added to quantify this overhead before modifying the RTL interface.
```

---

## Success Criteria

The software analysis is complete when the following are known:

```text
exact time spent in UB input writes
exact time spent waiting for PL done
exact time spent in output readback
exact AXI-Lite transaction count per image
exact AXI-Lite transaction count for 10,000 images
estimated benefit of packed/streaming writes
```

Only after this data is collected should the RTL input interface be modified.

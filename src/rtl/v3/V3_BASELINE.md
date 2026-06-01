# V3 Baseline

This directory starts as a clean copy of the verified V2 RTL plus the required model memory files.

Purpose:

```text
1. Preserve V2 as the known-good baseline.
2. Give V3 its own RTL tree for dataflow changes.
3. Allow compile checks with RTL_VERSION=v3.
```

Current state:

```text
Functionality: same as V2 baseline
Array       : 2x2
Model       : signed symmetric INT8 MNIST CNN
Top wrapper : tpu_top_axi_lite.sv
```

Next V3 implementation step:

```text
Add activation_window_gather_v3.sv and integrate it first at ARRAY_K=2, ARRAY_OC=2.
Do not scale to 4x4 until the improved 2x2 V3 path is correct and faster than V2.
```

Compile check:

```bash
cd src/sim/tb_sa_NxN
make compile TEST=tpu_axi_lite RTL_VERSION=v3
```

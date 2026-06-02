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

First V3 implementation modules:

```text
activation_window_gather_v3.sv
weight_tile_buffer_v3.sv
mxu_v3.sv
tpu_datapath_v3.sv
tpu_controller_v3_tile.sv
tpu_controller_v3_rom_tile.sv
```

This block accepts an activation address vector request, serializes unified-buffer reads, skips padded or invalid lanes, and buffers completed activation vectors behind a ready/valid interface.

The weight tile buffer accepts a flattened weight-address tile plus valid/zero masks, reads only required ROM entries, stores padded/invalid entries as zero, and can repeatedly stream the resident tile rows into the WS systolic-array weight load interface.

The first overlap implementation is inside `weight_tile_buffer_v3.sv` and
`tpu_controller_v3_tile.sv`:

```text
slot A: active tile streamed into WS array for current K tile
slot B: inactive tile filled from ROM for next K tile
```

The controller now issues the next weight request after the current weights have
been streamed into the WS array and before launching the current activation
request. This overlaps next-tile ROM weight fetch with current-tile activation
fetch/compute. The WS array is still protected: prefetched weights are not
streamed into the PEs until the current tile has produced and drained its psums.

Activation prefetch uses a gated launch contract:

```text
activation_window_gather_v3 -> FIFO holds prefetched activation vector
tpu_controller_v3_tile      -> act_launch_o pulse releases the vector
mxu_v3                      -> gated launch feeds skew buffer and WS array
```

With `GATED_ACT_LAUNCH=1`, gathered activations no longer enter the skew buffer
automatically. The controller may request activation `k+1` while current `k`
psums are draining, but it launches that vector only after `k+1` weights are
resident in the WS array.

Important WS-array load contract:

```text
weight_tile_buffer_v3 stores tiles row-major for inspection, but streams rows bottom-to-top.
The existing WS array shifts weights downward during load, so bottom-row-first streaming is required for correct active weights.
```

The first MXU V3 wrapper keeps the proven 2x2 WS systolic array, but replaces the direct activation input and FIFO weight path with the V3 activation gather and resident weight tile buffer. This is a compatibility step before controller/datapath integration.

The first TPU datapath V3 wrapper keeps the proven V2 post-MXU path:

```text
mxu_v3 -> psum_packer_v2 -> accumulator_array_v2 -> vector_processing_unit_v2
```

This validates the new V3 feed path without changing accumulator or VPU behavior.

The first address-generator integration test drives the V3 datapath from
`conv_fc_address_generator.sv` outputs. It uses FC-style `out_ch=16` addressing,
two K tiles, resident weight-tile load/release between tiles, accumulation across
both tiles, then VPU bias/requant/ReLU. This is the bridge between the standalone
V3 datapath and the next controller rewrite.

The first V3 controller wrapper is `tpu_controller_v3_tile.sv`. It controls one
accumulator row for one output-channel tile across all K tiles using request/ready
handshakes:

```text
controller -> weight_tile_buffer_v3 request
controller -> weight stream start
controller -> activation_window_gather_v3 request
controller -> activation launch gate
controller -> accumulator write/read controls
controller -> VPU done/config controls
```

The tile controller keeps a separate weight-request K index so it can request
`k+1` while activation/psum handling still belongs to current `k`.
It also keeps activation request/launch state separate, so an activation vector
can be requested early and launched later.

It deliberately stays separate from `tpu_controller_rom_kloop.sv` while the V3
request path is validated.

`tpu_controller_v3_rom_tile.sv` wraps the V3 tile controller with descriptor ROM,
bias/requant parameter ROM lookup, descriptor/manual bank selection, and two-lane
UB output writeback. Weight ROM reads remain on the V3 datapath side through
`weight_tile_buffer_v3`.

Direct testbench:

```text
src/sim/tb_for_v3/test_activation_window_gather_v3.sv
src/sim/tb_for_v3/test_weight_tile_buffer_v3.sv
src/sim/tb_for_v3/test_mxu_v3_2x2.sv
src/sim/tb_for_v3/test_tpu_datapath_v3.sv
src/sim/tb_for_v3/test_addrgen_tpu_datapath_v3.sv
src/sim/tb_for_v3/test_controller_v3_tile.sv
src/sim/tb_for_v3/test_controller_v3_rom_tile.sv
```

Next V3 integration step:

```text
Integrate activation_window_gather_v3.sv and weight_tile_buffer_v3.sv first at ARRAY_K=2, ARRAY_OC=2.
Do not scale to 4x4 until the improved 2x2 V3 path is correct and faster than V2.
```

Compile check:

```bash
cd src/sim/tb_sa_NxN
make compile TEST=tpu_axi_lite RTL_VERSION=v3

cd ../tb_for_v3
make compile TEST=activation_window_gather
make compile TEST=weight_tile_buffer
make compile TEST=mxu_v3_2x2
make compile TEST=tpu_datapath_v3
make compile TEST=addrgen_tpu_datapath_v3
make compile TEST=controller_v3_tile
make compile TEST=controller_v3_rom_tile
```

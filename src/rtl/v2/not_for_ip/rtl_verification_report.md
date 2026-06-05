# RTL v2 Verification Report

Status date: 2026-05-21

## Numeric Contract

The current RTL path targets the signed symmetric INT8 model export:

```text
activation_q : signed int8
weight_q     : signed int8
bias_q       : signed int32
accumulator  : signed int32
output_q     : signed int8
zero_point   : 0
```

The systolic array performs integer dot products only. Bias addition, fixed-point
requantization, activation, and clamp are handled after accumulation.

## Implemented Dataflow

The verified end-to-end small-CNN flow is:

```text
input -> Conv1 -> Pool1 -> Conv2 -> Pool2 -> FC1 -> FC2 -> logits
```

The top-level schedule is implemented in `top.sv`:

```text
CONV1: bank0 -> bank1
POOL1: bank1 -> bank0
CONV2: bank0 -> bank1
POOL2: bank1 -> bank0
FC1:   bank0 -> bank1
FC2:   bank1 -> bank0
```

## Main RTL Blocks

```text
top.sv
  unified_buffer.sv
  controller_layer.sv
    controller_kloop.sv
      weight_rom.sv
      bias_rom.sv
      requant_mult_rom.sv
      requant_shift_rom.sv
      address_generator.sv
  datapath.sv
    mxu.sv
    psum_packer.sv
    accumulator_array.sv
    vector_processing_unit.sv
  maxpool2d.sv
```

`top_axi_lite.sv` is the first PS-facing wrapper around `top.sv`.
It provides AXI4-Lite control/status and byte-wise unified-buffer access. It is
intended for bring-up and register-level software control, not high-throughput
image transfer.

## AXI4-Lite Register Map

| Offset | Register | Access | Bits |
|---:|---|---|---|
| `0x00` | `CONTROL` | W | bit0 start pulse, bit1 clear overflow flags, bit2 clear sticky status |
| `0x04` | `STATUS` | R | bit0 done sticky, bit1 busy, bit2 error, bit3 overflow, bit4 UB read valid, bit5 command error, bits10:8 stage, bit16 done raw |
| `0x08` | `ERROR` | R | top-level error code |
| `0x0c` | `CYCLES` | R | low 16 bits of top cycle counter |
| `0x10` | `DEBUG0` | R | top state, stage, layer state, layer tile state |
| `0x14` | `DEBUG1` | R | layer spatial index and output-channel tile |
| `0x18` | `DEBUG2` | R | layer K tile and pool channel |
| `0x1c` | `DEBUG3` | R | pool row and pool column |
| `0x20` | `UB_ADDR` | R/W | bit31 bank, low bits byte address |
| `0x24` | `UB_WDATA` | R/W | signed INT8 write data in bits7:0 |
| `0x28` | `UB_RDATA` | R | signed INT8 read data in bits7:0, bit8 read-valid |
| `0x2c` | `UB_CONTROL` | W | bit0 write byte, bit1 read byte |

Unified-buffer reads are synchronous. Software should issue `UB_CONTROL[1]`,
then poll `STATUS[4]` or `UB_RDATA[8]` before consuming `UB_RDATA[7:0]`.

The wrapper intentionally does not implement AXI DMA or AXI4-Stream yet.

## User-Run Simulation Results

The following results were reported from simulation runs.

| Test | Result | Coverage |
|---|---:|---|
| `test_weight_fifo_fetcher_mxu` | `15/15` | Weight FIFO/fetcher load into MXU |
| `test_activation_skew_ws_sa` | `16/16` | Activation stagger plus WS SA compute |
| `test_vpu_post_process` | `36/36` | ReLU, normalize, saturation, bias/requant, pooling modes |
| `test_tpu_datapath_v2` | `30/30` | MXU -> psum packer -> accumulator -> VPU |
| `test_accumulator_array_ws_sa_vpu` | `19/19` | WS SA -> accumulator array -> VPU |
| `test_controller_unified_buffer_v2` | `5/5` | Controller plus unified buffer smoke path |
| `test_rom_load` | `84/84` | Weight, bias, requant, descriptor ROMs |
| `test_conv_fc_address_generator` | `56/56` | Conv/FC addresses, padded K, padded OC masks |
| `test_controller_rom_tile` | `5/5` | ROM-driven single FC2 tile |
| `test_controller_rom_kloop` | `5/5` | ROM-driven full-K FC2 OC tile |
| `test_controller_rom_layer` | `13/13` | Full FC2 logits from FC1 golden vector |
| `test_controller_conv1_pixel` | `8/8` | Conv1 single pixel |
| `test_controller_conv1_layer` | `5412/5412` | Full Conv1 tensor, `5408/5408` output matches |
| `test_maxpool2d_pool1` | `1355/1355` | Full Pool1 tensor, `1352/1352` output matches |
| `test_controller_conv2_layer` | `1214/1214` | Full Conv2 tensor, `1210/1210` output matches |
| `test_maxpool2d_pool2` | `253/253` | Full Pool2 tensor, `250/250` output matches |
| `test_tpu_top_end_to_end` | `13/13` | Full inference logits match golden output |

End-to-end top result:

```text
TOP: done=1 error=0 cycles=386174 err=0x00000000
logits = {-11,-30,22,23,-40,-26,-113,87,9,13}
```

The expected argmax is class `7`.

## Compile/Elaboration Checks

The latest added targets were checked with Vivado `xvlog` and `xelab` only:

```bash
make elaborate TEST=maxpool2d_pool2
make elaborate TEST=tpu_top_e2e
make elaborate TEST=tpu_axi_lite
```

All elaborated successfully.

## Recommended Regression Commands

Focused remaining-flow checks:

```bash
make test_maxpool2d_pool2
make test_tpu_top_e2e
```

Current full integration set:

```bash
make test_rom_load
make test_conv_fc_addr
make test_controller_conv1_layer
make test_maxpool2d_pool1
make test_controller_conv2_layer
make test_maxpool2d_pool2
make test_tpu_top_e2e
```

Lower-level datapath checks:

```bash
make test_weight_fifo_fetcher
make test_activation_skew
make test_vpu_post_process
make test_tpu_datapath
make test_accumulator_array
```

## Current Boundaries

The design is now functionally verified for one signed symmetric INT8 MNIST
golden image and the fixed 4,996-parameter small CNN.

Remaining engineering work:

```text
1. Run synthesis/resource/timing reports.
2. Add AXI DMA or another bulk-transfer path for faster image loading.
3. Add broader image regression tests, not only one golden image.
4. Add a clean build/run README for the v2 flow.
5. Scale the array/controller if moving from 2x2 to 32x32.
6. Keep ROM weights for this model; move to external memory only for larger models.
```

Do not claim this is a production accelerator yet. The current result proves the
RTL inference path and module integration for the fixed MNIST signed INT8 model.

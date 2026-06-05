# RTL v2 Synthesis Readiness Summary

Status date: 2026-05-22

This document summarizes the current signed-INT8 MNIST accelerator RTL, the
testbenches used to verify it, the model artifacts that feed the ROMs and
golden checks, and the files that should be considered for synthesis.

## Current Status

The current 2x2 design is functionally verified in simulation for the fixed
signed symmetric INT8 MNIST model.

Latest user-reported end-to-end regression:

```text
256 real MNIST test images
test_tpu_top_end_to_end: checks=3328 pass=3328 fail=0
```

Verified RTL flow:

```text
host/testbench preload
  -> unified buffer
  -> Conv1
  -> Pool1
  -> Conv2
  -> Pool2
  -> FC1
  -> FC2
  -> final logits
```

The RTL final logits match the Python integer reference logits exactly for the
tested images.

## Numeric Contract

The project now uses a signed symmetric INT8 contract:

| Quantity | Format | Notes |
|---|---:|---|
| input activation | signed INT8 | zero point is 0 |
| intermediate activation | signed INT8 | zero point is 0 |
| weight | signed INT8 | zero point is 0 |
| bias | signed INT32 | per output channel |
| accumulator | signed INT32 | accumulates K tiles |
| requant multiplier | signed INT32 | fixed-point scale |
| requant shift | unsigned 6-bit | right shift after multiply |
| output activation/logit | signed INT8 | clamp to `[-128, 127]` |

The systolic array performs integer dot products only. Bias addition,
requantization, ReLU, normalization, and clamp happen after accumulation in the
VPU/post-processing path.

## Model Specification

Model: `small_cnn_4996_params`

Parameter count:

```text
weights: 4952
biases : 44
total  : 4996 trainable parameters
```

Layer schedule:

| Stage | Operation | Shape | Element count |
|---|---|---:|---:|
| input | input image | `1 x 28 x 28` | 784 |
| Conv1 | `1 -> 8`, `3x3`, ReLU | `8 x 26 x 26` | 5408 |
| Pool1 | maxpool `2x2` | `8 x 13 x 13` | 1352 |
| Conv2 | `8 -> 10`, `3x3`, ReLU | `10 x 11 x 11` | 1210 |
| Pool2 | maxpool `2x2` | `10 x 5 x 5` | 250 |
| FC1 | `250 -> 16`, ReLU | `16` | 16 |
| FC2 | `16 -> 10` | `10` | 10 |

Layer descriptor constants are defined in:

```text
src/rtl/v2/layer_descriptor_pkg.sv
```

Important descriptor values:

| Layer | K total | K tiles | OC tiles | Spatial count | Weight base | Bias base | Requant base | Activation |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Conv1 | 9 | 5 | 4 | 676 | 0 | 0 | 0 | ReLU |
| Conv2 | 72 | 36 | 5 | 121 | 72 | 8 | 8 | ReLU |
| FC1 | 250 | 125 | 8 | 1 | 792 | 18 | 18 | ReLU |
| FC2 | 16 | 8 | 5 | 1 | 4792 | 34 | 34 | bypass |

## Top-Level Dataflow

The final end-to-end top is:

```text
top.sv
  unified_buffer.sv
  controller_layer.sv
    layer_descriptor_rom.sv
    controller_kloop.sv
      address_generator.sv
      weight_rom.sv
      bias_rom.sv
      requant_mult_rom.sv
      requant_shift_rom.sv
  datapath.sv
    mxu.sv
      fifo.sv
      weight_fetcher.sv
      act_skew_buffer.sv
      systolic_array.sv
        pe.sv
          multiplier.sv
    psum_packer.sv
    accumulator_array.sv
    vector_processing_unit.sv
      post_process.sv
        bias_requantize.sv
        activation_array.sv
        normalizer.sv
        pooling_unit.sv
  maxpool2d.sv
```

Bank schedule:

| Stage | Read bank | Write bank |
|---|---:|---:|
| Host preload input | host -> bank0 | bank0 |
| Conv1 | bank0 | bank1 |
| Pool1 | bank1 | bank0 |
| Conv2 | bank0 | bank1 |
| Pool2 | bank1 | bank0 |
| FC1 | bank0 | bank1 |
| FC2 | bank1 | bank0 |
| Host read logits | bank0 | host |

## Synthesis Top Choices

Use one of these top modules depending on the target.

| Top module | Use case |
|---|---|
| `tpu_top` | Pure RTL core with simple host-style UB read/write pins. Best for initial standalone synthesis/resource/timing. |
| `tpu_top_axi_lite` | PS-facing wrapper around `tpu_top` with AXI4-Lite control/status and byte-wise UB access. Best for Zynq/ZCU104 block-design bring-up. |

For a first synthesis pass, use `tpu_top_axi_lite` if the goal is PS software
control. Use `tpu_top` if the goal is only core resource/timing.

## Recommended Synthesis RTL File Set

Include these SystemVerilog RTL files for the current end-to-end design:

```text
src/rtl/v2/layer_descriptor_pkg.sv
src/rtl/v2/top_axi_lite.sv
src/rtl/v2/top.sv
src/rtl/v2/unified_buffer.sv
src/rtl/v2/controller_layer.sv
src/rtl/v2/controller_kloop.sv
src/rtl/v2/layer_descriptor_rom.sv
src/rtl/v2/address_generator.sv
src/rtl/v2/weight_rom.sv
src/rtl/v2/bias_rom.sv
src/rtl/v2/requant_mult_rom.sv
src/rtl/v2/requant_shift_rom.sv
src/rtl/v2/datapath.sv
src/rtl/v2/mxu.sv
src/rtl/v2/fifo.sv
src/rtl/v2/weight_fetcher.sv
src/rtl/v2/act_skew_buffer.sv
src/rtl/v2/systolic_array.sv
src/rtl/v2/pe.sv
src/rtl/v2/multiplier.sv
src/rtl/v2/psum_packer.sv
src/rtl/v2/accumulator_array.sv
src/rtl/v2/vector_processing_unit.sv
src/rtl/v2/post_process.sv
src/rtl/v2/bias_requantize.sv
src/rtl/v2/activation_array.sv
src/rtl/v2/normalizer.sv
src/rtl/v2/pooling_unit.sv
src/rtl/v2/maxpool2d.sv
src/rtl/v2/output_accumulator_v2.sv
```

`output_accumulator_v2.sv` is not active in the current `tpu_datapath_v2`
configuration because `mxu_2x2` is instantiated with local accumulation
disabled, but keeping the file in the synthesis project is harmless.

These RTL files are useful, but are not required by the current final top:

```text
src/rtl/v2/tpu_controller.sv
src/rtl/v2/tpu_controller_rom_tile.sv
src/rtl/v2/ws_sa_3x3.sv
```

These are not RTL synthesis files:

```text
src/rtl/v2/gen_sa.py
src/rtl/v2/rtl_next_steps_ai_agent_instructions.md
src/rtl/v2/rtl_verification_report.md
src/rtl/v2/rtl_synthesis_readiness_summary.md
```

## Required ROM Memory Files

The ROM modules use `$readmemh` initialization. Vivado synthesis can infer ROMs
from these memory files when the paths are available to the project.

| File | Lines | Used by |
|---|---:|---|
| `src/rtl/v2/mem/small_cnn_sym_weights_i8.mem` | 4952 | `weight_rom.sv` |
| `src/rtl/v2/mem/small_cnn_sym_biases_i32.mem` | 44 | `bias_rom.sv` |
| `src/rtl/v2/mem/small_cnn_sym_requant_mult_i32.mem` | 44 | `requant_mult_rom.sv` |
| `src/rtl/v2/mem/small_cnn_sym_requant_shift_u6.mem` | 44 | `requant_shift_rom.sv` |

Path note: the default `INIT_FILE` parameters are relative paths such as:

```text
../../rtl/v2/mem/small_cnn_sym_weights_i8.mem
```

For Vivado project synthesis, confirm the working directory or override
`INIT_FILE` parameters if needed.

## RTL File Inventory

| RTL file | Main role | Current synthesis role |
|---|---|---|
| `layer_descriptor_pkg.sv` | Layer types, shapes, bases, bank schedule constants | Required |
| `layer_descriptor_rom.sv` | Descriptor lookup by layer index | Required |
| `top.sv` | End-to-end CNN sequencer around controller, datapath, UB, pool | Required core top |
| `top_axi_lite.sv` | AXI4-Lite wrapper around `tpu_top` | Required for PS-facing top |
| `unified_buffer.sv` | Two-bank signed INT8 activation/output buffer | Required |
| `controller_layer.sv` | Runs one full layer across spatial blocks and OC tiles | Required |
| `controller_kloop.sv` | Runs one spatial/OC block across all K tiles | Required |
| `address_generator.sv` | Generates activation and weight addresses, masks padded K/OC lanes | Required |
| `weight_rom.sv` | Signed INT8 weight ROM | Required |
| `bias_rom.sv` | Signed INT32 bias ROM | Required |
| `requant_mult_rom.sv` | Signed INT32 requant multiplier ROM | Required |
| `requant_shift_rom.sv` | Unsigned 6-bit requant shift ROM | Required |
| `datapath.sv` | MXU, psum packer, accumulator, VPU datapath shell | Required |
| `mxu.sv` | Weight FIFO/fetcher, activation skew, 2x2 WS SA | Required |
| `fifo.sv` | Simple synchronous FIFO for weight rows | Required |
| `weight_fetcher.sv` | Loads weight rows into WS array | Required |
| `act_skew_buffer.sv` | Staggers activation rows for WS array timing | Required |
| `systolic_array.sv` | 2x2 weight-stationary systolic array | Required |
| `pe.sv` | Processing element | Required |
| `multiplier.sv` | Signed 8x8 multiply | Required |
| `psum_packer.sv` | Collects staggered psum lanes into one row write | Required |
| `accumulator_array.sv` | Accumulates K tiles per row/lane and marks rows ready | Required |
| `vector_processing_unit.sv` | Post-processing wrapper | Required |
| `post_process.sv` | Bias/requant, activation, normalize, lane pooling chain | Required |
| `bias_requantize.sv` | Bias add, fixed-point requant, signed INT8 clamp | Required |
| `activation_array.sv` | ReLU/bypass activation per lane | Required |
| `normalizer.sv` | Optional shift/round normalize stage | Required |
| `pooling_unit.sv` | Temporal lane pooling stage, bypass in top datapath | Required by VPU chain |
| `maxpool2d.sv` | Real 2D Pool1/Pool2 pass over UB tensors | Required |
| `output_accumulator_v2.sv` | Older/local SA output accumulator | Optional support file |
| `tpu_controller.sv` | Earlier non-ROM controller | Not in final top |
| `tpu_controller_rom_tile.sv` | Earlier single-tile ROM controller | Not in final top |
| `ws_sa_3x3.sv` | 3x3 generated systolic array experiment | Not in final top |

## Top-Level Signals

### `tpu_top`

Main control:

| Signal | Direction | Meaning |
|---|---|---|
| `clk` | input | Core clock |
| `rst_n` | input | Active-low reset |
| `start_i` | input | Start full CNN schedule |
| `done_o` | output | Full schedule complete |
| `busy_o` | output | Top is running |
| `error_o` | output | Top-level error |
| `overflow_clr_i` | input | Clear multiplier overflow flags |
| `overflow_flatten_o` | output | Per-PE overflow flags |

Host unified-buffer access:

| Signal | Direction | Meaning |
|---|---|---|
| `host_wr_en_i` | input | Write one signed INT8 byte into UB |
| `host_wr_bank_i` | input | UB bank select for write |
| `host_wr_addr_i` | input | UB byte address for write |
| `host_wr_data_i` | input | Signed INT8 write data |
| `host_rd_en_i` | input | Read one signed INT8 byte from UB |
| `host_rd_bank_i` | input | UB bank select for read |
| `host_rd_addr_i` | input | UB byte address for read |
| `host_rd_data_o` | output | Signed INT8 read data |
| `host_rd_valid_o` | output | Read data valid |

Debug:

| Signal | Meaning |
|---|---|
| `dbg_state_o` | Top FSM state |
| `dbg_stage_o` | `0` idle, `1` Conv1, `2` Pool1, `3` Conv2, `4` Pool2, `5` FC1, `6` FC2 |
| `dbg_cycle_count_o` | Low 16-bit run cycle counter |
| `dbg_error_code_o` | Top error code |
| `dbg_layer_state_o` | Layer controller FSM state |
| `dbg_layer_tile_state_o` | K-loop/tile FSM state |
| `dbg_layer_spatial_o` | Current layer spatial block |
| `dbg_layer_oc_tile_o` | Current output-channel tile |
| `dbg_layer_k_tile_o` | Current K tile |
| `dbg_pool_state_o` | 2D pool FSM state |
| `dbg_pool_channel_o` | Current pool channel |
| `dbg_pool_row_o` | Current pool output row |
| `dbg_pool_col_o` | Current pool output column |

### `tpu_top_axi_lite`

AXI4-Lite pins:

```text
s_axi_aclk
s_axi_aresetn
s_axi_awaddr, s_axi_awvalid, s_axi_awready
s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready
s_axi_bresp, s_axi_bvalid, s_axi_bready
s_axi_araddr, s_axi_arvalid, s_axi_arready
s_axi_rdata, s_axi_rresp, s_axi_rvalid, s_axi_rready
```

Register map:

| Offset | Register | Access | Fields |
|---:|---|---|---|
| `0x00` | `CONTROL` | W | bit0 start pulse, bit1 clear overflow, bit2 clear sticky status |
| `0x04` | `STATUS` | R | bit0 done sticky, bit1 busy, bit2 error, bit3 overflow, bit4 UB read valid, bit5 command error, bits10:8 stage, bit16 done raw |
| `0x08` | `ERROR` | R | top-level error code |
| `0x0c` | `CYCLES` | R | low 16 bits of cycle counter |
| `0x10` | `DEBUG0` | R | top state, stage, layer state, layer tile state |
| `0x14` | `DEBUG1` | R | layer spatial index and OC tile |
| `0x18` | `DEBUG2` | R | layer K tile and pool channel |
| `0x1c` | `DEBUG3` | R | pool row and pool column |
| `0x20` | `UB_ADDR` | R/W | bit31 bank, low bits byte address |
| `0x24` | `UB_WDATA` | R/W | signed INT8 write data in bits7:0 |
| `0x28` | `UB_RDATA` | R | signed INT8 read data in bits7:0, bit8 read-valid |
| `0x2c` | `UB_CONTROL` | W | bit0 write byte, bit1 read byte |

AXI wrapper limitation: current wrapper is a correctness-first bring-up
interface with byte-wise UB access. It is not a high-throughput DMA path.

## Internal Datapath Signals

Important controller-to-datapath signals:

| Signal | Meaning |
|---|---|
| `work_o/work_i` | Enables MXU compute work |
| `num_tiles_o/num_tiles_i` | Number of K tiles for the current dot product |
| `start_wgt_load_o/start_wgt_load_i` | Begins loading stationary weights into SA |
| `wgt_fifo_wdata_o` | Packed two-lane signed INT8 weight row |
| `wgt_fifo_wr_en_o` | Weight FIFO write enable |
| `wgt_fetcher_ready_i` | Fetcher can accept a new weight-load sequence |
| `wgt_load_done_i` | Per-row weight load done flags |
| `act_flat_raw_o` | Packed two-lane signed INT8 activation input |
| `act_valid_raw_o` | Per-lane activation valid |

Accumulator/VPU control:

| Signal | Meaning |
|---|---|
| `accumulator_clear_all_o` | Clears all accumulator rows |
| `accumulator_row_clear_o` | Clears one accumulator row |
| `accumulator_write_en_o` | Enables psum packer capture/write |
| `accumulator_write_addr_o` | Accumulator row address for current spatial block |
| `accumulator_read_en_o` | Reads accumulated row into VPU |
| `accumulator_row_ready_i` | Row is fully accumulated across K tiles |
| `vpu_input_done_o` | Marks final VPU input for a block |
| `vpu_act_mode_o` | ReLU or bypass |
| `vpu_bias_flatten_o` | Per-lane bias |
| `vpu_requant_multiplier_flatten_o` | Per-lane fixed-point multiplier |
| `vpu_requant_shift_flatten_o` | Per-lane fixed-point shift |
| `vpu_data_flatten_i` | Packed signed INT8 VPU output |
| `vpu_data_valid_i` | VPU output valid |

## Testbench Inventory

All testbenches are simulation-only and must not be included in synthesis.

| Testbench | Make target | Purpose | Latest known result |
|---|---|---|---|
| `test_weight_fifo_fetcher_mxu.sv` | `make test_weight_fifo_fetcher` | Weight FIFO/fetcher load into MXU/SA | `15/15` |
| `test_activation_skew_ws_sa.sv` | `make test_activation_skew` | Activation row skew plus WS SA compute | `16/16` |
| `test_vpu_post_process.sv` | `make test_vpu_post_process` | ReLU, normalize, saturation, bias/requant, pooling modes | `36/36` |
| `test_accumulator_array_ws_sa_vpu.sv` | `make test_accumulator_array` | WS SA -> accumulator array -> VPU | `19/19` |
| `test_datapath.sv` | `make test_tpu_datapath` | MXU -> psum packer -> accumulator -> VPU | `30/30` |
| `test_controller_unified_buffer_v2.sv` | `make test_controller_buffer` | Controller and unified buffer smoke path | `5/5` |
| `test_rom_load.sv` | `make test_rom_load` | Weight/bias/requant/descriptor ROM offsets | `84/84` |
| `test_address_generator.sv` | `make test_conv_fc_addr` | Conv/FC address generation and padding masks | `56/56` |
| `test_controller_rom_tile.sv` | `make test_controller_rom_tile` | ROM-driven FC2 single tile | `5/5` |
| `test_controller_rom_kloop.sv` | `make test_controller_rom_kloop` | ROM-driven full-K FC2 OC tile | `5/5` |
| `test_controller_rom_layer.sv` | `make test_controller_rom_layer` | Full FC2 layer logits | `13/13` |
| `test_controller_conv1_pixel.sv` | `make test_controller_conv1_pixel` | Conv1 single output pixel | `8/8` |
| `test_controller_conv1_layer.sv` | `make test_controller_conv1_layer` | Full Conv1 output tensor | `5412/5412` |
| `test_maxpool2d_pool1.sv` | `make test_maxpool2d_pool1` | Full Pool1 tensor | `1355/1355` |
| `test_controller_conv2_layer.sv` | `make test_controller_conv2_layer` | Full Conv2 output tensor | `1214/1214` |
| `test_maxpool2d_pool2.sv` | `make test_maxpool2d_pool2` | Full Pool2 tensor | `253/253` |
| `test_tpu_top_end_to_end.sv` | `make test_tpu_top_e2e` | Built-in full-top cases | `52/52` |
| `test_tpu_top_end_to_end.sv` | `make test_tpu_top_e2e_mnist_txt` | Real MNIST text-image E2E regression | `3328/3328` for 256 images |
| `test_tpu_top_axi_lite_compile.sv` | `make test_tpu_axi_lite` | AXI wrapper compile/elaboration harness | Elaborates |
| `test_sa_2x2_computation.sv` | `make test_sa_2x2` | Older/direct SA compute test | Lower-level |
| `test_staggered_activation.sv` | `make test_staggered_activation` | Older stagger helper test | Lower-level |
| `test_weight_double_buffer.sv` | `make test_weight_double_buffer` | Older weight buffer test | Lower-level |
| `tb_sa_NxN.sv` | none current | Older generic SA testbench | Legacy |

Useful commands:

```bash
cd src/sim/tb_sa_NxN
make test_rom_load
make test_conv_fc_addr
make test_tpu_datapath
make test_tpu_top_e2e
make test_tpu_top_e2e_mnist_txt MNIST_TXT_COUNT=256
make elaborate TEST=tpu_axi_lite
```

## Model and Golden Files

Signed symmetric model artifacts:

```text
CNN_model/python/mnist_classification/18_05/small_cnn_sym_weights_i8_c_order.txt
CNN_model/python/mnist_classification/18_05/small_cnn_sym_biases_i32_c_order.txt
CNN_model/python/mnist_classification/18_05/small_cnn_sym_requant_mult_i32_c_order.txt
CNN_model/python/mnist_classification/18_05/small_cnn_sym_requant_shift_u6_c_order.txt
CNN_model/python/mnist_classification/18_05/small_cnn_sym_qparams.txt
CNN_model/python/mnist_classification/18_05/reference_infer_int.py
```

Layer/debug golden files:

```text
CNN_model/python/mnist_classification/18_05/input_image_i8.hex
CNN_model/python/mnist_classification/18_05/layer0_conv_acc_i32.hex
CNN_model/python/mnist_classification/18_05/layer0_out_i8.hex
CNN_model/python/mnist_classification/18_05/layer1_conv_acc_i32.hex
CNN_model/python/mnist_classification/18_05/layer1_out_i8.hex
CNN_model/python/mnist_classification/18_05/layer2_fc_acc_i32.hex
CNN_model/python/mnist_classification/18_05/layer2_out_i8.hex
CNN_model/python/mnist_classification/18_05/layer3_fc_acc_i32.hex
CNN_model/python/mnist_classification/18_05/final_logits_i8.hex
```

E2E generated regression files:

```text
CNN_model/python/mnist_classification/18_05/e2e_cases/tpu_top_e2e_inputs_i8.hex
CNN_model/python/mnist_classification/18_05/e2e_cases/tpu_top_e2e_logits_i8.hex
CNN_model/python/mnist_classification/18_05/e2e_cases/manifest.txt
CNN_model/python/mnist_classification/18_05/e2e_cases/case_count.txt
```

Generator:

```text
CNN_model/python/mnist_classification/18_05/make_tpu_top_e2e_cases.py
```

The generator supports the real MNIST text files:

```text
/home/pah/Pictures/mnist_data_txt/mnist_images.txt
/home/pah/Pictures/mnist_data_txt/mnist_labels.txt
```

It converts `uint8 0..255` pixels into the signed INT8 input contract using
`activation_scale.input` from `small_cnn_sym_qparams.txt`, then computes golden
logits with `reference_infer_int.py`.

## Current Limits Before Hardware Bring-Up

What is verified:

```text
2x2 signed INT8 RTL datapath
ROM-driven layer controller
Unified buffer ping-pong schedule
2D maxpool passes
Full top-level MNIST inference
Exact final-logit agreement for 256 real MNIST images
```

What is not yet proven:

```text
FPGA synthesis resource utilization
FPGA timing closure
AXI software driver behavior on PS
High-throughput image loading
All 10000 MNIST test images
32x32 systolic-array scaling
```

## Recommended Next Synthesis Steps

1. Create a Vivado project or TCL flow with `tpu_top_axi_lite` as top for PS
   integration, or `tpu_top` as top for core-only synthesis.
2. Add the recommended RTL file set and the four `.mem` ROM init files.
3. Confirm Vivado resolves the ROM `INIT_FILE` paths.
4. Run synthesis, utilization, and timing reports.
5. If targeting ZCU104 PS control, connect `tpu_top_axi_lite` to AXI interconnect
   and map the register region.
6. Keep byte-wise UB access for first hardware correctness. Add DMA only after
   register-level bring-up works.


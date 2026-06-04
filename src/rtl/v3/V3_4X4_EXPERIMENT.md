# V3 4x4 Experiment

V3 has been reset to the V2 RTL baseline. The previous V3 request/gather,
weight-tile, and spatial-block controller experiment is paused and removed from
this RTL folder.

The new V3 purpose is to test whether increasing the systolic array from 2x2 to
4x4 can reduce the full MNIST inference cycle count below the V2 baseline of
about 386k cycles per image.

## Important Constraint

The V2 RTL is not yet a true drop-in `SIZE=4` design.

Several files are parameterized by `SIZE`, but the controller and compute path
still contain 2x2 scheduling assumptions:

- `tpu_controller_rom_kloop.sv`
  - Checks `SIZE != 2` and errors out.
  - Fetches only activation lane 0 and lane 1.
  - Writes only bottom/top weight rows.
  - Writes only output lane 0 and lane 1.
- `mxu_2x2.sv`
  - Instantiates `wgt_fetcher_2x2`, `act_skew_buffer_2x2`, and `ws_sa_2x2`.
- `ws_sa_2x2.sv`
  - Contains fixed 2x2 PE wiring.
- `wgt_fetcher_2x2.sv`
  - Can count rows by `SIZE`, but the upstream controller only feeds two rows.

Therefore, setting top-level `SIZE=4` alone is not a valid experiment. It would
either error out or stall during weight load.

## Required 4x4 Work

1. Generalize or replace `ws_sa_2x2.sv` with a 4x4 systolic array.
2. Generalize or replace `wgt_fetcher_2x2.sv` so it loads four weight rows.
3. Reuse `act_skew_buffer_2x2` only if its generic `SIZE` behavior is verified;
   otherwise create a 4-lane activation skew buffer.
4. Update `mxu_2x2.sv` or create a new MXU wrapper for 4x4.
5. Update `tpu_controller_rom_kloop.sv` to:
   - fetch four activation lanes,
   - write four weight rows,
   - accept four output lanes,
   - support four output channels per OC tile,
   - remove the `SIZE != 2` runtime error.
6. Update VPU/output writeback for four lanes.
7. Update or add 4x4 tests before running full end-to-end.

## Expected Cycle Impact

If the 4x4 path is implemented correctly:

- K tiles become `ceil(K/4)` instead of `ceil(K/2)`.
- OC tiles become `ceil(out_channels/4)` instead of `ceil(out_channels/2)`.
- Conv2 and FC1 should benefit the most.

The real speedup may be limited by unified-buffer read bandwidth because the
current controller reads activation lanes serially.

## Initial Validation Order

1. Compile reset V3 as V2-equivalent with `RTL_VERSION=v3`.
2. Add a focused 4x4 systolic-array test.
3. Add a focused 4-row weight-load test.
4. Add a focused 4-lane activation/skew test.
5. Add a focused 4x4 MXU test.
6. Update K-loop controller and run Conv1/Conv2 layer tests.
7. Run full top end-to-end and compare cycle count against about 386k cycles.

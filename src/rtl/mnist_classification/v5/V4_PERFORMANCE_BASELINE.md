# V4 Performance Baseline

V4 starts from the proven V2 RTL, not from the experimental V3 spatial-block path.

## Reason

Measured behavior showed that V2 is still the fastest complete design:

- V2 full inference: about 386k cycles per image.
- V2 Conv1: about 136k cycles.
- V3 spatial-block Conv1 prototype: about 350k cycles.

The V3 work is paused. V4 should improve the V2 datapath and controller directly.

## Baseline Source

This folder was forked from `src/rtl/v2` synthesizable/IP-ready files.

The module names intentionally remain mostly `*_v2` for now. Rename a module only
when its behavior meaningfully changes, so comparisons against V2 stay clear.

## Initial V4 Targets

1. Preserve V2 correctness and signed symmetric INT8 behavior.
2. Add or keep useful counters only if they do not affect the critical path.
3. Identify V2 layer bottlenecks with phase counters.
4. Optimize the existing V2 schedule before replacing datapath blocks.
5. Prove each optimization layer-by-layer before moving to full top-level tests.

## First Optimization Candidates

- Reduce controller idle/drain cycles in `controller_layer.sv`.
- Reduce repeated activation and weight sequencing bubbles in `controller_kloop.sv`.
- Check whether accumulator read/VPU/output-write sequencing can overlap with the next tile.
- Keep `maxpool2d.sv` as the external full-layer pooling path.

## Do Not Carry Forward Yet

- V3 spatial-block controller.
- V3 activation gather path.
- V3 weight tile buffer path.
- V3 request/launch controller rewrite.

These can be revisited only if a focused test proves they beat the V2 schedule.

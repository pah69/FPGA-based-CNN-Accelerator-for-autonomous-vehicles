"""Bit-oriented signed INT8 golden inference for exported Animals-10 Student A."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from animals10_common import load_json, read_hex_file, write_hex_file


def round_shift(values: np.ndarray, shift: int) -> np.ndarray:
    values = np.asarray(values, dtype=np.int64)
    if shift == 0:
        return values
    offset = np.int64(1 << (shift - 1))
    return np.where(values >= 0, (values + offset) >> shift, (values - offset) >> shift)


def requantize_i8(
    acc_i32: np.ndarray,
    bias_i32: np.ndarray,
    multiplier_i32: np.ndarray,
    shift_i8: np.ndarray,
    relu: bool,
) -> np.ndarray:
    acc = np.asarray(acc_i32, dtype=np.int64)
    channel_shape = (-1,) + (1,) * (acc.ndim - 1)
    bias = np.asarray(bias_i32, dtype=np.int64).reshape(channel_shape)
    mult = np.asarray(multiplier_i32, dtype=np.int64).reshape(channel_shape)
    shifts = np.asarray(shift_i8, dtype=np.int64).reshape(-1)
    scaled = np.empty_like(acc, dtype=np.int64)

    product = (acc + bias) * mult
    for channel, shift in enumerate(shifts):
        scaled[channel] = round_shift(product[channel], int(shift))

    clipped = np.clip(scaled, -128, 127)
    if relu:
        clipped = np.maximum(clipped, 0)
    return clipped.astype(np.int8)


def conv2d_acc_i32(input_i8: np.ndarray, weight_i8: np.ndarray, padding: int) -> np.ndarray:
    x = np.asarray(input_i8, dtype=np.int32)
    w = np.asarray(weight_i8, dtype=np.int32)
    if padding:
        x = np.pad(x, ((0, 0), (padding, padding), (padding, padding)), mode="constant")
    kh, kw = w.shape[2], w.shape[3]
    windows = np.lib.stride_tricks.sliding_window_view(x, (kh, kw), axis=(1, 2))
    return np.tensordot(w, windows, axes=([1, 2, 3], [0, 3, 4])).astype(np.int32)


def maxpool2d_i8(input_i8: np.ndarray) -> np.ndarray:
    x = np.asarray(input_i8, dtype=np.int8)
    channels, height, width = x.shape
    out_h, out_w = height // 2, width // 2
    x = x[:, : out_h * 2, : out_w * 2]
    return x.reshape(channels, out_h, 2, out_w, 2).max(axis=(2, 4)).astype(np.int8)


def round_divide(values: np.ndarray, divisor: int) -> np.ndarray:
    values = np.asarray(values, dtype=np.int64)
    offset = divisor // 2
    return np.where(values >= 0, (values + offset) // divisor, (values - offset) // divisor)


def global_average_pool_i8(input_i8: np.ndarray) -> np.ndarray:
    x = np.asarray(input_i8, dtype=np.int32)
    divisor = x.shape[1] * x.shape[2]
    pooled = round_divide(x.sum(axis=(1, 2), dtype=np.int64), divisor)
    return np.clip(pooled, -128, 127).astype(np.int8)


def dense_acc_i32(input_i8: np.ndarray, weight_i8: np.ndarray) -> np.ndarray:
    return (np.asarray(weight_i8, dtype=np.int32) @ np.asarray(input_i8, dtype=np.int32)).astype(np.int32)


def _slice(values: np.ndarray, offset: int, count: int) -> np.ndarray:
    return values[offset : offset + count]


def load_exported_state(export_dir: str | Path) -> dict[str, Any]:
    export_dir = Path(export_dir)
    config = load_json(export_dir / "animals10_model_config.json")
    layers = load_json(export_dir / "animals10_layer_shapes.json")["layers"]
    weights = np.asarray(read_hex_file(export_dir / "animals10_weights_i8.hex", 8), dtype=np.int8)
    biases = np.asarray(read_hex_file(export_dir / "animals10_bias_i32.hex", 32), dtype=np.int32)
    mults = np.asarray(read_hex_file(export_dir / "animals10_requant_mult_i32.hex", 32), dtype=np.int32)
    shifts = np.asarray(read_hex_file(export_dir / "animals10_requant_shift_i8.hex", 8), dtype=np.int8)
    return {
        "config": config,
        "layers": layers,
        "weights": weights,
        "biases": biases,
        "mults": mults,
        "shifts": shifts,
    }


def infer_i8(state: dict[str, Any], input_i8_chw: np.ndarray) -> tuple[int, dict[str, np.ndarray]]:
    x = np.asarray(input_i8_chw, dtype=np.int8)
    debug: dict[str, np.ndarray] = {"layer_00_input_i8": x.copy()}

    for layer in state["layers"]:
        layer_type = layer["type"]
        name = layer["name"]
        if layer_type == "conv":
            weight = _slice(state["weights"], layer["weight_offset"], layer["weight_count"]).reshape(layer["weight_shape"])
            bias = _slice(state["biases"], layer["bias_offset"], layer["output_c"])
            mult = _slice(state["mults"], layer["requant_offset"], layer["output_c"])
            shift = _slice(state["shifts"], layer["requant_offset"], layer["output_c"])
            acc = conv2d_acc_i32(x, weight, padding=layer["padding"])
            x = requantize_i8(acc, bias, mult, shift, relu=layer["activation"] == "relu")
            debug[f"{name}_acc_i32"] = acc
            debug[f"{name}_out_i8"] = x.copy()
        elif layer_type == "maxpool":
            x = maxpool2d_i8(x)
            debug[f"{name}_out_i8"] = x.copy()
        elif layer_type == "gap":
            x = global_average_pool_i8(x)
            debug[f"{name}_out_i8"] = x.copy()
        elif layer_type == "dense":
            weight = _slice(state["weights"], layer["weight_offset"], layer["weight_count"]).reshape(layer["weight_shape"])
            bias = _slice(state["biases"], layer["bias_offset"], layer["output_features"])
            mult = _slice(state["mults"], layer["requant_offset"], layer["output_features"])
            shift = _slice(state["shifts"], layer["requant_offset"], layer["output_features"])
            acc = dense_acc_i32(x.reshape(-1), weight)
            x = requantize_i8(acc, bias, mult, shift, relu=layer["activation"] == "relu")
            debug[f"{name}_acc_i32"] = acc
            debug[f"{name}_out_i8"] = x.copy()
        else:
            raise ValueError(f"Unsupported layer type: {layer_type}")

    debug["final_logits_i8"] = x.reshape(-1).copy()
    return int(np.argmax(debug["final_logits_i8"])), debug


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Animals-10 exported INT8 golden inference.")
    parser.add_argument("--export-dir", default=".")
    parser.add_argument("--input-hex", default="animals10_test_inputs_i8.hex")
    parser.add_argument("--case-index", type=int, default=0)
    parser.add_argument("--dump-debug", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    export_dir = Path(args.export_dir)
    state = load_exported_state(export_dir)
    input_shape = tuple(state["config"]["input_shape_chw"])
    input_count = int(np.prod(input_shape))
    flat_inputs = np.asarray(read_hex_file(export_dir / args.input_hex, 8), dtype=np.int8)
    start = args.case_index * input_count
    stop = start + input_count
    if stop > flat_inputs.size:
        raise ValueError(f"case-index={args.case_index} is outside {args.input_hex}")
    input_i8 = flat_inputs[start:stop].reshape(input_shape)
    prediction, debug = infer_i8(state, input_i8)
    logits = debug["final_logits_i8"].reshape(-1)
    print(f"prediction={prediction}")
    print("final_logits_i8=" + " ".join(str(int(value)) for value in logits))
    if args.dump_debug:
        debug_dir = export_dir / "debug_case0"
        debug_dir.mkdir(parents=True, exist_ok=True)
        for name, values in debug.items():
            bits = 32 if name.endswith("_i32") else 8
            write_hex_file(debug_dir / f"{name}.hex", values, bits)
            np.save(debug_dir / f"{name}.npy", values)


if __name__ == "__main__":
    main()


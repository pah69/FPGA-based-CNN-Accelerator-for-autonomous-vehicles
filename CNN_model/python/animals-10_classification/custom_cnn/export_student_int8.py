"""Fold BN, calibrate, quantize, and export Student A for RTL."""

from __future__ import annotations

import argparse
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

from animals10_common import (
    CLASS_NAMES,
    STUDENT_INPUT_SIZE,
    ensure_dir,
    load_checkpoint_state,
    save_json,
    write_hex_file,
    write_txt_file,
)
from animals10_data import build_animals10_loaders
from animals10_models import StudentCNNVersionA, fold_student_a
from reference_infer_int import infer_i8, load_exported_state


COMPUTE_LAYER_NAMES = ["conv1", "conv2", "conv3", "conv4", "conv5", "conv6", "fc1", "fc2"]


def symmetric_scale(max_abs: float) -> float:
    if max_abs <= 0.0:
        return 1.0 / 127.0
    return float(max_abs) / 127.0


def quantize_int8(values: np.ndarray, scale: np.ndarray | float) -> np.ndarray:
    q = np.rint(values.astype(np.float64) / scale)
    return np.clip(q, -128, 127).astype(np.int8)


def fixed_point_params(real_multiplier: float) -> tuple[int, int]:
    if real_multiplier <= 0:
        raise ValueError(f"real_multiplier must be positive, got {real_multiplier}")
    for shift in range(31, -1, -1):
        multiplier = int(round(real_multiplier * (1 << shift)))
        if 0 < multiplier <= 0x7FFFFFFF:
            return multiplier, shift
    raise ValueError(f"real_multiplier is too small to encode: {real_multiplier}")


def collect_activation_maxima(model, loader, device: torch.device, batches: int) -> OrderedDict[str, float]:
    maxima: OrderedDict[str, float] = OrderedDict(
        [
            ("input", 0.0),
            ("b1_relu1", 0.0),
            ("b1_relu2", 0.0),
            ("pool1", 0.0),
            ("b2_relu1", 0.0),
            ("b2_relu2", 0.0),
            ("pool2", 0.0),
            ("b3_relu1", 0.0),
            ("b3_relu2", 0.0),
            ("pool3", 0.0),
            ("gap", 0.0),
            ("fc1_relu", 0.0),
            ("logits", 0.0),
        ]
    )
    model.eval()
    with torch.inference_mode():
        for batch_idx, (images, _labels) in enumerate(loader):
            if batch_idx >= batches:
                break
            images = images.to(device, non_blocking=True)
            trace = model.forward_trace(images)
            for name in maxima:
                value = trace[name].detach().abs().amax().item()
                maxima[name] = max(maxima[name], float(value))
    return maxima


def conv_weight_to_oihw(conv: torch.nn.Conv2d) -> np.ndarray:
    return conv.weight.detach().cpu().numpy().astype(np.float64)


def dense_weight_to_oi(fc: torch.nn.Linear) -> np.ndarray:
    return fc.weight.detach().cpu().numpy().astype(np.float64)


def bias_to_numpy(module: torch.nn.Module) -> np.ndarray:
    bias = module.bias
    if bias is None:
        return np.zeros(module.weight.shape[0], dtype=np.float64)
    return bias.detach().cpu().numpy().astype(np.float64)


def quantize_layer(
    name: str,
    weight_float: np.ndarray,
    bias_float: np.ndarray,
    input_scale: float,
    output_scale: float,
) -> dict[str, Any]:
    if weight_float.ndim == 4:
        reduce_axes = (1, 2, 3)
        reshape = (-1, 1, 1, 1)
    elif weight_float.ndim == 2:
        reduce_axes = (1,)
        reshape = (-1, 1)
    else:
        raise ValueError(f"Unsupported weight shape for {name}: {weight_float.shape}")

    weight_max = np.max(np.abs(weight_float), axis=reduce_axes)
    weight_scales = np.asarray([symmetric_scale(value) for value in weight_max], dtype=np.float64)
    weight_i8 = quantize_int8(weight_float, weight_scales.reshape(reshape))
    bias_i32 = np.rint(bias_float / (input_scale * weight_scales)).astype(np.int32)

    multipliers: list[int] = []
    shifts: list[int] = []
    for weight_scale in weight_scales:
        multiplier, shift = fixed_point_params((input_scale * float(weight_scale)) / output_scale)
        multipliers.append(multiplier)
        shifts.append(shift)

    return {
        "name": name,
        "weight_i8": weight_i8,
        "bias_i32": bias_i32,
        "requant_mult_i32": np.asarray(multipliers, dtype=np.int32),
        "requant_shift_i8": np.asarray(shifts, dtype=np.int8),
        "weight_scales": weight_scales,
        "input_scale": input_scale,
        "output_scale": output_scale,
    }


def build_layer_exports(model, activation_scales: dict[str, float]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    modules = model.features._modules
    quant_layers = [
        quantize_layer("conv1", conv_weight_to_oihw(modules["b1_conv1"]), bias_to_numpy(modules["b1_conv1"]), activation_scales["input"], activation_scales["b1_relu1"]),
        quantize_layer("conv2", conv_weight_to_oihw(modules["b1_conv2"]), bias_to_numpy(modules["b1_conv2"]), activation_scales["b1_relu1"], activation_scales["b1_relu2"]),
        quantize_layer("conv3", conv_weight_to_oihw(modules["b2_conv1"]), bias_to_numpy(modules["b2_conv1"]), activation_scales["b1_relu2"], activation_scales["b2_relu1"]),
        quantize_layer("conv4", conv_weight_to_oihw(modules["b2_conv2"]), bias_to_numpy(modules["b2_conv2"]), activation_scales["b2_relu1"], activation_scales["b2_relu2"]),
        quantize_layer("conv5", conv_weight_to_oihw(modules["b3_conv1"]), bias_to_numpy(modules["b3_conv1"]), activation_scales["b2_relu2"], activation_scales["b3_relu1"]),
        quantize_layer("conv6", conv_weight_to_oihw(modules["b3_conv2"]), bias_to_numpy(modules["b3_conv2"]), activation_scales["b3_relu1"], activation_scales["b3_relu2"]),
        quantize_layer("fc1", dense_weight_to_oi(model.fc1), bias_to_numpy(model.fc1), activation_scales["pool3"], activation_scales["fc1_relu"]),
        quantize_layer("fc2", dense_weight_to_oi(model.fc2), bias_to_numpy(model.fc2), activation_scales["fc1_relu"], activation_scales["logits"]),
    ]

    descriptors: list[dict[str, Any]] = []
    weight_offset = 0
    bias_offset = 0
    requant_offset = 0

    def append_compute_descriptor(base: dict[str, Any], layer: dict[str, Any]) -> None:
        nonlocal weight_offset, bias_offset, requant_offset
        out_count = int(layer["bias_i32"].size)
        weight_count = int(layer["weight_i8"].size)
        descriptor = {
            **base,
            "weight_offset": weight_offset,
            "weight_count": weight_count,
            "bias_offset": bias_offset,
            "requant_offset": requant_offset,
        }
        descriptors.append(descriptor)
        weight_offset += weight_count
        bias_offset += out_count
        requant_offset += out_count

    append_compute_descriptor(
        {
            "name": "conv1",
            "type": "conv",
            "input_shape": [3, 64, 64],
            "output_shape": [32, 64, 64],
            "input_c": 3,
            "output_c": 32,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [32, 3, 3, 3],
        },
        quant_layers[0],
    )
    append_compute_descriptor(
        {
            "name": "conv2",
            "type": "conv",
            "input_shape": [32, 64, 64],
            "output_shape": [32, 64, 64],
            "input_c": 32,
            "output_c": 32,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [32, 32, 3, 3],
        },
        quant_layers[1],
    )
    descriptors.append({"name": "pool1", "type": "maxpool", "input_shape": [32, 64, 64], "output_shape": [32, 32, 32]})
    append_compute_descriptor(
        {
            "name": "conv3",
            "type": "conv",
            "input_shape": [32, 32, 32],
            "output_shape": [64, 32, 32],
            "input_c": 32,
            "output_c": 64,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [64, 32, 3, 3],
        },
        quant_layers[2],
    )
    append_compute_descriptor(
        {
            "name": "conv4",
            "type": "conv",
            "input_shape": [64, 32, 32],
            "output_shape": [64, 32, 32],
            "input_c": 64,
            "output_c": 64,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [64, 64, 3, 3],
        },
        quant_layers[3],
    )
    descriptors.append({"name": "pool2", "type": "maxpool", "input_shape": [64, 32, 32], "output_shape": [64, 16, 16]})
    append_compute_descriptor(
        {
            "name": "conv5",
            "type": "conv",
            "input_shape": [64, 16, 16],
            "output_shape": [128, 16, 16],
            "input_c": 64,
            "output_c": 128,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [128, 64, 3, 3],
        },
        quant_layers[4],
    )
    append_compute_descriptor(
        {
            "name": "conv6",
            "type": "conv",
            "input_shape": [128, 16, 16],
            "output_shape": [128, 16, 16],
            "input_c": 128,
            "output_c": 128,
            "kernel_h": 3,
            "kernel_w": 3,
            "padding": 1,
            "activation": "relu",
            "weight_shape": [128, 128, 3, 3],
        },
        quant_layers[5],
    )
    descriptors.append({"name": "pool3", "type": "maxpool", "input_shape": [128, 16, 16], "output_shape": [128, 8, 8]})
    descriptors.append({"name": "gap", "type": "gap", "input_shape": [128, 8, 8], "output_shape": [128]})
    append_compute_descriptor(
        {
            "name": "fc1",
            "type": "dense",
            "input_features": 128,
            "output_features": 128,
            "input_shape": [128],
            "output_shape": [128],
            "activation": "relu",
            "weight_shape": [128, 128],
        },
        quant_layers[6],
    )
    append_compute_descriptor(
        {
            "name": "fc2",
            "type": "dense",
            "input_features": 128,
            "output_features": 10,
            "input_shape": [128],
            "output_shape": [10],
            "activation": "none",
            "weight_shape": [10, 128],
        },
        quant_layers[7],
    )
    return quant_layers, descriptors


def write_export_files(out_dir: Path, quant_layers: list[dict[str, Any]], descriptors: list[dict[str, Any]], activation_scales: dict[str, float]) -> None:
    weights = np.concatenate([layer["weight_i8"].reshape(-1) for layer in quant_layers])
    biases = np.concatenate([layer["bias_i32"].reshape(-1) for layer in quant_layers])
    mults = np.concatenate([layer["requant_mult_i32"].reshape(-1) for layer in quant_layers])
    shifts = np.concatenate([layer["requant_shift_i8"].reshape(-1) for layer in quant_layers])

    write_hex_file(out_dir / "animals10_weights_i8.hex", weights, 8)
    write_hex_file(out_dir / "animals10_bias_i32.hex", biases, 32)
    write_hex_file(out_dir / "animals10_requant_mult_i32.hex", mults, 32)
    write_hex_file(out_dir / "animals10_requant_shift_i8.hex", shifts, 8)
    write_txt_file(out_dir / "animals10_weights_i8.txt", weights)
    write_txt_file(out_dir / "animals10_bias_i32.txt", biases)
    write_txt_file(out_dir / "animals10_requant_mult_i32.txt", mults)
    write_txt_file(out_dir / "animals10_requant_shift_i8.txt", shifts)

    scale_payload = {
        "activation_scales": activation_scales,
        "weight_scales": {layer["name"]: layer["weight_scales"].tolist() for layer in quant_layers},
        "layer_io_scales": {
            layer["name"]: {
                "input_scale": layer["input_scale"],
                "output_scale": layer["output_scale"],
            }
            for layer in quant_layers
        },
    }
    save_json(out_dir / "animals10_qparams.json", scale_payload)

    model_config = {
        "model_name": "animals10_student_a_int8",
        "class_names": CLASS_NAMES,
        "input_shape_chw": [3, 64, 64],
        "tensor_layout": "channel_major_chw",
        "input_addr": "base + c * H * W + y * W + x",
        "weight_layout": "output_channel_major_oihw",
        "arithmetic": {
            "input": "signed_int8",
            "weights": "signed_int8_per_output_channel",
            "bias": "signed_int32",
            "accumulator": "signed_int32",
            "requant": "round((acc + bias) * multiplier / 2**shift)",
            "zero_point": 0,
            "clamp": [-128, 127],
        },
    }
    save_json(out_dir / "animals10_model_config.json", model_config)
    save_json(out_dir / "animals10_layer_shapes.json", {"layers": descriptors})


def export_test_vectors(out_dir: Path, loader, max_cases: int, balanced_per_class: int = 0) -> None:
    state = load_exported_state(out_dir)
    input_scale = state["config"].get("input_scale")
    _ = input_scale
    inputs: list[np.ndarray] = []
    logits: list[np.ndarray] = []
    labels: list[int] = []
    predictions: list[int] = []
    class_counts = {idx: 0 for idx in range(len(CLASS_NAMES))}
    debug_written = False

    for images, batch_labels in loader:
        for index in range(images.size(0)):
            label = int(batch_labels[index].item())
            if balanced_per_class > 0 and class_counts[label] >= balanced_per_class:
                continue
            image = images[index].numpy()
            input_i8 = quantize_int8(image, load_exported_activation_scale(out_dir, "input"))
            prediction, debug = infer_i8(state, input_i8)
            inputs.append(input_i8.reshape(-1))
            logits.append(debug["final_logits_i8"].reshape(-1))
            labels.append(label)
            predictions.append(prediction)
            class_counts[label] += 1
            if not debug_written:
                debug_dir = ensure_dir(out_dir / "debug_case0")
                for name, values in debug.items():
                    bits = 32 if name.endswith("_i32") else 8
                    write_hex_file(debug_dir / f"{name}.hex", values, bits)
                    np.save(debug_dir / f"{name}.npy", values)
                debug_written = True
            if balanced_per_class > 0:
                if all(count >= balanced_per_class for count in class_counts.values()):
                    break
            elif len(inputs) >= max_cases:
                break
        if balanced_per_class > 0:
            if all(count >= balanced_per_class for count in class_counts.values()):
                break
        elif len(inputs) >= max_cases:
            break

    if not inputs:
        raise RuntimeError("No INT8 test vectors were selected")

    write_hex_file(out_dir / "animals10_test_inputs_i8.hex", np.concatenate(inputs), 8)
    write_hex_file(out_dir / "animals10_test_logits_i8.hex", np.concatenate(logits), 8)
    write_hex_file(out_dir / "animals10_test_labels.hex", np.asarray(labels, dtype=np.int8), 8)
    manifest = ["idx label class_name prediction logits"]
    for idx, (label, pred, logit_vec) in enumerate(zip(labels, predictions, logits)):
        manifest.append(
            f"{idx} {label} {CLASS_NAMES[label]} {pred} "
            + ",".join(str(int(value)) for value in logit_vec.reshape(-1))
        )
    (out_dir / "animals10_test_manifest.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    print(f"exported_test_vectors={len(inputs)} class_counts={class_counts}")


def load_exported_activation_scale(out_dir: Path, name: str) -> float:
    import json

    payload = json.loads((out_dir / "animals10_qparams.json").read_text(encoding="utf-8"))
    return float(payload["activation_scales"][name])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export PyTorch Student A as signed INT8 RTL files.")
    parser.add_argument("--checkpoint", required=True, help="Student A checkpoint from train_student.py.")
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--manifest", default="../animals10_split_manifest.csv")
    parser.add_argument("--out-dir", default="int8_export")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--calibration-batches", type=int, default=32)
    parser.add_argument("--test-cases", type=int, default=8)
    parser.add_argument(
        "--balanced-test-cases-per-class",
        type=int,
        default=0,
        help="If positive, export this many test vectors per class instead of the first --test-cases samples.",
    )
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out_dir = ensure_dir(args.out_dir)
    device = torch.device(args.device)

    train_loader, val_loader, test_loader = build_animals10_loaders(
        data_root=args.data_root,
        manifest_path=args.manifest,
        input_size=STUDENT_INPUT_SIZE,
        batch_size=args.batch_size,
        eval_batch_size=args.batch_size,
        model_family="student",
        num_workers=args.num_workers,
    )
    _ = train_loader
    fp32_model = StudentCNNVersionA()
    fp32_model.load_state_dict(load_checkpoint_state(args.checkpoint, map_location="cpu"))
    fp32_model.eval()
    folded_model = fold_student_a(fp32_model).to(device)

    with torch.inference_mode():
        sample, _ = next(iter(val_loader))
        sample = sample[: min(sample.size(0), 8)].to(device)
        original_logits = fp32_model.to(device).eval()(sample)
        folded_logits = folded_model(sample)
        max_abs_diff = (original_logits - folded_logits).abs().max().item()
    print(f"bn_fold_max_abs_diff={max_abs_diff:.8f}")

    maxima = collect_activation_maxima(folded_model, val_loader, device, args.calibration_batches)
    activation_scales = {name: symmetric_scale(value) for name, value in maxima.items()}
    activation_scales["pool1"] = activation_scales["b1_relu2"]
    activation_scales["pool2"] = activation_scales["b2_relu2"]
    activation_scales["pool3"] = activation_scales["b3_relu2"]
    activation_scales["gap"] = activation_scales["pool3"]

    quant_layers, descriptors = build_layer_exports(folded_model.cpu(), activation_scales)
    write_export_files(out_dir, quant_layers, descriptors, activation_scales)
    export_test_vectors(
        out_dir,
        test_loader,
        args.test_cases,
        balanced_per_class=args.balanced_test_cases_per_class,
    )
    torch.save({"model_state": folded_model.cpu().state_dict(), "bn_fold_max_abs_diff": max_abs_diff}, out_dir / "student_a_folded_fp32.pt")
    print(f"wrote INT8 export to {out_dir}")


if __name__ == "__main__":
    main()

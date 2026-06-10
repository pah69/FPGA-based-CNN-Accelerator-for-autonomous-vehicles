"""Print Student A/B parameter and MAC estimates for RTL planning."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch
import torch.nn as nn

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from animals10_common import STUDENT_INPUT_SIZE, count_parameters, save_json
from animals10_models import build_student


def estimate_student_a_macs() -> list[dict[str, int | str | list[int]]]:
    rows: list[dict[str, int | str | list[int]]] = [
        {"name": "conv1", "type": "conv3x3", "output_shape": [32, 64, 64], "macs": 64 * 64 * 32 * 3 * 3 * 3},
        {"name": "conv2", "type": "conv3x3", "output_shape": [32, 64, 64], "macs": 64 * 64 * 32 * 32 * 3 * 3},
        {"name": "conv3", "type": "conv3x3", "output_shape": [64, 32, 32], "macs": 32 * 32 * 64 * 32 * 3 * 3},
        {"name": "conv4", "type": "conv3x3", "output_shape": [64, 32, 32], "macs": 32 * 32 * 64 * 64 * 3 * 3},
        {"name": "conv5", "type": "conv3x3", "output_shape": [128, 16, 16], "macs": 16 * 16 * 128 * 64 * 3 * 3},
        {"name": "conv6", "type": "conv3x3", "output_shape": [128, 16, 16], "macs": 16 * 16 * 128 * 128 * 3 * 3},
        {"name": "gap", "type": "gap", "output_shape": [128], "macs": 0},
        {"name": "fc1", "type": "dense", "output_shape": [128], "macs": 128 * 128},
        {"name": "fc2", "type": "dense", "output_shape": [10], "macs": 128 * 10},
    ]
    return rows


def activation_footprints() -> list[dict[str, int | str | list[int]]]:
    shapes = [
        ("input", [3, 64, 64]),
        ("conv1_out", [32, 64, 64]),
        ("conv2_out", [32, 64, 64]),
        ("pool1_out", [32, 32, 32]),
        ("conv3_out", [64, 32, 32]),
        ("conv4_out", [64, 32, 32]),
        ("pool2_out", [64, 16, 16]),
        ("conv5_out", [128, 16, 16]),
        ("conv6_out", [128, 16, 16]),
        ("pool3_out", [128, 8, 8]),
    ]
    return [{"name": name, "shape_chw": shape, "bytes_i8": int(torch.tensor(shape).prod().item())} for name, shape in shapes]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inspect Animals-10 student model for RTL planning.")
    parser.add_argument("--variant", choices=("A", "B"), default="A")
    parser.add_argument("--out-json", default="")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = build_student(args.variant)
    print(model)
    params = count_parameters(model)
    print(f"parameters={params}")
    payload = {"variant": args.variant, "parameters": params, "input_size": STUDENT_INPUT_SIZE}
    if args.variant == "A":
        mac_rows = estimate_student_a_macs()
        footprints = activation_footprints()
        total_macs = sum(int(row["macs"]) for row in mac_rows)
        payload.update({"layers": mac_rows, "activation_footprints": footprints, "total_macs": total_macs})
        print(f"total_macs={total_macs}")
        for row in mac_rows:
            print(f"{row['name']}: shape={row['output_shape']} macs={row['macs']}")
        for row in footprints:
            print(f"{row['name']}: shape={row['shape_chw']} bytes_i8={row['bytes_i8']}")
    if args.out_json:
        save_json(args.out_json, payload)


if __name__ == "__main__":
    main()


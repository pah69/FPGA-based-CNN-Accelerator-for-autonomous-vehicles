#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def read_ints(path: Path) -> list[int]:
    return [int(line.strip()) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def format_values(values: list[int]) -> str:
    return ", ".join(str(value) for value in values)


def write_array(lines: list[str], c_type: str, name: str, values: list[int], per_line: int) -> None:
    lines.append(f"const {c_type} {name}[{len(values)}] = {{")
    for idx in range(0, len(values), per_line):
        suffix = "," if idx + per_line < len(values) else ""
        lines.append(f"    {format_values(values[idx:idx + per_line])}{suffix}")
    lines.append("};")
    lines.append("")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate C arrays for the CPU INT8 MNIST reference.")
    parser.add_argument("--export-dir", required=True, type=Path)
    parser.add_argument("--out-header", required=True, type=Path)
    parser.add_argument("--out-source", required=True, type=Path)
    args = parser.parse_args()

    export_dir = args.export_dir.resolve()
    weights = read_ints(export_dir / "small_cnn_sym_weights_i8_c_order.txt")
    biases = read_ints(export_dir / "small_cnn_sym_biases_i32_c_order.txt")
    mults = read_ints(export_dir / "small_cnn_sym_requant_mult_i32_c_order.txt")
    shifts = read_ints(export_dir / "small_cnn_sym_requant_shift_u6_c_order.txt")

    if len(weights) != 4952:
        raise ValueError(f"expected 4952 weights, got {len(weights)}")
    if len(biases) != 44 or len(mults) != 44 or len(shifts) != 44:
        raise ValueError("expected 44 biases, 44 multipliers, and 44 shifts")

    args.out_header.write_text(
        "\n".join([
            "#ifndef CPU_MODEL_PARAMS_H",
            "#define CPU_MODEL_PARAMS_H",
            "",
            '#include "xil_types.h"',
            "",
            "#define CPU_MODEL_WEIGHT_COUNT 4952U",
            "#define CPU_MODEL_BIAS_COUNT 44U",
            "",
            "extern const s8 cpu_model_weights[CPU_MODEL_WEIGHT_COUNT];",
            "extern const s32 cpu_model_biases[CPU_MODEL_BIAS_COUNT];",
            "extern const s32 cpu_model_requant_mult[CPU_MODEL_BIAS_COUNT];",
            "extern const u8 cpu_model_requant_shift[CPU_MODEL_BIAS_COUNT];",
            "",
            "#endif",
            "",
        ]),
        encoding="utf-8",
    )

    lines = ['#include "cpu_model_params.h"', ""]
    write_array(lines, "s8", "cpu_model_weights", weights, 32)
    write_array(lines, "s32", "cpu_model_biases", biases, 8)
    write_array(lines, "s32", "cpu_model_requant_mult", mults, 8)
    write_array(lines, "u8", "cpu_model_requant_shift", shifts, 16)
    args.out_source.write_text("\n".join(lines), encoding="utf-8")

    print(f"header: {args.out_header}")
    print(f"source: {args.out_source}")


if __name__ == "__main__":
    main()

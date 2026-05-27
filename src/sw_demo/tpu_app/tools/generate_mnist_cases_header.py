#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


INPUT_SIZE = 784
LOGIT_COUNT = 10


def read_i8_hex(path: Path) -> list[int]:
    values: list[int] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        token = line.strip()
        if not token:
            continue
        raw = int(token, 16)
        if raw >= 128:
            raw -= 256
        values.append(raw)
    return values


def parse_manifest(path: Path) -> list[tuple[int, int]]:
    rows: list[tuple[int, int]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for line in lines[1:]:
        parts = line.split(maxsplit=4)
        if len(parts) != 5:
            raise ValueError(f"bad manifest row: {line}")
        rows.append((int(parts[2]), int(parts[3])))
    return rows


def format_values(values: list[int]) -> str:
    return ", ".join(str(value) for value in values)


def write_header(path: Path, count: int, start: int) -> None:
    path.write_text(
        "\n".join([
            "#ifndef MNIST_REAL_CASES_H",
            "#define MNIST_REAL_CASES_H",
            "",
            '#include "tpu_axi_lite.h"',
            "",
            f"#define MNIST_REAL_CASE_COUNT {count}U",
            f"#define MNIST_REAL_CASE_START {start}U",
            "",
            "extern const s8 mnist_real_inputs[MNIST_REAL_CASE_COUNT][TPU_IMAGE_SIZE];",
            "extern const s8 mnist_real_expected_logits[MNIST_REAL_CASE_COUNT][TPU_LOGIT_COUNT];",
            "extern const s8 mnist_real_labels[MNIST_REAL_CASE_COUNT];",
            "extern const s8 mnist_real_expected_predictions[MNIST_REAL_CASE_COUNT];",
            "",
            "#endif",
            "",
        ]),
        encoding="utf-8",
    )


def write_source(path: Path,
                 inputs: list[int],
                 logits: list[int],
                 manifest: list[tuple[int, int]],
                 start: int,
                 count: int) -> None:
    lines: list[str] = ['#include "mnist_real_cases.h"', ""]

    selected_rows = manifest[start:start + count]
    labels = [label for label, _prediction in selected_rows]
    predictions = [prediction for _label, prediction in selected_rows]

    lines.append("const s8 mnist_real_labels[MNIST_REAL_CASE_COUNT] = {")
    for idx in range(0, len(labels), 32):
        suffix = "," if idx + 32 < len(labels) else ""
        lines.append(f"    {format_values(labels[idx:idx + 32])}{suffix}")
    lines.append("};")
    lines.append("")

    lines.append("const s8 mnist_real_expected_predictions[MNIST_REAL_CASE_COUNT] = {")
    for idx in range(0, len(predictions), 32):
        suffix = "," if idx + 32 < len(predictions) else ""
        lines.append(f"    {format_values(predictions[idx:idx + 32])}{suffix}")
    lines.append("};")
    lines.append("")

    lines.append("const s8 mnist_real_expected_logits[MNIST_REAL_CASE_COUNT][TPU_LOGIT_COUNT] = {")
    for out_idx, case_idx in enumerate(range(start, start + count)):
        offset = case_idx * LOGIT_COUNT
        suffix = "," if out_idx != count - 1 else ""
        lines.append(f"    {{{format_values(logits[offset:offset + LOGIT_COUNT])}}}{suffix}")
    lines.append("};")
    lines.append("")

    lines.append("const s8 mnist_real_inputs[MNIST_REAL_CASE_COUNT][TPU_IMAGE_SIZE] = {")
    for out_idx, case_idx in enumerate(range(start, start + count)):
        input_offset = case_idx * INPUT_SIZE
        case_inputs = inputs[input_offset:input_offset + INPUT_SIZE]
        if len(case_inputs) != INPUT_SIZE:
            raise ValueError(f"bad input slice for case {case_idx}")
        lines.append("    {")
        for row in range(28):
            row_values = case_inputs[row * 28:(row + 1) * 28]
            suffix = "," if row != 27 else ""
            lines.append(f"        {format_values(row_values)}{suffix}")
        lines.append("    }" + ("," if out_idx != count - 1 else ""))
    lines.append("};")
    lines.append("")

    path.write_text("\n".join(lines), encoding="utf-8")


def generate(case_dir: Path, out_header: Path, out_source: Path, start: int, count: int) -> None:
    inputs = read_i8_hex(case_dir / "tpu_top_e2e_inputs_i8.hex")
    logits = read_i8_hex(case_dir / "tpu_top_e2e_logits_i8.hex")
    manifest = parse_manifest(case_dir / "manifest.txt")

    if count <= 0:
        raise ValueError("case count must be positive")
    if start < 0 or start + count > len(manifest):
        raise ValueError("requested case range is outside manifest")
    if len(inputs) < (start + count) * INPUT_SIZE:
        raise ValueError("input file does not contain requested case range")
    if len(logits) < (start + count) * LOGIT_COUNT:
        raise ValueError("logit file does not contain requested case range")

    write_header(out_header, count, start)
    write_source(out_source, inputs, logits, manifest, start, count)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate embedded MNIST cases for the ZCU104 bare-metal demo.")
    parser.add_argument("--case-dir", required=True, type=Path)
    parser.add_argument("--out-header", default=None, type=Path)
    parser.add_argument("--out-source", default=None, type=Path)
    parser.add_argument("--out", default=None, type=Path, help="Backward-compatible header output path.")
    parser.add_argument("--start", default=0, type=int)
    parser.add_argument("--count", default=10000, type=int)
    args = parser.parse_args()

    out_header = args.out_header or args.out
    if out_header is None:
        raise ValueError("pass --out-header or --out")
    out_source = args.out_source or out_header.with_suffix(".c")

    generate(args.case_dir.resolve(), out_header.resolve(), out_source.resolve(), args.start, args.count)
    print(f"wrote {args.count} cases")
    print(f"header: {out_header}")
    print(f"source: {out_source}")


if __name__ == "__main__":
    main()

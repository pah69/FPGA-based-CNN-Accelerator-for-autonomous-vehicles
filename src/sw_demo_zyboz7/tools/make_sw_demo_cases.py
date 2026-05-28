#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import textwrap


IMAGE_SIZE = 784
LOGIT_COUNT = 10


@dataclass(frozen=True)
class ManifestCase:
    name: str
    label: int
    prediction: int


def signed_i8_from_hex(token: str) -> int:
    value = int(token, 16)
    return value - 256 if value >= 128 else value


def read_hex_lines(path: Path) -> list[str]:
    lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines()]
    return [line for line in lines if line]


def read_manifest(path: Path) -> list[ManifestCase]:
    lines = path.read_text(encoding="utf-8").splitlines()
    cases: list[ManifestCase] = []
    for line in lines[1:]:
        if not line.strip():
            continue
        fields = line.split(maxsplit=4)
        if len(fields) < 4:
            raise ValueError(f"bad manifest line: {line}")
        cases.append(
            ManifestCase(
                name=fields[1],
                label=-1 if fields[2] == "none" else int(fields[2]),
                prediction=int(fields[3]),
            )
        )
    return cases


def emit_string_literal(hex_chars: str, indent: str = "        ") -> list[str]:
    return [f'{indent}"{chunk}"' for chunk in textwrap.wrap(hex_chars, width=64)]


def emit_case(
    case: ManifestCase,
    input_bytes: list[str],
    logit_bytes: list[str],
) -> str:
    input_hex = "".join(f"{int(token, 16) & 0xff:02x}" for token in input_bytes)
    logits = ", ".join(str(signed_i8_from_hex(token)) for token in logit_bytes)
    string_lines = emit_string_literal(input_hex)

    lines = [
        "    {",
        "        {",
        f'            "{case.name}",',
        f"            {case.label},",
        f"            {case.prediction},",
        f"            {{ {logits} }}",
        "        },",
    ]
    lines.extend(string_lines)
    lines.append("    }")
    return "\n".join(lines)


def generate_source(
    manifest: list[ManifestCase],
    input_lines: list[str],
    logit_lines: list[str],
    case_start: int,
    case_count: int,
) -> str:
    if case_start < 0 or case_count <= 0:
        raise ValueError("case_start must be >= 0 and case_count must be > 0")
    if case_start + case_count > len(manifest):
        raise ValueError("requested case range exceeds manifest")
    if len(input_lines) < (case_start + case_count) * IMAGE_SIZE:
        raise ValueError("input hex file does not contain enough cases")
    if len(logit_lines) < (case_start + case_count) * LOGIT_COUNT:
        raise ValueError("logit hex file does not contain enough cases")

    emitted_cases: list[str] = []
    for offset in range(case_count):
        case_index = case_start + offset
        image_base = case_index * IMAGE_SIZE
        logit_base = case_index * LOGIT_COUNT
        emitted_cases.append(
            emit_case(
                manifest[case_index],
                input_lines[image_base:image_base + IMAGE_SIZE],
                logit_lines[logit_base:logit_base + LOGIT_COUNT],
            )
        )

    case_text = ",\n".join(emitted_cases)
    return f"""#include "mnist_real_cases.h"

typedef struct {{
    mnist_real_case_t meta;
    const char *input_hex;
}} embedded_real_case_t;

static const embedded_real_case_t real_cases[] = {{
{case_text}
}};

static int hex_nibble(char ch)
{{
    if ((ch >= '0') && (ch <= '9')) {{
        return ch - '0';
    }}
    if ((ch >= 'a') && (ch <= 'f')) {{
        return ch - 'a' + 10;
    }}
    if ((ch >= 'A') && (ch <= 'F')) {{
        return ch - 'A' + 10;
    }}
    return -1;
}}

u32 mnist_real_case_count(void)
{{
    return (u32)(sizeof(real_cases) / sizeof(real_cases[0]));
}}

const mnist_real_case_t *mnist_real_case_get(u32 index)
{{
    if (index >= mnist_real_case_count()) {{
        return 0;
    }}
    return &real_cases[index].meta;
}}

int mnist_real_case_fill_input(u32 index, s8 input[TPU_IMAGE_SIZE])
{{
    const char *hex = 0;

    if ((index >= mnist_real_case_count()) || (input == 0)) {{
        return -1;
    }}

    hex = real_cases[index].input_hex;
    for (u32 idx = 0U; idx < TPU_IMAGE_SIZE; idx++) {{
        int hi = hex_nibble(hex[idx * 2U]);
        int lo = hex_nibble(hex[(idx * 2U) + 1U]);
        if ((hi < 0) || (lo < 0)) {{
            return -1;
        }}
        input[idx] = (s8)(u8)((hi << 4) | lo);
    }}

    return 0;
}}
"""


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    sw_dir = script_dir.parent
    project_dir = sw_dir.parent.parent
    case_dir = project_dir / "CNN_model/python/mnist_classification/18_05/e2e_cases"

    parser = argparse.ArgumentParser(description="Embed real MNIST E2E cases into the Zybo app.")
    parser.add_argument("--case-dir", type=Path, default=case_dir)
    parser.add_argument("--case-start", type=int, default=0)
    parser.add_argument("--case-count", type=int, default=10)
    parser.add_argument(
        "--out",
        type=Path,
        default=sw_dir / "app/src/mnist_real_cases.c",
        help="generated C source path",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    case_dir = args.case_dir.resolve()
    out = args.out.resolve()

    manifest = read_manifest(case_dir / "manifest.txt")
    input_lines = read_hex_lines(case_dir / "tpu_top_e2e_inputs_i8.hex")
    logit_lines = read_hex_lines(case_dir / "tpu_top_e2e_logits_i8.hex")
    source = generate_source(
        manifest=manifest,
        input_lines=input_lines,
        logit_lines=logit_lines,
        case_start=args.case_start,
        case_count=args.case_count,
    )

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(source, encoding="utf-8")
    print(f"wrote {args.case_count} real cases to {out}")


if __name__ == "__main__":
    main()

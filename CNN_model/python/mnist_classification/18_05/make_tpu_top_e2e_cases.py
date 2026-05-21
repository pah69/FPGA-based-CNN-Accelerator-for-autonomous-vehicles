from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import reference_infer_int as ref


INPUT_SHAPE = (1, 28, 28)
INPUT_COUNT = 784
LOGIT_COUNT = 10


def read_input_hex(path: Path) -> np.ndarray:
    values = ref.read_hex_file(path, 8)
    if len(values) != INPUT_COUNT:
        raise ValueError(f"{path} has {len(values)} values, expected {INPUT_COUNT}")
    return np.asarray(values, dtype=np.int8).reshape(INPUT_SHAPE)


def write_flat_hex(path: Path, arrays: list[np.ndarray], bits: int) -> None:
    flat = np.concatenate([np.asarray(array).reshape(-1) for array in arrays])
    ref.write_hex_file(path, flat, bits)


def synthetic_cases(export_dir: Path) -> list[tuple[str, np.ndarray, int | None]]:
    zero = np.zeros(INPUT_SHAPE, dtype=np.int8)

    impulse = np.zeros(INPUT_SHAPE, dtype=np.int8)
    impulse[0, 14, 14] = 127

    checker = np.fromfunction(
        lambda _c, y, x: np.where(((y + x) % 2) == 0, 32, -32),
        INPUT_SHAPE,
        dtype=int,
    ).astype(np.int8)

    return [
        ("exported_image", read_input_hex(export_dir / "input_image_i8.hex"), None),
        ("zero_image", zero, None),
        ("impulse_center_127", impulse, None),
        ("checker_pm32", checker, None),
    ]


def mnist_cases(
    export_dir: Path,
    data_dir: Path,
    count: int,
    start_index: int,
    download: bool,
) -> list[tuple[str, np.ndarray, int | None]]:
    if count <= 0:
        return []

    try:
        from torchvision import datasets, transforms
    except ImportError as exc:
        raise RuntimeError("torchvision is required for --mnist-count") from exc

    qparams = ref.load_qparams(export_dir)
    if "activation_scale.input" not in qparams:
        raise RuntimeError("activation_scale.input is missing from small_cnn_sym_qparams.txt")

    scale = float(qparams["activation_scale.input"])
    dataset = datasets.MNIST(
        root=str(data_dir),
        train=False,
        transform=transforms.ToTensor(),
        download=download,
    )

    cases: list[tuple[str, np.ndarray, int | None]] = []
    for offset in range(count):
        dataset_index = start_index + offset
        image, label = dataset[dataset_index]
        image_np = image.numpy().reshape(INPUT_SHAPE)
        input_i8 = ref.symmetric_quantize_float(image_np, scale)
        cases.append((f"mnist_test_{dataset_index}_label_{int(label)}", input_i8, int(label)))
    return cases


def read_csv_uint8_image(line: str, line_number: int) -> np.ndarray:
    tokens = [token.strip() for token in line.strip().split(",") if token.strip()]
    if len(tokens) != INPUT_COUNT:
        raise ValueError(f"image line {line_number} has {len(tokens)} pixels, expected {INPUT_COUNT}")

    values = np.asarray([int(token) for token in tokens], dtype=np.int32)
    if np.any(values < 0) or np.any(values > 255):
        raise ValueError(f"image line {line_number} contains values outside uint8 range")
    return values.astype(np.float64).reshape(INPUT_SHAPE) / 255.0


def mnist_text_cases(
    export_dir: Path,
    images_txt: Path | None,
    labels_txt: Path | None,
    count: int,
    start_index: int,
) -> list[tuple[str, np.ndarray, int | None]]:
    if images_txt is None:
        return []
    if count <= 0:
        raise ValueError("--txt-count must be positive when --images-txt is used")

    qparams = ref.load_qparams(export_dir)
    if "activation_scale.input" not in qparams:
        raise RuntimeError("activation_scale.input is missing from small_cnn_sym_qparams.txt")

    scale = float(qparams["activation_scale.input"])
    image_lines = images_txt.read_text(encoding="utf-8").splitlines()
    label_lines: list[str] = []
    if labels_txt is not None:
        label_lines = labels_txt.read_text(encoding="utf-8").splitlines()

    if start_index < 0 or start_index >= len(image_lines):
        raise ValueError(f"--txt-start={start_index} is outside image file range")
    if start_index + count > len(image_lines):
        raise ValueError("requested text-image range exceeds available images")
    if label_lines and (start_index + count > len(label_lines)):
        raise ValueError("requested text-label range exceeds available labels")

    cases: list[tuple[str, np.ndarray, int | None]] = []
    for offset in range(count):
        dataset_index = start_index + offset
        image_float = read_csv_uint8_image(image_lines[dataset_index], dataset_index + 1)
        input_i8 = ref.symmetric_quantize_float(image_float, scale)
        label = int(label_lines[dataset_index].strip()) if label_lines else None
        label_suffix = "unknown" if label is None else str(label)
        cases.append((f"mnist_txt_{dataset_index}_label_{label_suffix}", input_i8, label))
    return cases


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build TPU top E2E case hex files.")
    parser.add_argument("--export-dir", default=".", help="Directory containing signed INT8 export files.")
    parser.add_argument("--out-dir", default="e2e_cases", help="Output directory for flat case files.")
    parser.add_argument("--include-synthetic", action="store_true", help="Include four built-in directed cases.")
    parser.add_argument("--mnist-count", type=int, default=0, help="Number of MNIST test images to append.")
    parser.add_argument("--mnist-start", type=int, default=0, help="First MNIST test-set index.")
    parser.add_argument("--mnist-data-dir", default="../data", help="MNIST data directory.")
    parser.add_argument("--download-mnist", action="store_true", help="Allow torchvision to download MNIST.")
    parser.add_argument("--images-txt", type=Path, default=None, help="CSV uint8 MNIST image text file.")
    parser.add_argument("--labels-txt", type=Path, default=None, help="One-label-per-line MNIST label file.")
    parser.add_argument("--txt-count", type=int, default=0, help="Number of text-file images to append.")
    parser.add_argument("--txt-start", type=int, default=0, help="First text-file image index.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    export_dir = Path(args.export_dir).resolve()
    out_dir = (export_dir / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    state = ref.load_exported_state(export_dir)
    cases: list[tuple[str, np.ndarray, int | None]] = []
    if args.include_synthetic:
        cases.extend(synthetic_cases(export_dir))
    cases.extend(
        mnist_cases(
            export_dir=export_dir,
            data_dir=(export_dir / args.mnist_data_dir).resolve(),
            count=args.mnist_count,
            start_index=args.mnist_start,
            download=args.download_mnist,
        )
    )
    cases.extend(
        mnist_text_cases(
            export_dir=export_dir,
            images_txt=args.images_txt,
            labels_txt=args.labels_txt,
            count=args.txt_count,
            start_index=args.txt_start,
        )
    )

    if not cases:
        raise RuntimeError("No cases selected. Use --include-synthetic or --mnist-count.")

    inputs: list[np.ndarray] = []
    logits: list[np.ndarray] = []
    manifest_lines = ["idx name label prediction logits"]
    labelled_count = 0
    correct_count = 0

    for idx, (name, input_i8, label) in enumerate(cases):
        prediction, debug = ref.infer_i8(state, input_i8)
        logit_vec = np.asarray(debug["final_logits"], dtype=np.int8).reshape(LOGIT_COUNT)
        inputs.append(np.asarray(input_i8, dtype=np.int8).reshape(INPUT_COUNT))
        logits.append(logit_vec)
        label_text = "none" if label is None else str(label)
        if label is not None:
            labelled_count += 1
            if prediction == label:
                correct_count += 1
        logit_text = ",".join(str(int(value)) for value in logit_vec)
        manifest_lines.append(f"{idx} {name} {label_text} {prediction} {logit_text}")

    write_flat_hex(out_dir / "tpu_top_e2e_inputs_i8.hex", inputs, 8)
    write_flat_hex(out_dir / "tpu_top_e2e_logits_i8.hex", logits, 8)
    (out_dir / "manifest.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    (out_dir / "case_count.txt").write_text(f"{len(cases)}\n", encoding="utf-8")

    print(f"wrote {len(cases)} cases to {out_dir}")
    print("inputs: tpu_top_e2e_inputs_i8.hex")
    print("logits: tpu_top_e2e_logits_i8.hex")
    if labelled_count:
        print(f"reference accuracy over labelled cases: {correct_count}/{labelled_count}")


if __name__ == "__main__":
    main()

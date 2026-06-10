"""Shared constants and file helpers for the Animals-10 PyTorch pipeline."""

from __future__ import annotations

import json
import random
from pathlib import Path
from typing import Any, Iterable

import numpy as np


CLASS_NAMES = [
    "dog",
    "cat",
    "horse",
    "spider",
    "butterfly",
    "chicken",
    "sheep",
    "cow",
    "squirrel",
    "elephant",
]

CLASS_TO_INDEX = {name: idx for idx, name in enumerate(CLASS_NAMES)}

CLASS_ALIASES = {
    "dog": "dog",
    "dogs": "dog",
    "cane": "dog",
    "cat": "cat",
    "cats": "cat",
    "gatto": "cat",
    "horse": "horse",
    "horses": "horse",
    "cavallo": "horse",
    "spider": "spider",
    "spiders": "spider",
    "ragno": "spider",
    "butterfly": "butterfly",
    "butterflies": "butterfly",
    "farfalla": "butterfly",
    "chicken": "chicken",
    "chickens": "chicken",
    "gallina": "chicken",
    "sheep": "sheep",
    "pecora": "sheep",
    "cow": "cow",
    "cows": "cow",
    "mucca": "cow",
    "squirrel": "squirrel",
    "squirrels": "squirrel",
    "scoiattolo": "squirrel",
    "elephant": "elephant",
    "elephants": "elephant",
    "elefante": "elephant",
}

DEFAULT_SEED = 2026
STUDENT_INPUT_SIZE = 64
TEACHER_INPUT_SIZES = {
    "b0": 224,
    "b1": 240,
    "b2": 260,
}


def normalize_class_name(name: str) -> str:
    key = name.strip().lower().replace("-", "_").replace(" ", "_")
    if key not in CLASS_ALIASES:
        raise ValueError(f"Unknown Animals-10 class folder: {name!r}")
    return CLASS_ALIASES[key]


def set_reproducible_seed(seed: int = DEFAULT_SEED) -> None:
    random.seed(seed)
    np.random.seed(seed)
    try:
        import torch
    except ImportError:
        return

    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def ensure_dir(path: str | Path) -> Path:
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def count_parameters(model: Any) -> int:
    return sum(parameter.numel() for parameter in model.parameters())


def save_json(path: str | Path, payload: dict[str, Any] | list[Any]) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def signed_to_hex(value: int, bits: int) -> str:
    return f"{int(value) & ((1 << bits) - 1):0{bits // 4}x}"


def hex_to_signed(token: str, bits: int) -> int:
    value = int(token.strip(), 16)
    sign_bit = 1 << (bits - 1)
    if value & sign_bit:
        value -= 1 << bits
    return value


def write_hex_file(path: str | Path, values: Iterable[int] | np.ndarray, bits: int) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(values).reshape(-1)
    path.write_text("".join(f"{signed_to_hex(int(value), bits)}\n" for value in flat), encoding="utf-8")


def read_hex_file(path: str | Path, bits: int) -> list[int]:
    return [
        hex_to_signed(line, bits)
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_txt_file(path: str | Path, values: Iterable[int] | np.ndarray) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(values).reshape(-1)
    path.write_text("".join(f"{int(value)}\n" for value in flat), encoding="utf-8")


def load_checkpoint_state(path: str | Path, map_location: str = "cpu") -> dict[str, Any]:
    import torch

    checkpoint = torch.load(path, map_location=map_location)
    if isinstance(checkpoint, dict):
        for key in ("model_state", "state_dict"):
            if key in checkpoint:
                return checkpoint[key]
    if not isinstance(checkpoint, dict):
        raise TypeError(f"Unsupported checkpoint object in {path}")
    return checkpoint


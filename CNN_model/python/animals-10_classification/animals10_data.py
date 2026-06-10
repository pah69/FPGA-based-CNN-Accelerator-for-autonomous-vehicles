"""Animals-10 manifest creation and PyTorch data loaders."""

from __future__ import annotations

import csv
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image
import torch
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms

from animals10_common import (
    CLASS_NAMES,
    CLASS_TO_INDEX,
    DEFAULT_SEED,
    normalize_class_name,
)


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
MANIFEST_COLUMNS = ["rel_path", "label", "class_name", "split"]


@dataclass(frozen=True)
class ManifestEntry:
    rel_path: str
    label: int
    class_name: str
    split: str


def _candidate_dataset_root(data_root: Path) -> Path:
    if (data_root / "raw-img").is_dir():
        return data_root / "raw-img"
    return data_root


def _iter_class_images(data_root: Path) -> dict[str, list[Path]]:
    scan_root = _candidate_dataset_root(data_root)
    class_to_paths: dict[str, list[Path]] = {name: [] for name in CLASS_NAMES}

    for class_dir in sorted(path for path in scan_root.iterdir() if path.is_dir()):
        try:
            class_name = normalize_class_name(class_dir.name)
        except ValueError:
            continue
        for image_path in sorted(class_dir.rglob("*")):
            if image_path.is_file() and image_path.suffix.lower() in IMAGE_EXTENSIONS:
                class_to_paths[class_name].append(image_path)

    missing = [name for name, paths in class_to_paths.items() if not paths]
    if missing:
        raise RuntimeError(f"No images found for class folders: {', '.join(missing)}")
    return class_to_paths


def create_split_manifest(
    data_root: str | Path,
    manifest_path: str | Path,
    train_ratio: float = 0.70,
    val_ratio: float = 0.15,
    seed: int = DEFAULT_SEED,
) -> dict[str, dict[str, int]]:
    """Create a fixed stratified train/val/test CSV manifest."""

    if train_ratio <= 0 or val_ratio <= 0 or train_ratio + val_ratio >= 1:
        raise ValueError("Expected train_ratio > 0, val_ratio > 0, and train_ratio + val_ratio < 1")

    data_root = Path(data_root).resolve()
    manifest_path = Path(manifest_path)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    class_to_paths = _iter_class_images(data_root)
    rng = random.Random(seed)
    rows: list[dict[str, str | int]] = []

    for class_name in CLASS_NAMES:
        paths = list(class_to_paths[class_name])
        rng.shuffle(paths)
        total = len(paths)
        train_count = int(total * train_ratio)
        val_count = int(total * val_ratio)
        if total >= 3:
            train_count = max(1, min(train_count, total - 2))
            val_count = max(1, min(val_count, total - train_count - 1))

        split_for_index = (
            ["train"] * train_count
            + ["val"] * val_count
            + ["test"] * (total - train_count - val_count)
        )
        for image_path, split in zip(paths, split_for_index):
            rows.append(
                {
                    "rel_path": image_path.relative_to(data_root).as_posix(),
                    "label": CLASS_TO_INDEX[class_name],
                    "class_name": class_name,
                    "split": split,
                }
            )

    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    return manifest_counts(read_manifest(manifest_path))


def read_manifest(manifest_path: str | Path) -> list[ManifestEntry]:
    entries: list[ManifestEntry] = []
    with Path(manifest_path).open("r", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            entries.append(
                ManifestEntry(
                    rel_path=row["rel_path"],
                    label=int(row["label"]),
                    class_name=row["class_name"],
                    split=row["split"],
                )
            )
    return entries


def manifest_counts(entries: Iterable[ManifestEntry]) -> dict[str, dict[str, int]]:
    counts = {split: {name: 0 for name in CLASS_NAMES} for split in ("train", "val", "test")}
    for entry in entries:
        counts.setdefault(entry.split, {name: 0 for name in CLASS_NAMES})
        counts[entry.split][entry.class_name] += 1
    return counts


class Animals10ManifestDataset(Dataset):
    def __init__(
        self,
        data_root: str | Path,
        manifest_path: str | Path,
        split: str,
        transform: object,
    ) -> None:
        self.data_root = Path(data_root).resolve()
        self.entries = [entry for entry in read_manifest(manifest_path) if entry.split == split]
        self.transform = transform
        if not self.entries:
            raise RuntimeError(f"No entries found for split={split!r} in {manifest_path}")

    def __len__(self) -> int:
        return len(self.entries)

    def __getitem__(self, index: int):
        entry = self.entries[index]
        image = Image.open(self.data_root / entry.rel_path).convert("RGB")
        if self.transform is not None:
            image = self.transform(image)
        return image, entry.label


def build_transforms(input_size: int, train: bool, model_family: str):
    steps: list[object] = []
    if train:
        steps.extend(
            [
                transforms.RandomHorizontalFlip(),
                transforms.RandomRotation(7),
                transforms.RandomAffine(degrees=0, translate=(0.05, 0.05), scale=(0.90, 1.10)),
                transforms.ColorJitter(contrast=0.10),
            ]
        )
    steps.extend(
        [
            transforms.Resize((input_size, input_size), antialias=True),
            transforms.ToTensor(),
        ]
    )
    if model_family == "teacher":
        steps.append(transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)))
    elif model_family != "student":
        raise ValueError(f"Unsupported model_family: {model_family}")
    return transforms.Compose(steps)


def build_animals10_loaders(
    data_root: str | Path,
    manifest_path: str | Path,
    input_size: int,
    batch_size: int,
    eval_batch_size: int,
    model_family: str,
    num_workers: int = 2,
) -> tuple[DataLoader, DataLoader, DataLoader]:
    pin_memory = torch.cuda.is_available()
    train_dataset = Animals10ManifestDataset(
        data_root=data_root,
        manifest_path=manifest_path,
        split="train",
        transform=build_transforms(input_size=input_size, train=True, model_family=model_family),
    )
    val_dataset = Animals10ManifestDataset(
        data_root=data_root,
        manifest_path=manifest_path,
        split="val",
        transform=build_transforms(input_size=input_size, train=False, model_family=model_family),
    )
    test_dataset = Animals10ManifestDataset(
        data_root=data_root,
        manifest_path=manifest_path,
        split="test",
        transform=build_transforms(input_size=input_size, train=False, model_family=model_family),
    )

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=num_workers,
        pin_memory=pin_memory,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=eval_batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=pin_memory,
    )
    test_loader = DataLoader(
        test_dataset,
        batch_size=eval_batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=pin_memory,
    )
    return train_loader, val_loader, test_loader

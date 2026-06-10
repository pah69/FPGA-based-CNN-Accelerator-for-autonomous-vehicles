"""Train the RTL-compatible Animals-10 student CNN with teacher distillation."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import torch
import torch.nn.functional as F
from PIL import Image
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from animals10_common import (  # noqa: E402
    DEFAULT_SEED,
    STUDENT_INPUT_SIZE,
    TEACHER_INPUT_SIZES,
    count_parameters,
    ensure_dir,
    load_checkpoint_state,
    save_json,
    set_reproducible_seed,
)
from animals10_data import build_animals10_loaders, build_transforms, create_split_manifest, read_manifest  # noqa: E402
from animals10_models import build_student, build_teacher  # noqa: E402
from animals10_train import benchmark, evaluate, save_checkpoint, write_metrics  # noqa: E402


class Animals10DistillDataset(Dataset):
    """Return paired student/teacher views from the same manifest entry."""

    def __init__(
        self,
        data_root: str | Path,
        manifest_path: str | Path,
        split: str,
        student_input_size: int,
        teacher_input_size: int,
        train: bool,
    ) -> None:
        self.data_root = Path(data_root).resolve()
        self.entries = [entry for entry in read_manifest(manifest_path) if entry.split == split]
        if not self.entries:
            raise RuntimeError(f"No entries found for split={split!r} in {manifest_path}")

        if train:
            self.shared_augment = transforms.Compose(
                [
                    transforms.RandomHorizontalFlip(),
                    transforms.RandomRotation(7),
                    transforms.RandomAffine(degrees=0, translate=(0.05, 0.05), scale=(0.90, 1.10)),
                    transforms.ColorJitter(contrast=0.10),
                ]
            )
        else:
            self.shared_augment = None

        self.student_transform = build_transforms(
            input_size=student_input_size,
            train=False,
            model_family="student",
        )
        self.teacher_transform = build_transforms(
            input_size=teacher_input_size,
            train=False,
            model_family="teacher",
        )

    def __len__(self) -> int:
        return len(self.entries)

    def __getitem__(self, index: int):
        entry = self.entries[index]
        image = Image.open(self.data_root / entry.rel_path).convert("RGB")
        if self.shared_augment is not None:
            image = self.shared_augment(image)
        student_image = self.student_transform(image)
        teacher_image = self.teacher_transform(image)
        return student_image, teacher_image, entry.label


def build_distill_loaders(
    data_root: str | Path,
    manifest_path: str | Path,
    student_input_size: int,
    teacher_input_size: int,
    batch_size: int,
    num_workers: int,
) -> DataLoader:
    dataset = Animals10DistillDataset(
        data_root=data_root,
        manifest_path=manifest_path,
        split="train",
        student_input_size=student_input_size,
        teacher_input_size=teacher_input_size,
        train=True,
    )
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=num_workers,
        pin_memory=torch.cuda.is_available(),
    )


def distillation_loss(
    student_logits: torch.Tensor,
    teacher_logits: torch.Tensor,
    labels: torch.Tensor,
    temperature: float,
    ce_weight: float,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    ce = F.cross_entropy(student_logits, labels)
    soft_student = F.log_softmax(student_logits / temperature, dim=1)
    soft_teacher = F.softmax(teacher_logits / temperature, dim=1)
    kd = F.kl_div(soft_student, soft_teacher, reduction="batchmean") * (temperature * temperature)
    loss = ce_weight * ce + (1.0 - ce_weight) * kd
    return loss, ce.detach(), kd.detach()


def train_distill_one_epoch(
    student: torch.nn.Module,
    teacher: torch.nn.Module,
    loader: DataLoader,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
    epoch: int,
    temperature: float,
    ce_weight: float,
    log_interval: int,
) -> dict[str, float]:
    student.train()
    teacher.eval()
    loss_sum = 0.0
    ce_sum = 0.0
    kd_sum = 0.0
    correct = 0
    total = 0

    for batch_idx, (student_images, teacher_images, labels) in enumerate(loader):
        student_images = student_images.to(device, non_blocking=True)
        teacher_images = teacher_images.to(device, non_blocking=True)
        labels = labels.to(device, non_blocking=True)

        optimizer.zero_grad(set_to_none=True)
        student_logits = student(student_images)
        with torch.inference_mode():
            teacher_logits = teacher(teacher_images)
        loss, ce, kd = distillation_loss(
            student_logits=student_logits,
            teacher_logits=teacher_logits,
            labels=labels,
            temperature=temperature,
            ce_weight=ce_weight,
        )
        loss.backward()
        optimizer.step()

        batch_size = labels.numel()
        loss_sum += loss.item() * batch_size
        ce_sum += ce.item() * batch_size
        kd_sum += kd.item() * batch_size
        correct += (student_logits.argmax(dim=1) == labels).sum().item()
        total += batch_size

        if log_interval > 0 and batch_idx % log_interval == 0:
            print(
                f"epoch={epoch} batch={batch_idx}/{len(loader)} "
                f"loss={loss.item():.5f} ce={ce.item():.5f} kd={kd.item():.5f}"
            )

    return {
        "train_loss": loss_sum / max(1, total),
        "train_ce_loss": ce_sum / max(1, total),
        "train_kd_loss": kd_sum / max(1, total),
        "train_accuracy": correct / max(1, total),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Distill EfficientNet into the RTL-compatible Animals-10 student CNN.")
    parser.add_argument("--data-root", required=True, help="Animals-10 root, or parent containing raw-img/.")
    parser.add_argument("--manifest", default="../animals10_split_manifest.csv", help="Fixed split manifest CSV.")
    parser.add_argument("--make-split", action="store_true", help="Create or replace the manifest before training.")
    parser.add_argument("--teacher-checkpoint", required=True, help="EfficientNet teacher checkpoint from train_teacher.py.")
    parser.add_argument("--teacher-backbone", choices=("b0", "b1", "b2"), default="b0")
    parser.add_argument("--student-init", default=None, help="Optional Student A/B checkpoint to continue from.")
    parser.add_argument("--variant", choices=("A", "B"), default="A")
    parser.add_argument("--out-dir", default="runs/student_a_distill_b0")
    parser.add_argument("--student-input-size", type=int, default=STUDENT_INPUT_SIZE)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-batch-size", type=int, default=128)
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--dropout", type=float, default=0.20)
    parser.add_argument("--temperature", type=float, default=4.0)
    parser.add_argument("--ce-weight", type=float, default=0.50, help="Cross-entropy weight. KD weight is 1 - ce_weight.")
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--log-interval", type=int, default=20)
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.temperature <= 0:
        raise ValueError("--temperature must be > 0")
    if not 0.0 <= args.ce_weight <= 1.0:
        raise ValueError("--ce-weight must be in [0, 1]")


def main() -> None:
    args = parse_args()
    validate_args(args)
    set_reproducible_seed(args.seed)

    out_dir = ensure_dir(args.out_dir)
    manifest = Path(args.manifest)
    if args.make_split or not manifest.exists():
        counts = create_split_manifest(args.data_root, manifest, seed=args.seed)
        save_json(out_dir / "split_counts.json", counts)

    teacher_input_size = TEACHER_INPUT_SIZES[args.teacher_backbone]
    train_loader = build_distill_loaders(
        data_root=args.data_root,
        manifest_path=manifest,
        student_input_size=args.student_input_size,
        teacher_input_size=teacher_input_size,
        batch_size=args.batch_size,
        num_workers=args.num_workers,
    )
    _, val_loader, test_loader = build_animals10_loaders(
        data_root=args.data_root,
        manifest_path=manifest,
        input_size=args.student_input_size,
        batch_size=args.batch_size,
        eval_batch_size=args.eval_batch_size,
        model_family="student",
        num_workers=args.num_workers,
    )

    device = torch.device(args.device)
    teacher = build_teacher(args.teacher_backbone, pretrained=False, freeze_backbone=False).to(device)
    teacher.load_state_dict(load_checkpoint_state(args.teacher_checkpoint, map_location=str(device)))
    teacher.eval()
    for parameter in teacher.parameters():
        parameter.requires_grad = False

    student = build_student(args.variant, dropout=args.dropout).to(device)
    if args.student_init:
        student.load_state_dict(load_checkpoint_state(args.student_init, map_location=str(device)))

    student_params = count_parameters(student)
    teacher_params = count_parameters(teacher)
    print(student)
    print(f"student_variant={args.variant}")
    print(f"student_parameters={student_params}")
    print(f"teacher_backbone={args.teacher_backbone}")
    print(f"teacher_parameters={teacher_params}")
    print(f"temperature={args.temperature}")
    print(f"ce_weight={args.ce_weight}")
    print(f"kd_weight={1.0 - args.ce_weight}")

    optimizer = torch.optim.AdamW(student.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(1, args.epochs))
    history: list[dict[str, Any]] = []
    best_acc = -1.0

    for epoch in range(1, args.epochs + 1):
        train_metrics = train_distill_one_epoch(
            student=student,
            teacher=teacher,
            loader=train_loader,
            optimizer=optimizer,
            device=device,
            epoch=epoch,
            temperature=args.temperature,
            ce_weight=args.ce_weight,
            log_interval=args.log_interval,
        )
        scheduler.step()
        val_metrics = evaluate(student, val_loader, device)
        row = {"phase": "distill", "epoch": epoch, **train_metrics, **val_metrics}
        history.append(row)
        print(row)
        if val_metrics["accuracy"] > best_acc:
            best_acc = val_metrics["accuracy"]
            save_checkpoint(
                out_dir / "best.pt",
                student,
                optimizer,
                epoch,
                val_metrics,
                {
                    "variant": args.variant,
                    "student_input_size": args.student_input_size,
                    "student_parameters": student_params,
                    "teacher_backbone": args.teacher_backbone,
                    "teacher_checkpoint": str(args.teacher_checkpoint),
                    "temperature": args.temperature,
                    "ce_weight": args.ce_weight,
                },
            )

    test_metrics = evaluate(student, test_loader, device)
    bench = benchmark(student, (1, 3, args.student_input_size, args.student_input_size), device=device)
    history.append({"phase": "test", "epoch": args.epochs, **test_metrics, **bench})
    save_checkpoint(
        out_dir / "last.pt",
        student,
        optimizer,
        args.epochs,
        test_metrics,
        {
            "variant": args.variant,
            "student_input_size": args.student_input_size,
            "student_parameters": student_params,
            "teacher_backbone": args.teacher_backbone,
            "teacher_checkpoint": str(args.teacher_checkpoint),
            "temperature": args.temperature,
            "ce_weight": args.ce_weight,
        },
    )
    write_metrics(out_dir / "metrics.json", history)
    print(f"test_metrics={test_metrics}")
    print(f"benchmark={bench}")


if __name__ == "__main__":
    main()

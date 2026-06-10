"""Train an ImageNet-pretrained EfficientNet teacher on Animals-10."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from animals10_common import DEFAULT_SEED, TEACHER_INPUT_SIZES, count_parameters, ensure_dir, save_json, set_reproducible_seed
from animals10_data import build_animals10_loaders, create_split_manifest
from animals10_models import build_teacher, unfreeze_teacher_tail
from animals10_train import evaluate, export_logits, save_checkpoint, train_one_epoch, write_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train an EfficientNet teacher for Animals-10.")
    parser.add_argument("--data-root", required=True, help="Animals-10 root, or parent containing raw-img/.")
    parser.add_argument("--manifest", default="../animals10_split_manifest.csv", help="Fixed split manifest CSV.")
    parser.add_argument("--make-split", action="store_true", help="Create or replace the manifest before training.")
    parser.add_argument("--backbone", choices=("b0", "b1", "b2"), default="b0")
    parser.add_argument("--out-dir", default="runs/teacher_b0")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--eval-batch-size", type=int, default=64)
    parser.add_argument("--head-epochs", type=int, default=8)
    parser.add_argument("--finetune-epochs", type=int, default=12)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--finetune-lr", type=float, default=1e-5)
    parser.add_argument("--unfreeze-blocks", type=int, default=2)
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--no-pretrained", action="store_true", help="Do not load ImageNet weights.")
    parser.add_argument("--log-interval", type=int, default=20)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    set_reproducible_seed(args.seed)
    out_dir = ensure_dir(args.out_dir)
    manifest = Path(args.manifest)
    if args.make_split or not manifest.exists():
        counts = create_split_manifest(args.data_root, manifest, seed=args.seed)
        save_json(out_dir / "split_counts.json", counts)

    input_size = TEACHER_INPUT_SIZES[args.backbone]
    train_loader, val_loader, test_loader = build_animals10_loaders(
        data_root=args.data_root,
        manifest_path=manifest,
        input_size=input_size,
        batch_size=args.batch_size,
        eval_batch_size=args.eval_batch_size,
        model_family="teacher",
        num_workers=args.num_workers,
    )

    device = torch.device(args.device)
    model = build_teacher(
        args.backbone,
        pretrained=not args.no_pretrained,
        freeze_backbone=True,
    ).to(device)
    print(model)
    print(f"trainable_parameters={sum(p.numel() for p in model.parameters() if p.requires_grad)}")
    print(f"total_parameters={count_parameters(model)}")

    optimizer = torch.optim.AdamW((p for p in model.parameters() if p.requires_grad), lr=args.lr, weight_decay=1e-4)
    history: list[dict[str, float | int | str]] = []
    best_acc = -1.0
    epoch_idx = 0

    for epoch in range(1, args.head_epochs + 1):
        epoch_idx += 1
        train_loss = train_one_epoch(model, train_loader, optimizer, device, epoch_idx, args.log_interval)
        val_metrics = evaluate(model, val_loader, device)
        row = {"phase": "head", "epoch": epoch_idx, "train_loss": train_loss, **val_metrics}
        history.append(row)
        print(row)
        if val_metrics["accuracy"] > best_acc:
            best_acc = val_metrics["accuracy"]
            save_checkpoint(out_dir / "best.pt", model, optimizer, epoch_idx, val_metrics, {"backbone": args.backbone})

    unfreeze_teacher_tail(model, args.unfreeze_blocks)
    optimizer = torch.optim.AdamW((p for p in model.parameters() if p.requires_grad), lr=args.finetune_lr, weight_decay=1e-5)
    for epoch in range(1, args.finetune_epochs + 1):
        epoch_idx += 1
        train_loss = train_one_epoch(model, train_loader, optimizer, device, epoch_idx, args.log_interval)
        val_metrics = evaluate(model, val_loader, device)
        row = {"phase": "finetune", "epoch": epoch_idx, "train_loss": train_loss, **val_metrics}
        history.append(row)
        print(row)
        if val_metrics["accuracy"] > best_acc:
            best_acc = val_metrics["accuracy"]
            save_checkpoint(out_dir / "best.pt", model, optimizer, epoch_idx, val_metrics, {"backbone": args.backbone})

    test_metrics = evaluate(model, test_loader, device)
    history.append({"phase": "test", "epoch": epoch_idx, **test_metrics})
    save_checkpoint(out_dir / "last.pt", model, optimizer, epoch_idx, test_metrics, {"backbone": args.backbone})
    write_metrics(out_dir / "metrics.json", history)
    export_logits(model, train_loader, device, out_dir / "teacher_logits_train.npz")
    export_logits(model, val_loader, device, out_dir / "teacher_logits_val.npz")
    export_logits(model, test_loader, device, out_dir / "teacher_logits_test.npz")
    print(f"test_metrics={test_metrics}")


if __name__ == "__main__":
    main()


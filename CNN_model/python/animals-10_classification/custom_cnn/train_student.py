"""Train the RTL-compatible Animals-10 student CNN in PyTorch."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from animals10_common import DEFAULT_SEED, STUDENT_INPUT_SIZE, count_parameters, ensure_dir, save_json, set_reproducible_seed
from animals10_data import build_animals10_loaders, create_split_manifest
from animals10_models import build_student
from animals10_train import benchmark, evaluate, save_checkpoint, train_one_epoch, write_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train Animals-10 Student CNN Version A/B.")
    parser.add_argument("--data-root", required=True, help="Animals-10 root, or parent containing raw-img/.")
    parser.add_argument("--manifest", default="../animals10_split_manifest.csv", help="Fixed split manifest CSV.")
    parser.add_argument("--make-split", action="store_true", help="Create or replace the manifest before training.")
    parser.add_argument("--variant", choices=("A", "B"), default="A")
    parser.add_argument("--out-dir", default="runs/student_a")
    parser.add_argument("--input-size", type=int, default=STUDENT_INPUT_SIZE)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-batch-size", type=int, default=128)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--dropout", type=float, default=0.20)
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
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

    train_loader, val_loader, test_loader = build_animals10_loaders(
        data_root=args.data_root,
        manifest_path=manifest,
        input_size=args.input_size,
        batch_size=args.batch_size,
        eval_batch_size=args.eval_batch_size,
        model_family="student",
        num_workers=args.num_workers,
    )

    device = torch.device(args.device)
    model = build_student(args.variant, dropout=args.dropout).to(device)
    total_params = count_parameters(model)
    print(model)
    print(f"student_variant={args.variant}")
    print(f"parameters={total_params}")

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(1, args.epochs))
    history: list[dict[str, float | int | str]] = []
    best_acc = -1.0

    for epoch in range(1, args.epochs + 1):
        train_loss = train_one_epoch(model, train_loader, optimizer, device, epoch, args.log_interval)
        scheduler.step()
        val_metrics = evaluate(model, val_loader, device)
        row = {"phase": "train", "epoch": epoch, "train_loss": train_loss, **val_metrics}
        history.append(row)
        print(row)
        if val_metrics["accuracy"] > best_acc:
            best_acc = val_metrics["accuracy"]
            save_checkpoint(
                out_dir / "best.pt",
                model,
                optimizer,
                epoch,
                val_metrics,
                {"variant": args.variant, "input_size": args.input_size, "parameters": total_params},
            )

    test_metrics = evaluate(model, test_loader, device)
    bench = benchmark(model, (1, 3, args.input_size, args.input_size), device=device)
    history.append({"phase": "test", "epoch": args.epochs, **test_metrics, **bench})
    save_checkpoint(
        out_dir / "last.pt",
        model,
        optimizer,
        args.epochs,
        test_metrics,
        {"variant": args.variant, "input_size": args.input_size, "parameters": total_params},
    )
    write_metrics(out_dir / "metrics.json", history)
    print(f"test_metrics={test_metrics}")
    print(f"benchmark={bench}")


if __name__ == "__main__":
    main()


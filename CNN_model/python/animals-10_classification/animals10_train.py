"""Shared PyTorch training and evaluation helpers for Animals-10."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn as nn

from animals10_common import ensure_dir, save_json


def train_one_epoch(
    model: nn.Module,
    loader,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
    epoch: int,
    log_interval: int,
) -> float:
    model.train()
    criterion = nn.CrossEntropyLoss()
    running_loss = 0.0
    total = 0

    for batch_idx, (images, labels) in enumerate(loader):
        images = images.to(device, non_blocking=True)
        labels = labels.to(device, non_blocking=True)
        optimizer.zero_grad(set_to_none=True)
        logits = model(images)
        loss = criterion(logits, labels)
        loss.backward()
        optimizer.step()

        batch_size = images.size(0)
        running_loss += loss.item() * batch_size
        total += batch_size
        if log_interval > 0 and batch_idx % log_interval == 0:
            print(f"epoch={epoch} batch={batch_idx}/{len(loader)} loss={loss.item():.5f}")

    return running_loss / max(1, total)


def evaluate(model: nn.Module, loader, device: torch.device) -> dict[str, float]:
    model.eval()
    criterion = nn.CrossEntropyLoss(reduction="sum")
    loss_sum = 0.0
    correct = 0
    total = 0

    with torch.inference_mode():
        for images, labels in loader:
            images = images.to(device, non_blocking=True)
            labels = labels.to(device, non_blocking=True)
            logits = model(images)
            loss_sum += criterion(logits, labels).item()
            correct += (logits.argmax(dim=1) == labels).sum().item()
            total += labels.numel()

    return {
        "loss": loss_sum / max(1, total),
        "accuracy": correct / max(1, total),
        "correct": float(correct),
        "total": float(total),
    }


def benchmark(model: nn.Module, input_shape: tuple[int, int, int, int], device: torch.device, repeats: int = 200) -> dict[str, float]:
    model.eval()
    sample = torch.randn(input_shape, device=device)
    with torch.inference_mode():
        for _ in range(20):
            model(sample)
        if device.type == "cuda":
            torch.cuda.synchronize()
        start = time.perf_counter()
        for _ in range(repeats):
            model(sample)
        if device.type == "cuda":
            torch.cuda.synchronize()
        elapsed = time.perf_counter() - start
    images = input_shape[0] * repeats
    return {
        "ms_per_image": elapsed * 1000.0 / images,
        "images_per_second": images / elapsed,
    }


def save_checkpoint(
    path: str | Path,
    model: nn.Module,
    optimizer: torch.optim.Optimizer | None,
    epoch: int,
    metrics: dict[str, Any],
    extra: dict[str, Any] | None = None,
) -> None:
    payload: dict[str, Any] = {
        "model_state": model.state_dict(),
        "epoch": epoch,
        "metrics": metrics,
    }
    if optimizer is not None:
        payload["optimizer_state"] = optimizer.state_dict()
    if extra:
        payload.update(extra)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(payload, path)


def export_logits(model: nn.Module, loader, device: torch.device, out_path: str | Path) -> None:
    model.eval()
    logits_out: list[np.ndarray] = []
    labels_out: list[np.ndarray] = []
    with torch.inference_mode():
        for images, labels in loader:
            logits = model(images.to(device, non_blocking=True)).detach().cpu().numpy()
            logits_out.append(logits)
            labels_out.append(labels.numpy())
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(out_path, logits=np.concatenate(logits_out, axis=0), labels=np.concatenate(labels_out, axis=0))


def write_metrics(path: str | Path, history: list[dict[str, Any]]) -> None:
    ensure_dir(Path(path).parent)
    save_json(path, {"history": history})


"""Train, quantize, evaluate, and benchmark the 4,996-parameter MNIST CNN."""

from __future__ import annotations

import argparse
import copy
import os
import time
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.ao.quantization import (
    DeQuantStub,
    QuantStub,
    convert,
    get_default_qat_qconfig,
    prepare_qat,
)
from torch.utils.data import DataLoader
from torchvision import datasets, transforms


class CNN(nn.Module):
    """Small MNIST CNN with 4,996 trainable parameters."""

    def __init__(self) -> None:
        super().__init__()

        self.conv1 = nn.Conv2d(1, 8, kernel_size=3)  # 80 params, output: 8x26x26
        self.conv2 = nn.Conv2d(8, 10, kernel_size=3)  # 730 params, output: 10x11x11
        self.mp = nn.MaxPool2d(2)
        self.fc1 = nn.Linear(10 * 5 * 5, 16)  # 4,016 params
        self.fc2 = nn.Linear(16, 10)  # 170 params

        self.quant = QuantStub()
        self.dequant = DeQuantStub()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.quant(x)
        x = self.mp(F.relu(self.conv1(x)))  # 8x13x13
        x = self.mp(F.relu(self.conv2(x)))  # 10x5x5
        x = x.reshape(x.size(0), -1)
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        x = self.dequant(x)
        return F.log_softmax(x, dim=1)


def build_transform(augment: bool = False, normalize: bool = False) -> transforms.Compose:
    transform_steps: list[object] = []
    if augment:
        transform_steps.append(transforms.RandomAffine(degrees=15, translate=(0.1, 0.1)))
    transform_steps.append(transforms.ToTensor())
    if normalize:
        transform_steps.append(transforms.Normalize((0.1307,), (0.3081,)))
    return transforms.Compose(transform_steps)


def build_loaders(
    data_dir: str | Path,
    batch_size: int,
    test_batch_size: int,
    augment: bool = False,
    normalize: bool = False,
    download: bool = True,
) -> tuple[DataLoader, DataLoader]:
    train_dataset = datasets.MNIST(
        root=str(data_dir),
        train=True,
        transform=build_transform(augment=augment, normalize=normalize),
        download=download,
    )
    test_dataset = datasets.MNIST(
        root=str(data_dir),
        train=False,
        transform=build_transform(augment=False, normalize=normalize),
        download=download,
    )

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    test_loader = DataLoader(test_dataset, batch_size=test_batch_size, shuffle=False)
    return train_loader, test_loader


def count_parameters(model: nn.Module) -> int:
    return sum(parameter.numel() for parameter in model.parameters())


def model_size_kb(model: nn.Module, filename: str | Path = "temp.p") -> float:
    path = Path(filename)
    torch.save(model.state_dict(), path)
    try:
        return os.path.getsize(path) / 1024
    finally:
        path.unlink(missing_ok=True)


def export_weights_to_txt(
    model: CNN,
    filename: str | Path,
    layout: str = "c",
    precision: int = 10,
) -> int:
    """Export model weights and biases to a text file.

    The default "c" layout matches CNN_model/C/float32/Float_Weights.txt:
    conv weights are output-major, dense weights are input-major, and each
    layer's bias follows its weights.
    """
    if layout not in {"c", "pytorch"}:
        raise ValueError(f"Unsupported weight export layout: {layout}")

    if layout == "c":
        tensors = [
            model.conv1.weight.detach().cpu().reshape(-1),
            model.conv1.bias.detach().cpu().reshape(-1),
            model.conv2.weight.detach().cpu().reshape(-1),
            model.conv2.bias.detach().cpu().reshape(-1),
            model.fc1.weight.detach().cpu().t().contiguous().reshape(-1),
            model.fc1.bias.detach().cpu().reshape(-1),
            model.fc2.weight.detach().cpu().t().contiguous().reshape(-1),
            model.fc2.bias.detach().cpu().reshape(-1),
        ]
    else:
        tensors = [parameter.detach().cpu().reshape(-1) for parameter in model.parameters()]

    weights = torch.cat(tensors).to(torch.float32)
    expected_count = count_parameters(model)
    if weights.numel() != expected_count:
        raise RuntimeError(f"Expected {expected_count} exported values, got {weights.numel()}")

    path = Path(filename)
    path.parent.mkdir(parents=True, exist_ok=True)
    value_format = f"{{:.{precision}g}}"
    with path.open("w", encoding="utf-8") as weights_file:
        for value in weights.tolist():
            weights_file.write(value_format.format(value) + "\n")

    return weights.numel()


def train_epoch(
    model: nn.Module,
    train_loader: DataLoader,
    optimizer: optim.Optimizer,
    epoch: int,
    device: torch.device,
    log_interval: int,
) -> float:
    model.train()
    running_loss = 0.0

    for batch_idx, (data, target) in enumerate(train_loader):
        data = data.to(device)
        target = target.to(device)

        optimizer.zero_grad(set_to_none=True)
        output = model(data)
        loss = F.nll_loss(output, target)
        loss.backward()
        optimizer.step()

        running_loss += loss.item() * data.size(0)
        if log_interval > 0 and batch_idx % log_interval == 0:
            processed = batch_idx * len(data)
            total = len(train_loader.dataset)
            percent = 100.0 * batch_idx / len(train_loader)
            print(
                f"Train Epoch: {epoch} [{processed}/{total} ({percent:.0f}%)]"
                f"\tLoss: {loss.item():.6f}"
            )

    return running_loss / len(train_loader.dataset)


def evaluate(model: nn.Module, test_loader: DataLoader, device: torch.device) -> tuple[float, int, float]:
    model.eval()
    test_loss = 0.0
    correct = 0

    with torch.inference_mode():
        for data, target in test_loader:
            data = data.to(device)
            target = target.to(device)
            output = model(data)

            test_loss += F.nll_loss(output, target, reduction="sum").item()
            pred = output.argmax(dim=1)
            correct += pred.eq(target).sum().item()

    test_loss /= len(test_loader.dataset)
    accuracy = 100.0 * correct / len(test_loader.dataset)
    print(
        f"\nTest set: Average loss: {test_loss:.4f}, "
        f"Accuracy: {correct}/{len(test_loader.dataset)} ({accuracy:.2f}%)\n"
    )
    return test_loss, correct, accuracy


def benchmark_inference(
    model: nn.Module,
    device: torch.device,
    batch_size: int = 1,
    warmup: int = 100,
    repeats: int = 1000,
) -> tuple[float, float]:
    model.eval()
    sample = torch.randn(batch_size, 1, 28, 28, device=device)

    with torch.inference_mode():
        for _ in range(warmup):
            model(sample)

        start = time.perf_counter()
        for _ in range(repeats):
            model(sample)
        elapsed_s = time.perf_counter() - start

    images = batch_size * repeats
    ms_per_image = elapsed_s * 1000 / images
    images_per_second = images / elapsed_s
    return ms_per_image, images_per_second


def train_float_model(
    model: nn.Module,
    train_loader: DataLoader,
    test_loader: DataLoader,
    device: torch.device,
    epochs: int,
    lr: float,
    momentum: float,
    log_interval: int,
) -> nn.Module:
    optimizer = optim.SGD(model.parameters(), lr=lr, momentum=momentum)
    scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=10, gamma=0.1)

    for epoch in range(1, epochs + 1):
        train_epoch(model, train_loader, optimizer, epoch, device, log_interval)
        scheduler.step()
        evaluate(model, test_loader, device)

    return model


def train_qat_model(
    model: nn.Module,
    train_loader: DataLoader,
    test_loader: DataLoader,
    device: torch.device,
    epochs: int,
    lr: float,
    momentum: float,
    log_interval: int,
    qconfig_backend: str,
) -> nn.Module:
    if qconfig_backend in torch.backends.quantized.supported_engines:
        torch.backends.quantized.engine = qconfig_backend

    qat_model = copy.deepcopy(model)
    qat_model.qconfig = get_default_qat_qconfig(qconfig_backend)
    qat_model.train()
    prepared_model = prepare_qat(qat_model).to(device)
    optimizer = optim.SGD(prepared_model.parameters(), lr=lr, momentum=momentum)

    for epoch in range(1, epochs + 1):
        train_epoch(prepared_model, train_loader, optimizer, epoch, device, log_interval)
        evaluate(prepared_model, test_loader, device)

    return prepared_model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train and benchmark the small MNIST CNN.")
    parser.add_argument("--data-dir", default="./data", help="MNIST dataset directory.")
    parser.add_argument("--batch-size", type=int, default=64, help="Training batch size.")
    parser.add_argument("--test-batch-size", type=int, default=64, help="Evaluation batch size.")
    parser.add_argument("--epochs", type=int, default=14, help="Float training epochs.")
    parser.add_argument("--qat-epochs", type=int, default=10, help="QAT fine-tuning epochs.")
    parser.add_argument("--lr", type=float, default=0.01, help="Float training learning rate.")
    parser.add_argument("--qat-lr", type=float, default=1e-4, help="QAT fine-tuning learning rate.")
    parser.add_argument("--momentum", type=float, default=0.9, help="SGD momentum.")
    parser.add_argument("--seed", type=int, default=1, help="Random seed.")
    parser.add_argument("--device", default="cpu", help="Training device, for example cpu or cuda.")
    parser.add_argument("--augment", action="store_true", help="Use affine augmentation for training.")
    parser.add_argument("--normalize", action="store_true", help="Apply MNIST mean/std normalization.")
    parser.add_argument("--no-download", action="store_true", help="Do not download MNIST.")
    parser.add_argument("--log-interval", type=int, default=10, help="Training log interval; 0 disables logs.")
    parser.add_argument("--save-float", default="", help="Optional path to save the trained float state_dict.")
    parser.add_argument("--save-int8", default="", help="Optional path to save the converted int8 state_dict.")
    parser.add_argument("--export-float-weights", default="", help="Optional path to export trained float weights as text.")
    parser.add_argument("--export-qat-weights", default="", help="Optional path to export QAT fine-tuned weights as text.")
    parser.add_argument(
        "--export-layout",
        choices=("c", "pytorch"),
        default="c",
        help="Text export order. 'c' matches CNN_model/C/float32/Float_Weights.txt.",
    )
    parser.add_argument("--export-precision", type=int, default=10, help="Significant digits for text weight export.")
    parser.add_argument("--benchmark-repeats", type=int, default=1000, help="Inference benchmark repeats.")
    parser.add_argument("--benchmark-batch-size", type=int, default=1, help="Inference benchmark batch size.")
    parser.add_argument("--qconfig-backend", default="fbgemm", help="QAT qconfig backend.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    device = torch.device(args.device)

    train_loader, test_loader = build_loaders(
        data_dir=args.data_dir,
        batch_size=args.batch_size,
        test_batch_size=args.test_batch_size,
        augment=args.augment,
        normalize=args.normalize,
        download=not args.no_download,
    )

    model = CNN().to(device)
    total_params = count_parameters(model)
    if total_params != 4996:
        raise RuntimeError(f"Expected 4,996 parameters, got {total_params}")

    print(model)
    print(f"Number of parameters: {total_params}")

    train_float_model(
        model=model,
        train_loader=train_loader,
        test_loader=test_loader,
        device=device,
        epochs=args.epochs,
        lr=args.lr,
        momentum=args.momentum,
        log_interval=args.log_interval,
    )

    _float_loss, float_correct, float_accuracy = evaluate(model, test_loader, device)
    float_ms, float_ips = benchmark_inference(
        model,
        device=device,
        batch_size=args.benchmark_batch_size,
        repeats=args.benchmark_repeats,
    )
    print(f"Float accuracy: {float_correct}/{len(test_loader.dataset)} ({float_accuracy:.2f}%)")
    print(f"Float inference: {float_ms:.6f} ms/image, {float_ips:.2f} images/s")

    if args.save_float:
        torch.save(model.state_dict(), args.save_float)

    if args.export_float_weights:
        exported_count = export_weights_to_txt(
            model,
            args.export_float_weights,
            layout=args.export_layout,
            precision=args.export_precision,
        )
        print(f"Exported {exported_count} float weight/bias values to {args.export_float_weights}")

    prepared_model = train_qat_model(
        model=model,
        train_loader=train_loader,
        test_loader=test_loader,
        device=device,
        epochs=args.qat_epochs,
        lr=args.qat_lr,
        momentum=args.momentum,
        log_interval=args.log_interval,
        qconfig_backend=args.qconfig_backend,
    )

    _qat_loss, qat_correct, qat_accuracy = evaluate(prepared_model, test_loader, device)
    print(f"QAT accuracy before convert: {qat_correct}/{len(test_loader.dataset)} ({qat_accuracy:.2f}%)")

    if args.export_qat_weights:
        exported_count = export_weights_to_txt(
            prepared_model,
            args.export_qat_weights,
            layout=args.export_layout,
            precision=args.export_precision,
        )
        print(f"Exported {exported_count} QAT weight/bias values to {args.export_qat_weights}")

    model_int8 = convert(prepared_model.to("cpu").eval())
    _int8_loss, int8_correct, int8_accuracy = evaluate(model_int8, test_loader, torch.device("cpu"))
    int8_ms, int8_ips = benchmark_inference(
        model_int8,
        device=torch.device("cpu"),
        batch_size=args.benchmark_batch_size,
        repeats=args.benchmark_repeats,
    )
    print(f"INT8 accuracy: {int8_correct}/{len(test_loader.dataset)} ({int8_accuracy:.2f}%)")
    print(f"INT8 inference: {int8_ms:.6f} ms/image, {int8_ips:.2f} images/s")
    print(f"Float model size: {model_size_kb(model, 'float.p'):.3f} KB")
    print(f"INT8 model size: {model_size_kb(model_int8, 'int8.p'):.3f} KB")

    if args.save_int8:
        torch.save(model_int8.state_dict(), args.save_int8)


if __name__ == "__main__":
    main()

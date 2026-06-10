"""PyTorch teacher and RTL-compatible student models for Animals-10."""

from __future__ import annotations

from collections import OrderedDict
from typing import Literal

import torch
import torch.nn as nn
from torchvision import models


StudentVariant = Literal["A", "B"]


class StudentCNNVersionA(nn.Module):
    """First RTL target: Conv/BN/ReLU/Pool/GAP/Dense only."""

    def __init__(self, num_classes: int = 10, dropout: float = 0.20) -> None:
        super().__init__()
        self.features = nn.Sequential(
            OrderedDict(
                [
                    ("b1_conv1", nn.Conv2d(3, 32, kernel_size=3, padding=1, bias=False)),
                    ("b1_bn1", nn.BatchNorm2d(32)),
                    ("b1_relu1", nn.ReLU(inplace=False)),
                    ("b1_conv2", nn.Conv2d(32, 32, kernel_size=3, padding=1, bias=False)),
                    ("b1_bn2", nn.BatchNorm2d(32)),
                    ("b1_relu2", nn.ReLU(inplace=False)),
                    ("pool1", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b2_conv1", nn.Conv2d(32, 64, kernel_size=3, padding=1, bias=False)),
                    ("b2_bn1", nn.BatchNorm2d(64)),
                    ("b2_relu1", nn.ReLU(inplace=False)),
                    ("b2_conv2", nn.Conv2d(64, 64, kernel_size=3, padding=1, bias=False)),
                    ("b2_bn2", nn.BatchNorm2d(64)),
                    ("b2_relu2", nn.ReLU(inplace=False)),
                    ("pool2", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b3_conv1", nn.Conv2d(64, 128, kernel_size=3, padding=1, bias=False)),
                    ("b3_bn1", nn.BatchNorm2d(128)),
                    ("b3_relu1", nn.ReLU(inplace=False)),
                    ("b3_conv2", nn.Conv2d(128, 128, kernel_size=3, padding=1, bias=False)),
                    ("b3_bn2", nn.BatchNorm2d(128)),
                    ("b3_relu2", nn.ReLU(inplace=False)),
                    ("pool3", nn.MaxPool2d(kernel_size=2, stride=2)),
                ]
            )
        )
        self.gap = nn.AdaptiveAvgPool2d((1, 1))
        self.fc1 = nn.Linear(128, 128)
        self.fc1_relu = nn.ReLU(inplace=False)
        self.dropout = nn.Dropout(dropout)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = self.gap(x)
        x = torch.flatten(x, 1)
        x = self.fc1_relu(self.fc1(x))
        x = self.dropout(x)
        return self.fc2(x)


class StudentCNNVersionB(nn.Module):
    """Pointwise-enhanced future student. Not the first RTL target."""

    def __init__(self, num_classes: int = 10, dropout: float = 0.20) -> None:
        super().__init__()
        self.features = nn.Sequential(
            OrderedDict(
                [
                    ("b1_conv3x3", nn.Conv2d(3, 32, kernel_size=3, padding=1, bias=False)),
                    ("b1_bn3x3", nn.BatchNorm2d(32)),
                    ("b1_relu3x3", nn.ReLU(inplace=False)),
                    ("b1_conv1x1", nn.Conv2d(32, 32, kernel_size=1, padding=0, bias=False)),
                    ("b1_bn1x1", nn.BatchNorm2d(32)),
                    ("b1_relu1x1", nn.ReLU(inplace=False)),
                    ("pool1", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b2_conv3x3", nn.Conv2d(32, 64, kernel_size=3, padding=1, bias=False)),
                    ("b2_bn3x3", nn.BatchNorm2d(64)),
                    ("b2_relu3x3", nn.ReLU(inplace=False)),
                    ("b2_conv1x1", nn.Conv2d(64, 64, kernel_size=1, padding=0, bias=False)),
                    ("b2_bn1x1", nn.BatchNorm2d(64)),
                    ("b2_relu1x1", nn.ReLU(inplace=False)),
                    ("pool2", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b3_conv3x3", nn.Conv2d(64, 128, kernel_size=3, padding=1, bias=False)),
                    ("b3_bn3x3", nn.BatchNorm2d(128)),
                    ("b3_relu3x3", nn.ReLU(inplace=False)),
                    ("b3_conv1x1", nn.Conv2d(128, 128, kernel_size=1, padding=0, bias=False)),
                    ("b3_bn1x1", nn.BatchNorm2d(128)),
                    ("b3_relu1x1", nn.ReLU(inplace=False)),
                    ("pool3", nn.MaxPool2d(kernel_size=2, stride=2)),
                ]
            )
        )
        self.gap = nn.AdaptiveAvgPool2d((1, 1))
        self.fc = nn.Linear(128, num_classes)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = self.gap(x)
        x = torch.flatten(x, 1)
        x = self.dropout(x)
        return self.fc(x)


class StudentCNNVersionAFolded(nn.Module):
    """BatchNorm-folded inference graph for Student A."""

    def __init__(self, num_classes: int = 10) -> None:
        super().__init__()
        self.features = nn.Sequential(
            OrderedDict(
                [
                    ("b1_conv1", nn.Conv2d(3, 32, kernel_size=3, padding=1, bias=True)),
                    ("b1_relu1", nn.ReLU(inplace=False)),
                    ("b1_conv2", nn.Conv2d(32, 32, kernel_size=3, padding=1, bias=True)),
                    ("b1_relu2", nn.ReLU(inplace=False)),
                    ("pool1", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b2_conv1", nn.Conv2d(32, 64, kernel_size=3, padding=1, bias=True)),
                    ("b2_relu1", nn.ReLU(inplace=False)),
                    ("b2_conv2", nn.Conv2d(64, 64, kernel_size=3, padding=1, bias=True)),
                    ("b2_relu2", nn.ReLU(inplace=False)),
                    ("pool2", nn.MaxPool2d(kernel_size=2, stride=2)),
                    ("b3_conv1", nn.Conv2d(64, 128, kernel_size=3, padding=1, bias=True)),
                    ("b3_relu1", nn.ReLU(inplace=False)),
                    ("b3_conv2", nn.Conv2d(128, 128, kernel_size=3, padding=1, bias=True)),
                    ("b3_relu2", nn.ReLU(inplace=False)),
                    ("pool3", nn.MaxPool2d(kernel_size=2, stride=2)),
                ]
            )
        )
        self.gap = nn.AdaptiveAvgPool2d((1, 1))
        self.fc1 = nn.Linear(128, 128)
        self.fc1_relu = nn.ReLU(inplace=False)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        trace = self.forward_trace(x)
        return trace["logits"]

    def forward_trace(self, x: torch.Tensor) -> OrderedDict[str, torch.Tensor]:
        trace: OrderedDict[str, torch.Tensor] = OrderedDict()
        trace["input"] = x
        for name, module in self.features.named_children():
            x = module(x)
            trace[name] = x
        x = self.gap(x)
        trace["gap"] = x
        x = torch.flatten(x, 1)
        trace["flatten"] = x
        x = self.fc1(x)
        trace["fc1"] = x
        x = self.fc1_relu(x)
        trace["fc1_relu"] = x
        x = self.fc2(x)
        trace["logits"] = x
        return trace


def build_student(variant: StudentVariant = "A", num_classes: int = 10, dropout: float = 0.20) -> nn.Module:
    if variant == "A":
        return StudentCNNVersionA(num_classes=num_classes, dropout=dropout)
    if variant == "B":
        return StudentCNNVersionB(num_classes=num_classes, dropout=dropout)
    raise ValueError(f"Unsupported student variant: {variant}")


def _fold_conv_bn(conv: nn.Conv2d, bn: nn.BatchNorm2d) -> tuple[torch.Tensor, torch.Tensor]:
    if conv.bias is None:
        bias = torch.zeros(conv.weight.size(0), dtype=conv.weight.dtype, device=conv.weight.device)
    else:
        bias = conv.bias.detach()

    weight = conv.weight.detach()
    gamma = bn.weight.detach()
    beta = bn.bias.detach()
    mean = bn.running_mean.detach()
    var = bn.running_var.detach()
    scale = gamma / torch.sqrt(var + bn.eps)
    folded_weight = weight * scale.reshape(-1, 1, 1, 1)
    folded_bias = beta + (bias - mean) * scale
    return folded_weight, folded_bias


def fold_student_a(model: StudentCNNVersionA) -> StudentCNNVersionAFolded:
    model.eval()
    folded = StudentCNNVersionAFolded(num_classes=model.fc2.out_features)
    conv_bn_pairs = [
        ("b1_conv1", "b1_bn1"),
        ("b1_conv2", "b1_bn2"),
        ("b2_conv1", "b2_bn1"),
        ("b2_conv2", "b2_bn2"),
        ("b3_conv1", "b3_bn1"),
        ("b3_conv2", "b3_bn2"),
    ]
    with torch.no_grad():
        for conv_name, bn_name in conv_bn_pairs:
            weight, bias = _fold_conv_bn(
                model.features._modules[conv_name],
                model.features._modules[bn_name],
            )
            folded_conv = folded.features._modules[conv_name]
            folded_conv.weight.copy_(weight)
            folded_conv.bias.copy_(bias)
        folded.fc1.weight.copy_(model.fc1.weight)
        folded.fc1.bias.copy_(model.fc1.bias)
        folded.fc2.weight.copy_(model.fc2.weight)
        folded.fc2.bias.copy_(model.fc2.bias)
    folded.eval()
    return folded


def build_teacher(
    backbone: Literal["b0", "b1", "b2"],
    num_classes: int = 10,
    pretrained: bool = True,
    freeze_backbone: bool = True,
) -> nn.Module:
    if backbone == "b0":
        weights = models.EfficientNet_B0_Weights.DEFAULT if pretrained else None
        model = models.efficientnet_b0(weights=weights)
    elif backbone == "b1":
        weights = models.EfficientNet_B1_Weights.DEFAULT if pretrained else None
        model = models.efficientnet_b1(weights=weights)
    elif backbone == "b2":
        weights = models.EfficientNet_B2_Weights.DEFAULT if pretrained else None
        model = models.efficientnet_b2(weights=weights)
    else:
        raise ValueError(f"Unsupported EfficientNet backbone: {backbone}")

    if freeze_backbone:
        for parameter in model.features.parameters():
            parameter.requires_grad = False

    in_features = model.classifier[-1].in_features
    model.classifier = nn.Sequential(
        nn.Dropout(p=0.20, inplace=False),
        nn.Linear(in_features, num_classes),
    )
    return model


def unfreeze_teacher_tail(model: nn.Module, block_count: int) -> None:
    if block_count <= 0:
        return
    for block in list(model.features.children())[-block_count:]:
        for parameter in block.parameters():
            parameter.requires_grad = True


from pathlib import Path
import argparse
import numpy as np

WEIGHTS_FILE = "small_cnn_sym_weights_i8_c_order.txt"
BIASES_FILE = "small_cnn_sym_biases_i32_c_order.txt"
REQUANT_MULT_FILE = "small_cnn_sym_requant_mult_i32_c_order.txt"
REQUANT_SHIFT_FILE = "small_cnn_sym_requant_shift_u6_c_order.txt"
QPARAMS_FILE = "small_cnn_sym_qparams.txt"

WEIGHT_BASES = {"conv1": 0, "conv2": 72, "fc1": 792, "fc2": 4792}
BIAS_BASES = {"conv1": 0, "conv2": 8, "fc1": 18, "fc2": 34}
DEBUG_FILES = {
    "input": "input_image_i8.hex",
    "layer0_acc": "layer0_conv_acc_i32.hex",
    "layer0_out": "layer0_out_i8.hex",
    "layer1_acc": "layer1_conv_acc_i32.hex",
    "layer1_out": "layer1_out_i8.hex",
    "layer2_acc": "layer2_fc_acc_i32.hex",
    "layer2_out": "layer2_out_i8.hex",
    "layer3_acc": "layer3_fc_acc_i32.hex",
    "final_logits": "final_logits_i8.hex",
}


def read_int_file(path):
    return [int(line.strip()) for line in Path(path).read_text().splitlines() if line.strip()]


def hex_to_signed(token, bits):
    value = int(token.strip(), 16)
    sign_bit = 1 << (bits - 1)
    if value & sign_bit:
        value -= 1 << bits
    return value


def read_hex_file(path, bits):
    return [hex_to_signed(line, bits) for line in Path(path).read_text().splitlines() if line.strip()]


def signed_to_hex(value, bits):
    return f"{int(value) & ((1 << bits) - 1):0{bits // 4}x}"


def write_hex_file(path, values, bits):
    flat = np.asarray(values).reshape(-1)
    Path(path).write_text("".join(f"{signed_to_hex(value, bits)}\n" for value in flat))


def load_qparams(export_dir):
    qparams = {}
    path = Path(export_dir) / QPARAMS_FILE
    if not path.exists():
        return qparams
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        qparams[key.strip()] = value.strip()
    return qparams


def symmetric_quantize_float(array, scale):
    q = np.rint(np.asarray(array, dtype=np.float64) / float(scale))
    return np.clip(q, -128, 127).astype(np.int8)


def load_exported_state(export_dir):
    export_dir = Path(export_dir)
    weights = read_int_file(export_dir / WEIGHTS_FILE)
    biases = read_int_file(export_dir / BIASES_FILE)
    multipliers = read_int_file(export_dir / REQUANT_MULT_FILE)
    shifts = read_int_file(export_dir / REQUANT_SHIFT_FILE)

    if len(weights) != 4952:
        raise ValueError(f"Expected 4952 weights, got {len(weights)}")
    if len(biases) != 44 or len(multipliers) != 44 or len(shifts) != 44:
        raise ValueError("Expected 44 biases, 44 multipliers, and 44 shifts")

    conv1_w = np.asarray(weights[0:72], dtype=np.int8).reshape(8, 1, 3, 3)
    conv2_w = np.asarray(weights[72:792], dtype=np.int8).reshape(10, 8, 3, 3)
    fc1_w = np.asarray(weights[792:4792], dtype=np.int8).reshape(250, 16).T.copy()
    fc2_w = np.asarray(weights[4792:4952], dtype=np.int8).reshape(16, 10).T.copy()

    return {
        "conv1": {
            "weight_q": conv1_w,
            "bias_q": np.asarray(biases[0:8], dtype=np.int32),
            "requant_multiplier": np.asarray(multipliers[0:8], dtype=np.int32),
            "requant_shift": np.asarray(shifts[0:8], dtype=np.int64),
        },
        "conv2": {
            "weight_q": conv2_w,
            "bias_q": np.asarray(biases[8:18], dtype=np.int32),
            "requant_multiplier": np.asarray(multipliers[8:18], dtype=np.int32),
            "requant_shift": np.asarray(shifts[8:18], dtype=np.int64),
        },
        "fc1": {
            "weight_q": fc1_w,
            "bias_q": np.asarray(biases[18:34], dtype=np.int32),
            "requant_multiplier": np.asarray(multipliers[18:34], dtype=np.int32),
            "requant_shift": np.asarray(shifts[18:34], dtype=np.int64),
        },
        "fc2": {
            "weight_q": fc2_w,
            "bias_q": np.asarray(biases[34:44], dtype=np.int32),
            "requant_multiplier": np.asarray(multipliers[34:44], dtype=np.int32),
            "requant_shift": np.asarray(shifts[34:44], dtype=np.int64),
        },
    }


def rtl_round_shift_array(values, shift):
    shift = int(np.asarray(shift).reshape(-1)[0])
    values = np.asarray(values, dtype=np.int64)
    if shift == 0:
        return values
    offset = np.int64(1 << (shift - 1))
    return np.where(values >= 0, (values + offset) >> shift, (values - offset) >> shift)


def conv2d_acc_i32(input_i8, weight_i8):
    x = np.asarray(input_i8, dtype=np.int32)
    w = np.asarray(weight_i8, dtype=np.int32)
    kh, kw = w.shape[2], w.shape[3]
    windows = np.lib.stride_tricks.sliding_window_view(x, (kh, kw), axis=(1, 2))
    return np.tensordot(w, windows, axes=([1, 2, 3], [0, 3, 4])).astype(np.int32)


def fc_acc_i32(input_i8, weight_i8):
    return (np.asarray(weight_i8, dtype=np.int32) @ np.asarray(input_i8, dtype=np.int32)).astype(np.int32)


def requantize_i8(acc_i32, bias_i32, multiplier_i32, shift_u6, relu=False):
    acc = np.asarray(acc_i32, dtype=np.int64)
    bias = np.asarray(bias_i32, dtype=np.int64).reshape((-1,) + (1,) * (acc.ndim - 1))
    mult = np.asarray(multiplier_i32, dtype=np.int64).reshape((-1,) + (1,) * (acc.ndim - 1))
    tmp = acc + bias
    scaled = rtl_round_shift_array(tmp * mult, shift_u6)
    clipped = np.clip(scaled, -128, 127)
    if relu:
        clipped = np.maximum(clipped, 0)
    return clipped.astype(np.int8)


def maxpool2d_i8(input_i8):
    x = np.asarray(input_i8, dtype=np.int8)
    channels, height, width = x.shape
    out_h, out_w = height // 2, width // 2
    x = x[:, : out_h * 2, : out_w * 2]
    return x.reshape(channels, out_h, 2, out_w, 2).max(axis=(2, 4)).astype(np.int8)


def infer_i8(state, input_i8):
    debug = {"input": np.asarray(input_i8, dtype=np.int8)}

    conv1_acc = conv2d_acc_i32(debug["input"], state["conv1"]["weight_q"])
    conv1_out = requantize_i8(
        conv1_acc,
        state["conv1"]["bias_q"],
        state["conv1"]["requant_multiplier"],
        state["conv1"]["requant_shift"],
        relu=True,
    )
    pool1 = maxpool2d_i8(conv1_out)

    conv2_acc = conv2d_acc_i32(pool1, state["conv2"]["weight_q"])
    conv2_out = requantize_i8(
        conv2_acc,
        state["conv2"]["bias_q"],
        state["conv2"]["requant_multiplier"],
        state["conv2"]["requant_shift"],
        relu=True,
    )
    pool2 = maxpool2d_i8(conv2_out)

    flat = pool2.reshape(-1)
    fc1_acc = fc_acc_i32(flat, state["fc1"]["weight_q"])
    fc1_out = requantize_i8(
        fc1_acc,
        state["fc1"]["bias_q"],
        state["fc1"]["requant_multiplier"],
        state["fc1"]["requant_shift"],
        relu=True,
    )

    fc2_acc = fc_acc_i32(fc1_out, state["fc2"]["weight_q"])
    logits = requantize_i8(
        fc2_acc,
        state["fc2"]["bias_q"],
        state["fc2"]["requant_multiplier"],
        state["fc2"]["requant_shift"],
        relu=False,
    )

    debug.update({
        "layer0_acc": conv1_acc,
        "layer0_out": conv1_out,
        "layer1_acc": conv2_acc,
        "layer1_out": conv2_out,
        "layer2_acc": fc1_acc,
        "layer2_out": fc1_out,
        "layer3_acc": fc2_acc,
        "final_logits": logits,
    })
    return int(np.argmax(logits)), debug


def write_debug_hex_files(export_dir, debug):
    export_dir = Path(export_dir)
    write_hex_file(export_dir / DEBUG_FILES["input"], debug["input"], 8)
    write_hex_file(export_dir / DEBUG_FILES["layer0_acc"], debug["layer0_acc"], 32)
    write_hex_file(export_dir / DEBUG_FILES["layer0_out"], debug["layer0_out"], 8)
    write_hex_file(export_dir / DEBUG_FILES["layer1_acc"], debug["layer1_acc"], 32)
    write_hex_file(export_dir / DEBUG_FILES["layer1_out"], debug["layer1_out"], 8)
    write_hex_file(export_dir / DEBUG_FILES["layer2_acc"], debug["layer2_acc"], 32)
    write_hex_file(export_dir / DEBUG_FILES["layer2_out"], debug["layer2_out"], 8)
    write_hex_file(export_dir / DEBUG_FILES["layer3_acc"], debug["layer3_acc"], 32)
    write_hex_file(export_dir / DEBUG_FILES["final_logits"], debug["final_logits"], 8)


def main():
    parser = argparse.ArgumentParser(description="Integer-only signed symmetric INT8 inference for small_cnn_4996_params")
    parser.add_argument("--export-dir", default=".", help="Directory containing exported text files")
    parser.add_argument("--input-hex", default="input_image_i8.hex", help="Signed INT8 input hex file")
    parser.add_argument("--input-npy", default=None, help="Optional float input .npy file shaped 1x28x28 or 28x28")
    parser.add_argument("--dump-debug", action="store_true", help="Rewrite layer debug hex files")
    args = parser.parse_args()

    export_dir = Path(args.export_dir)
    state = load_exported_state(export_dir)
    qparams = load_qparams(export_dir)

    if args.input_npy:
        if "activation_scale.input" not in qparams:
            raise ValueError("input .npy quantization requires activation_scale.input in qparams")
        image = np.load(args.input_npy)
        if image.shape == (28, 28):
            image = image.reshape(1, 28, 28)
        input_i8 = symmetric_quantize_float(image, float(qparams["activation_scale.input"]))
    else:
        input_values = read_hex_file(export_dir / args.input_hex, 8)
        input_i8 = np.asarray(input_values, dtype=np.int8).reshape(1, 28, 28)

    prediction, debug = infer_i8(state, input_i8)
    print(f"prediction={prediction}")
    print("final_logits_i8=" + " ".join(str(int(value)) for value in debug["final_logits"].reshape(-1)))

    if args.dump_debug:
        write_debug_hex_files(export_dir, debug)


if __name__ == "__main__":
    main()

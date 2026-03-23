import os

# Configuration for Q3.12 (2^12 = 4096)
FRAC_BITS = 12
SCALE = 1 << FRAC_BITS 

def float_to_q312(value_str):
    """Converts a float string to a signed 16-bit integer in Q3.12."""
    try:
        # Using float conversion first to handle scientific notation if present
        val = float(value_str)
        scaled = round(val * SCALE)
        # Clamp to 16-bit signed integer range (-32768 to 32767)
        return max(min(scaled, 32767), -32768)
    except ValueError:
        return 0

def convert_normalized_file(input_path, output_path):
    """Processes space-separated float files and outputs space-separated Q3.12 integers."""
    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found.")
        return

    print(f"Processing {input_path}...")
    count = 0
    with open(input_path, 'r') as f_in, open(output_path, 'w') as f_out:
        for line in f_in:
            line = line.strip()
            if not line:
                continue
            
            # .split() with no arguments handles any amount of whitespace (spaces, tabs, etc.)
            floats = line.split()
            fixed = [str(float_to_q312(v)) for v in floats]
            
            # Write back as space-separated integers
            f_out.write(" ".join(fixed) + "\n")
            count += 1
            
    print(f"Successfully converted {count} lines to {output_path}")

# --- Execution ---
# This will now work for both your weights and your space-separated image file
convert_normalized_file('mnist_image_normalized.txt', 'mnist_image_q312_part2.txt')
convert_normalized_file('Float_Weights.txt', 'weights_q312_part2.txt')

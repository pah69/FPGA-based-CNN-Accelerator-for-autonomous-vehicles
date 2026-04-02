#!/usr/bin/env python3

def convert_weights_to_header(input_file, output_file):
    with open(input_file, 'r') as f:
        values = [int(line.strip()) for line in f.readlines()]
    
    with open(output_file, 'w') as f:
        f.write('#ifndef WEIGHTS_H\n')
        f.write('#define WEIGHTS_H\n\n')
        f.write('#include <stdint.h>\n\n')
        f.write('const int16_t weights[4996] = {\n    ')
        
        for i, val in enumerate(values):
            f.write(f'{val}')
            if i < len(values) - 1:
                f.write(', ')
            if (i + 1) % 16 == 0:
                f.write('\n    ')
        
        f.write('\n};\n\n')
        f.write('#endif\n')
    print(f"Converted {len(values)} weights to {output_file}")

def convert_images_to_header(input_file, output_file, num_images=100):
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    all_values = []
    for line in lines:
        # Split by spaces and convert each value to int
        values = line.strip().split()
        for val in values:
            if val:  # Skip empty strings
                all_values.append(int(val))
    
    # Reshape to 100 images of 784 pixels each
    images = [all_values[i*784:(i+1)*784] for i in range(num_images)]
    
    with open(output_file, 'w') as f:
        f.write('#ifndef IMAGES_H\n')
        f.write('#define IMAGES_H\n\n')
        f.write('#include <stdint.h>\n\n')
        f.write('const int16_t images[100][784] = {\n')
        
        for img_idx, image in enumerate(images):
            f.write('    { // Image %d\n        ' % img_idx)
            for i, val in enumerate(image):
                f.write(f'{val}')
                if i < len(image) - 1:
                    f.write(', ')
                if (i + 1) % 28 == 0 and i < len(image) - 1:
                    f.write('\n        ')
            f.write('}')
            if img_idx < len(images) - 1:
                f.write(',')
            f.write('\n')
        
        f.write('};\n\n')
        f.write('#endif\n')
    print(f"Converted {len(images)} images to {output_file}")

def convert_labels_to_header(input_file, output_file):
    with open(input_file, 'r') as f:
        values = [int(line.strip()) for line in f.readlines()]
    
    with open(output_file, 'w') as f:
        f.write('#ifndef LABELS_H\n')
        f.write('#define LABELS_H\n\n')
        f.write('#include <stdint.h>\n\n')
        f.write('const int16_t labels[100] = {\n    ')
        
        for i, val in enumerate(values):
            f.write(f'{val}')
            if i < len(values) - 1:
                f.write(', ')
            if (i + 1) % 20 == 0:
                f.write('\n    ')
        
        f.write('\n};\n\n')
        f.write('#endif\n')
    print(f"Converted {len(values)} labels to {output_file}")

# Convert your files
convert_weights_to_header('Int16_Weights.txt', 'weights.h')
convert_images_to_header('Int16_Images.txt', 'images.h')
convert_labels_to_header('mnist_labels.txt', 'labels.h')
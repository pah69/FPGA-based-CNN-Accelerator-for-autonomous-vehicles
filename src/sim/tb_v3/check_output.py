import numpy as np

# 1. Đọc Trọng số
weights = np.loadtxt("Float_Weights.txt").flatten()
W = weights[:9].reshape(3, 3)

# 2. Đọc Ảnh (Đọc liên tục giống hệt Testbench 100 ảnh)
image = np.loadtxt("mnist_image_normalized.txt").flatten()

# Lấy dữ liệu của 100 ảnh (78400 pixels)
num_images = 100
total_pixels = 784 * num_images
img_data = image[:total_pixels]

# Pad thêm số 0 ở tận cùng để tổng số pixel chia hết cho 3
pad_len = (3 - (len(img_data) % 3)) % 3
A_flat = np.pad(img_data, (0, pad_len), mode='constant', constant_values=0)

# Reshape thành ma trận A (Cứ 3 pixel xếp thành 1 hàng)
# Kích thước lúc này sẽ là 26134 hàng x 3 cột (Khớp 100% với Testbench)
A = A_flat.reshape(-1, 3) 

# 3. Lượng hóa (Quantization Q8.8)
# SỬ DỤNG np.trunc ĐỂ GIỐNG HỆT HÀM $rtoi CỦA VERILOG
# A_quantized = np.trunc(A * 256).astype(int)
# W_quantized = np.trunc(W * 256).astype(int)
A_quantized = np.round(A * 256).astype(int)
W_quantized = np.round(W * 256).astype(int)
# 4. Tính toán phần cứng (Số nguyên Q16.16)
Y_hardware_sim = np.dot(A_quantized, W_quantized)

# 5. Tính toán lý thuyết (Số thực Float)
Y_float = np.dot(A, W)

# In kết quả đối chiếu cho ẢNH 2 (Hàng 395 và 396)
print("========== KIỂM TRA ẢNH 2 (ROW 395) ==========")
print("Hardware Simulation (Q8.8):", Y_hardware_sim[395])
print("Lý thuyết Số Thực (Float) :", Y_float[395])

print("\n========== KIỂM TRA ẢNH 2 (ROW 396) ==========")
print("Hardware Simulation (Q8.8):", Y_hardware_sim[396])
print("Lý thuyết Số Thực (Float) :", Y_float[396])
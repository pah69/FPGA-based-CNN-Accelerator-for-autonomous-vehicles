void Max_Pool2D_0(float input_MaxPooling[5408], float output_MaxPooling[1352]){
	int PoolSize = 2;
	int stride = 2;
	int index = 0;
	for (int i = 0; i < 8; i++){
		index = 0;
		for (int z = 0; z < 13; z++){
			for (int y = 0; y < 13; y++){
				float max_c = -10;
				for (int h = 0; h < PoolSize; h++){
					for (int w = 0; w < PoolSize; w++){
						int Pool_index = 26 * 26 * i + 26 * h + 26 * stride * z + w + y * stride;
						float Pool_value = input_MaxPooling[Pool_index];
						if (Pool_value >= max_c) max_c = Pool_value;
					}
				}
				int outIndex = 13 * 13 * i + index;
				output_MaxPooling[outIndex] = max_c;
				index++;
			}
		}
	}
}
void Max_Pool2D_1(float input_MaxPooling[1210], float output_MaxPooling[250]){
	int PoolSize = 2;
	int stride = 2;
	int index = 0;
	for (int i = 0; i < 10; i++){
		index = 0;
		for (int z = 0; z < 5; z++){
			for (int y = 0; y < 5; y++){
				float max_c = -10;
				for (int h = 0; h < PoolSize; h++){
					for (int w = 0; w < PoolSize; w++){
						int Pool_index = 11 * 11 * i + 11 * h + 11 * stride * z + w + y * stride;
						float Pool_value = input_MaxPooling[Pool_index];
						if (Pool_value >= max_c) max_c = Pool_value;
					}
				}
				int outIndex = 5 * 5 * i + index;
				output_MaxPooling[outIndex] = max_c;
				index++;
			}
		}
	}
}
void flatten0(float input_Flatten[250],float output_Flatten[250]){
	int hs = 0;
	for (int i = 0; i < 5; i++){
		for (int j = 0; j < 5; j++){
			for (int k = 0; k < 10; k++){
				output_Flatten[hs] = input_Flatten[5 * i + 5 * 5 * k + j ];
				hs++;
			}
		}
	}
}

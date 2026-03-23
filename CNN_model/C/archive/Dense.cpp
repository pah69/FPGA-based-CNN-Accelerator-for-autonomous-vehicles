void Dense_0(float input_Dense[250],float output_Dense[16],float bias[16],float weight[4000]){
	float out_Dense[16];
	loop_for_a_Dense_0:
	for (int i = 0; i < 16; i++){
		float s=0;
		loop_for_b_Dense_0:
		for (int j = 0; j < 250; j++){
			s+=input_Dense[j]*weight[j*16+i];
		}
		out_Dense[i]=s+bias[i];
	}
	for (int i = 0; i < 16; i++){
		if (out_Dense[i] < 0) output_Dense[i] = 0; else output_Dense[i] = out_Dense[i];
	}
}
#include <cmath>
void Dense_1(float input_Dense[16],float &output_Dense0,float bias[10],float weight[160]){
	float out_Dense[10];
	loop_for_a_Dense_1:
	for (int i = 0; i < 10; i++){
		float s=0;
		loop_for_b_Dense_1:
		for (int j = 0; j < 16; j++){
			s+=input_Dense[j]*weight[j*10+i];
		}
		out_Dense[i]=s+bias[i];
	}
	int maxindex = 0;
	float max=out_Dense[0];
	loop_detect:
	for (int i=0; i<10; i++){
		if (out_Dense[i]> max) {
			max=out_Dense[i];
			maxindex=i;
		}
	}
	float sum_exp_x = 0.0;
	for(int i = 0; i <10;i++){
		sum_exp_x += exp(out_Dense[i]- out_Dense[maxindex]);
	}
	float max_value = out_Dense[maxindex];
	for(int i = 0; i <10;i++){
		out_Dense[i] = exp(out_Dense[i] - max_value) / sum_exp_x;
	}
	float maxindex_2 = 0;
	float max_2 = out_Dense[0];
	for(int i = 0; i <10;i++){
		if (out_Dense[i] > max_2) {
			max_2 = out_Dense[i];
			maxindex_2 = i;
		}
	}
	output_Dense0 = maxindex_2;
}

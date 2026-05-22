void Conv2D_0(float Input_Conv[784],float Output_Conv[5408], float bias[8], float kernel[72]){
	int stride = 1;
	loop_for_channel2D_0:
	for (int n = 0; n < 8; n++){
		loop_for_bp2D_0:
		for (int x = 0; x < 26; x++){
			loop_for_ap2D_0:
			for (int y = 0; y < 26; y++){
				float s = 0;
				loop_for_fc_0:
				for (int k = 0; k < 1; k++){
					loop_for_fb_0:
					for (int i = 0; i < 3; i++){
						loop_for_fa_0:
						for (int j = 0; j < 3; j++){
							s=s+(kernel[1*3*3*n+3*3*k+3*i+j])*(Input_Conv[28*28*k+28*(i+x*stride)+j+y*stride]);}
					}
				}
				if ((s+bias[n])<0) Output_Conv[26*26*n+26*x+y]=0; else Output_Conv[26*26*n+26*x+y]=s+bias[n];
			}
		}
	}
}
void Conv2D_1(float Input_Conv[1352],float Output_Conv[1210], float bias[10], float kernel[720]){
	int stride = 1;
	loop_for_channel2D_1:
	for (int n = 0; n < 10; n++){
		loop_for_bp2D_1:
		for (int x = 0; x < 11; x++){
			loop_for_ap2D_1:
			for (int y = 0; y < 11; y++){
				float s = 0;
				loop_for_fc_1:
				for (int k = 0; k < 8; k++){
					loop_for_fb_1:
					for (int i = 0; i < 3; i++){
						loop_for_fa_1:
						for (int j = 0; j < 3; j++){
							s=s+(kernel[8*3*3*n+3*3*k+3*i+j])*(Input_Conv[13*13*k+13*(i+x*stride)+j+y*stride]);}
					}
				}
				if ((s+bias[n])<0) Output_Conv[11*11*n+11*x+y]=0; else Output_Conv[11*11*n+11*x+y]=s+bias[n];
			}
		}
	}
}

#include "CNN.h"
#include "Conv.h"
#include "Pool.h"
#include "Dense.h"
#include <algorithm>
#include <string.h>

void CNN(float InModel[784],float &OutModel0,float Weights[4996]){
	float conv1[5408];
	float max_pooling2d[1352];
	float conv2[1210];
	float max_pooling2d_1[250];
	float flatten[250];
	float fc1[16];
	Conv2D_0(&InModel[0],conv1,&Weights[72],&Weights[0]);
	Max_Pool2D_0(conv1,max_pooling2d);
	Conv2D_1(max_pooling2d,conv2,&Weights[800],&Weights[80]);
	Max_Pool2D_1(conv2,max_pooling2d_1);
	flatten0(max_pooling2d_1,flatten);
	Dense_0(flatten,fc1,&Weights[4810],&Weights[810]);
	Dense_1(fc1,OutModel0,&Weights[4986],&Weights[4826]);
}

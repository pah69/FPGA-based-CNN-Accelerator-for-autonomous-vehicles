
#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <iostream>
#include "CNN.h"
#include "Conv.h"
#include "Pool.h"
#include "Dense.h"

#define NUMBER_OF_PICS 10000   // for test set
#define d 1                     // grayscale (1 channel)
#define IMG_SIZE (28*28)
#define NUMBER_OF_PARAMS 4996 
int main() {
    float OutModel0;
    float tmp;
    
    // --- Load weights ---
    float* Weights = (float*)malloc(NUMBER_OF_PARAMS * sizeof(float));
    FILE* Weight = fopen("Float_Weights.txt", "r");
    if (!Weight) { printf("Weight file not found!\n"); return -1; }
    for (int i = 0; i < 4996; i++) {
        fscanf(Weight, "%f", &tmp);
        Weights[i] = tmp;
    }
    fclose(Weight);

    // --- Load inputs (normalized) ---
    float* InModel = (float*)malloc(NUMBER_OF_PICS * IMG_SIZE * sizeof(float));
    FILE* Input = fopen("mnist_image_normalized.txt", "r");
    if (!Input) { printf("Image file not found!\n"); return -1; }

    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        for (int j = 0; j < IMG_SIZE; j++) {
            fscanf(Input, "%f", &InModel[i * IMG_SIZE + j]);
        }
    }
    fclose(Input);

    // --- Load labels (raw integers 0-9) ---
    float* Label = (float*)malloc(NUMBER_OF_PICS * sizeof(float));
    FILE* Output = fopen("mnist_labels.txt", "r");
    if (!Output) { printf("Label file not found!\n"); return -1; }
    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        fscanf(Output, "%f", &tmp);
        Label[i] = tmp;
    }
    fclose(Output);

    // --- Run inference ---
    float* OutArray = (float*)malloc(NUMBER_OF_PICS * sizeof(float));
    float Image[IMG_SIZE] = {};

    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        int startIndex = i * IMG_SIZE;
        for (int k = 0; k < IMG_SIZE; k++) {
            Image[k] = InModel[startIndex + k];
        }
        CNN(Image, OutModel0, Weights);   // forward pass
        OutArray[i] = OutModel0;
    }

    // --- Evaluate accuracy ---
    int countTrue = 0;
    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        int labelValue = (int)Label[i];
        int predictValue = (int)OutArray[i];
        if (labelValue == predictValue) {
            countTrue++;
        }
    }
    float accuracy = (float)countTrue / NUMBER_OF_PICS * 100.0f;
    std::cout << "Accuracy of Model: " << accuracy << "%\n";

    free(Weights);
    free(InModel);
    free(Label);
    free(OutArray);

    return 0;
}



// #define _CRT_SECURE_NO_WARNINGS
// #include <conio.h>
// #include <stdio.h>
// #include <stdlib.h>
// #include <math.h>
// #include <string>
// #include <fstream>
// #include <iostream>
// #include "CNN.h"
// #include "Conv.h"
// #include "Pool.h"
// #include "Dense.h"
// #define NUMBER_OF_PICS ...
// #define d ...
// int main(){
// 	float OutModel0;
// 	float* Weights = (float*)malloc(4996 * sizeof(float));
// 	float tmp;

// 	FILE* Weight = fopen("Float_Weights.txt", "r");
// 	for (int i = 0; i < 4996; i++){
// 		fscanf(Weight, "%f", &tmp);
// 		*(Weights + i)=tmp;
// 	}
// 	fclose(Weight);

// 	//read Input
// 	float* InModel = (float*)malloc((NUMBER_OF_PICS * d * 28 * 28) * sizeof(float));
// 	FILE* Input = fopen("X.txt", "r");
// 	for (int i = 0; i < NUMBER_OF_PICS * d * 28 * 28; i++){
// 		fscanf(Input, "%f", &tmp);
// 		*(InModel + i)=tmp;
// 	}
// 	fclose(Input);

// 	//Read Label
// 	float*Label = (float*)malloc((NUMBER_OF_PICS) * sizeof(float));
// 	FILE* Output = fopen("Y.txt", "r");
// 	for (int i = 0; i < NUMBER_OF_PICS ; i++)
// 	{
// 		fscanf(Output, "%f", &tmp);
// 		*(Label + i) = tmp;
// 	}
// 	fclose(Output);
	
// 	float*OutArray = (float*)malloc((NUMBER_OF_PICS) * sizeof(float));
// 	float Image[d * 28 * 28] = {};
// 	for (int i = 0; i < NUMBER_OF_PICS ; i++)
// 	{
// 		int startIndex = i * d * 28 * 28;
// 		for (int k = 0; k < d * 28 * 28; k++)
// 		{
// 			Image[k] = *(InModel + startIndex + k);
// 		}
// 		CNN(Image, OutModel0, Weights);
// 		*(OutArray + i) = OutModel0;
// 	}

// 	float countTrue = 0;
// 	for (int i = 0; i < NUMBER_OF_PICS; i++)
// 	{
// 		int labelValue = *(Label + i);
// 		int PredictValue = *(OutArray + i);
// 		if (labelValue == PredictValue)
// 		{
// 			countTrue = countTrue + 1;
// 		}
// 	}

// 	float accuracy = (float)((countTrue / (NUMBER_OF_PICS)) * 100);

// 	std::cout << "accuracy of Model: " << accuracy << "%\n";
// 	//std::cout << "Result: " <<  OutModel <<  "\n";
// 	return 0;
// }

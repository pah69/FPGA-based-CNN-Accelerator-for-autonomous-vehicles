
// ============================================
// CNN_tb_Fixed.cpp - Test bench
// ============================================
#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <iostream>


#include "fixed_point.h"
#include "cnn_fixed.h"
#include "conv_fixed.h"
#include "dense_fixed.h"
#include "pool_fixed.h"


#define NUMBER_OF_PICS 10000
#define IMG_SIZE 784
#define NUMBER_OF_PARAMS 4996

bool loadInt16Array(const char* filename, int16_t* array, int size) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        printf("Error: Cannot open %s\n", filename);
        return false;
    }
    
    for (int i = 0; i < size; i++) {
        int temp;
        fscanf(file, "%d", &temp);
        array[i] = (int32_t)temp;
    }
    fclose(file);
    return true;
}

int main() {
    // Allocate memory for int16
    int16_t* weights = (int16_t*)malloc(NUMBER_OF_PARAMS * sizeof(int16_t));
    int16_t* images = (int16_t*)malloc(NUMBER_OF_PICS * IMG_SIZE * sizeof(int16_t));
    float* labels = (float*)malloc(NUMBER_OF_PICS * sizeof(float));
    float* predictions = (float*)malloc(NUMBER_OF_PICS * sizeof(float));
    
    // Load quantized weights and images
    printf("Loading quantized data...\n");
    if (!loadInt16Array("weights_q312.txt", weights, NUMBER_OF_PARAMS)) {
        return -1;
    }
    if (!loadInt16Array("mnist_image_q312.txt", images, NUMBER_OF_PICS * IMG_SIZE)) {
        return -1;
    }
    
    // Load labels (still float)
    FILE* labelFile = fopen("mnist_labels.txt", "r");
    if (!labelFile) {
        printf("Error: Cannot open labels\n");
        return -1;
    }
    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        fscanf(labelFile, "%f", &labels[i]);
    }
    fclose(labelFile);
    
    printf("Running fixed-point inference...\n");
    
    // Run inference
    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        int16_t predictedClass;
        CNN_Fixed(&images[i * IMG_SIZE], predictedClass, weights);
        predictions[i] = predictedClass;
    }
    
    //Calculate accuracy
    int correctPredictions = 0;
    int wrongPredictions = 0;

    for (int i = 0; i < NUMBER_OF_PICS; i++) {
        int label = (int)labels[i];
        int predicted = (int)predictions[i];
        bool correct = (label == predicted);
        
        if (correct) {
            correctPredictions++;
        } else {
            wrongPredictions++;
            // Print all wrong predictions
            // printf("%6d | %5d | %9d | WRONG\n", i, label, predicted);
        }
        
        // print first 20 images (correct or wrong)
        // if (i < 10000) {
        //     printf("%6d | %5d | %9d | %s\n", i,label,predicted, correct ? "OK" : "WRONG");
        // }
    }
    
    printf("\n=== Summary ===\n");
    printf("Total images: %d\n", NUMBER_OF_PICS);
    printf("Correct: %d\n", correctPredictions);
    printf("Wrong: %d\n", wrongPredictions);

    float accuracy = (float)correctPredictions / NUMBER_OF_PICS * 100.0f;
    std::cout << "Fixed-Point Model Accuracy: " << accuracy << "%\n";
    
    // Cleanup
    free(weights);
    free(images);
    free(labels);
    free(predictions);
    
    return 0;
}
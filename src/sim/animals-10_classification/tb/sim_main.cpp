#include "Vtest_animals10_conv1_case0.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtest_animals10_conv1_case0 top;

    while (!Verilated::gotFinish()) {
        top.eval();
    }

    top.final();
    return 0;
}


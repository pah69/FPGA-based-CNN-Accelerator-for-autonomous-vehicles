#!/bin/bash

# 1. Define variables
TOP_MODULE="simple_test_tb"         # Change this to your testbench name
SNAPSHOT="sim_snapshot"

# 2. Cleanup previous runs
#rm -rf *.log *.jou *.pb

# 3. Parse/Compile Verilog/SystemVerilog files
echo "--- COMPILING ---"
xvlog -sv \
    "simple_test.sv" \
   *.sv
   # "sim/testbench.v" \
   # --include "./include_dir"

# 4. Elaborate the design
# -debug typical: allows waveform viewing
# -L: allows linking to specific libraries (e.g., unisims_ver)
echo "--- ELABORATING ---"
xelab -debug typical \
      $TOP_MODULE \
      -s $SNAPSHOT

# 5. Run simulation
# -tclbatch: runs commands (like 'run all') from a file or inline
echo "--- SIMULATING ---"
xsim $SNAPSHOT -R

#clean :
rm -rf xsim.dir/ *.log *.jou *.pb

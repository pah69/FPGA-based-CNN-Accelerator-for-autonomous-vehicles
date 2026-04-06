# Variables
TOP_MODULE = tb_systolic_array_4x4
SNAPSHOT   = my_sim_snapshot

# Directories
RTL_DIR = /home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/rtl/accelerator/
SIM_DIR = /home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sim/

# Source Files
RTL_FILES = $(wildcard $(RTL_DIR)/*.sv) $(wildcard $(RTL_DIR)/*/*.sv)
# TB_FILE   = $(SIM_DIR)/tb.sv
TB_FILE = $(SIM_DIR)/tb_systolic_array_4x4.sv
# Targets
all: simulate

# Step 1: Parse (Compile)
compile: 
	xvlog -sv $(RTL_FILES) $(TB_FILE)

# Step 2: Elaborate
elaborate: compile
	xelab -debug typical -top $(TOP_MODULE) -snapshot $(SNAPSHOT)

# Step 3: Simulate
simulate: elaborate
	xsim $(SNAPSHOT) -R

# Run with GUI
gui: elaborate
	xsim $(SNAPSHOT) -gui 

# Cleanup temporary files
clean:
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil *.vcd

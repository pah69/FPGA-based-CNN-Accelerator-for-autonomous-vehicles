# Variables
TOP_MODULE = simple_test_tb
SNAPSHOT   = my_sim_snapshot
SRC_FILES  = *.sv

# Targets
all: simulate

# Step 1: Parse (Compile)
compile: $(SRC_FILES)
	xvlog -sv $(SRC_FILES)

# Step 2: Elaborate
elaborate: compile
	xelab -debug typical -top $(TOP_MODULE) -snapshot $(SNAPSHOT)

# Step 3: Simulate (Batch mode)
simulate: elaborate
	xsim $(SNAPSHOT) -R

# Run with GUI
gui: elaborate
	xsim $(SNAPSHOT) -gui 

# Cleanup temporary files
clean:
	rm -rf *.log *.jou *.pb *.wdb


# Directories
RTL_DIR ?= ../../rtl/v2
SIM_DIR ?= .

# Available test aliases
TEST ?= sa_2x2

TOP_sa_2x2               = test_sa_2x2_computation
TOP_staggered_activation = test_staggered_activation
TOP_weight_double_buffer = test_weight_double_buffer
TOP_weight_fifo_fetcher  = test_weight_fifo_fetcher_mxu
TOP_activation_skew      = test_activation_skew_ws_sa
TOP_vpu_post_process     = test_vpu_post_process

TOP_MODULE ?= $(TOP_$(TEST))
SNAPSHOT   ?= $(TOP_MODULE)_snapshot
TB_FILE    ?= $(SIM_DIR)/$(TOP_MODULE).sv

# Source files
RTL_FILES = $(wildcard $(RTL_DIR)/*.sv) $(wildcard $(RTL_DIR)/*/*.sv)

.PHONY: all help list run compile elaborate simulate gui clean \
	test_sa_2x2 test_staggered_activation test_weight_double_buffer \
	test_weight_fifo_fetcher test_activation_skew test_vpu_post_process

all: run

help: list
	@echo ""
	@echo "Usage:"
	@echo "  make test_activation_skew"
	@echo "  make test_weight_fifo_fetcher"
	@echo "  make run TEST=sa_2x2"
	@echo "  make gui TEST=activation_skew"

list:
	@echo "Available tests:"
	@echo "  sa_2x2"
	@echo "  staggered_activation"
	@echo "  weight_double_buffer"
	@echo "  weight_fifo_fetcher"
	@echo "  activation_skew"
	@echo "  vpu_post_process"

run: simulate

test_sa_2x2:
	$(MAKE) run TEST=sa_2x2

test_staggered_activation:
	$(MAKE) run TEST=staggered_activation

test_weight_double_buffer:
	$(MAKE) run TEST=weight_double_buffer

test_weight_fifo_fetcher:
	$(MAKE) run TEST=weight_fifo_fetcher

test_activation_skew:
	$(MAKE) run TEST=activation_skew

test_vpu_post_process:
	$(MAKE) run TEST=vpu_post_process

# Step 1: Parse / compile
compile:
	@test -n "$(TOP_MODULE)" || (echo "Unknown TEST='$(TEST)'. Run 'make list'." && exit 1)
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
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil *.str

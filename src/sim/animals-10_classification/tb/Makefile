# Animals-10 focused RTL bring-up benches.

TEST ?= conv1_case0

TOP_conv1_case0 = test_animals10_conv1_case0
TOP_conv1_dut_case0 = test_animals10_conv1_dut_case0

TOP_MODULE ?= $(TOP_$(TEST))
SNAPSHOT   ?= $(TOP_MODULE)_snapshot
TB_FILE    ?= $(TOP_MODULE).sv
RTL_DIR    ?= ../../../rtl/animals-10_classification/v1
SA_CORE_FILES = $(RTL_DIR)/animals10_pe.sv \
                $(RTL_DIR)/animals10_systolic_array.sv
RTL_FILES_conv1_dut_case0 = $(RTL_DIR)/animals10_conv1_direct.sv
RTL_FILES ?= $(RTL_FILES_$(TEST))

CASE_INDEX ?= 0
XSIM_ARGS  ?=

.PHONY: all help list run compile compile_sa_core elaborate simulate test_conv1_case0 \
	verilate_conv1_case0 gui clean

all: run

help: list
	@echo ""
	@echo "Usage:"
	@echo "  make test_conv1_case0"
	@echo "  make test_conv1_dut_case0"
	@echo "  make run TEST=conv1_case0"
	@echo "  make run TEST=conv1_case0 XSIM_ARGS=\"--testplusarg CASE_INDEX=0\""
	@echo "  make compile_sa_core"
	@echo "  make verilate_conv1_case0"
	@echo "  make compile TEST=conv1_case0"
	@echo "  make gui TEST=conv1_case0"

list:
	@echo "Available tests:"
	@echo "  conv1_case0"
	@echo "  conv1_dut_case0"

run: simulate

test_conv1_case0:
	$(MAKE) run TEST=conv1_case0

test_conv1_dut_case0:
	$(MAKE) run TEST=conv1_dut_case0

verilate_conv1_case0:
	verilator -sv --cc --exe --build --top-module test_animals10_conv1_case0 \
		test_animals10_conv1_case0.sv sim_main.cpp
	./obj_dir/Vtest_animals10_conv1_case0

compile:
	@test -n "$(TOP_MODULE)" || (echo "Unknown TEST='$(TEST)'. Run 'make list'." && exit 1)
	xvlog -sv $(RTL_FILES) $(TB_FILE)

compile_sa_core:
	xvlog -sv $(SA_CORE_FILES)

elaborate: compile
	xelab -debug typical -top $(TOP_MODULE) -snapshot $(SNAPSHOT)

simulate: elaborate
	xsim $(SNAPSHOT) -R $(XSIM_ARGS)

gui: elaborate
	xsim $(SNAPSHOT) -gui $(XSIM_ARGS)

clean:
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil *.str obj_dir

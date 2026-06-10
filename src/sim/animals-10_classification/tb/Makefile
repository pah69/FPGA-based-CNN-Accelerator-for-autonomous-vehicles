# Animals-10 focused RTL bring-up benches.

TEST ?= conv1_case0

TOP_conv1_case0 = test_animals10_conv1_case0
TOP_conv1_dut_case0 = test_animals10_conv1_dut_case0
TOP_conv1_systolic_case0 = test_animals10_conv1_systolic_case0
TOP_conv2_systolic_case0 = test_animals10_conv2_systolic_case0
TOP_conv1_conv2_pool1_case0 = test_animals10_conv1_conv2_pool1_case0
TOP_conv3_systolic_case0 = test_animals10_conv3_systolic_case0
TOP_conv4_systolic_case0 = test_animals10_conv4_systolic_case0
TOP_conv3_conv4_pool2_case0 = test_animals10_conv3_conv4_pool2_case0
TOP_conv5_systolic_case0 = test_animals10_conv5_systolic_case0
TOP_conv6_systolic_case0 = test_animals10_conv6_systolic_case0
TOP_conv5_conv6_pool3_case0 = test_animals10_conv5_conv6_pool3_case0
TOP_gap_case0 = test_animals10_gap_case0
TOP_fc1_case0 = test_animals10_fc1_case0
TOP_fc2_case0 = test_animals10_fc2_case0
TOP_gap_fc1_fc2_case0 = test_animals10_gap_fc1_fc2_case0
TOP_conv5_conv6_pool3_gap_fc1_fc2_case0 = test_animals10_conv5_conv6_pool3_gap_fc1_fc2_case0
TOP_full_network_case0 = test_animals10_full_network_case0
TOP_full_network_10cases = test_animals10_full_network_10cases

TOP_MODULE ?= $(TOP_$(TEST))
SNAPSHOT   ?= $(TOP_MODULE)_snapshot
TB_FILE    ?= $(TOP_MODULE).sv
RTL_DIR    ?= ../../../rtl/animals-10_classification/v1
SA_CORE_FILES = $(RTL_DIR)/animals10_pe.sv \
                $(RTL_DIR)/animals10_systolic_array.sv \
                $(RTL_DIR)/animals10_systolic_array_4x4.sv
RTL_FILES_conv1_dut_case0 = $(RTL_DIR)/animals10_conv1_direct.sv
RTL_FILES_conv1_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv1_systolic_4x4.sv
RTL_FILES_conv2_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                  $(RTL_DIR)/animals10_conv2_systolic_4x4.sv
RTL_FILES_conv1_conv2_pool1_case0 = $(RTL_DIR)/animals10_pe.sv \
                                    $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                    $(RTL_DIR)/animals10_conv1_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv2_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_maxpool2x2_i8.sv \
                                    $(RTL_DIR)/animals10_conv1_conv2_pool1_systolic_4x4.sv
RTL_FILES_conv3_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                  $(RTL_DIR)/animals10_conv3_systolic_4x4.sv
RTL_FILES_conv4_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                  $(RTL_DIR)/animals10_conv4_systolic_4x4.sv
RTL_FILES_conv3_conv4_pool2_case0 = $(RTL_DIR)/animals10_pe.sv \
                                    $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                    $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv3_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv4_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_maxpool2x2_i8.sv \
                                    $(RTL_DIR)/animals10_conv3_conv4_pool2_systolic_4x4.sv
RTL_FILES_conv5_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                  $(RTL_DIR)/animals10_conv5_systolic_4x4.sv
RTL_FILES_conv6_systolic_case0 = $(RTL_DIR)/animals10_pe.sv \
                                  $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                  $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                  $(RTL_DIR)/animals10_conv6_systolic_4x4.sv
RTL_FILES_conv5_conv6_pool3_case0 = $(RTL_DIR)/animals10_pe.sv \
                                    $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                    $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv5_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_conv6_systolic_4x4.sv \
                                    $(RTL_DIR)/animals10_maxpool2x2_i8.sv \
                                    $(RTL_DIR)/animals10_conv5_conv6_pool3_systolic_4x4.sv
RTL_FILES_gap_case0 = $(RTL_DIR)/animals10_gap_i8.sv
RTL_FILES_fc1_case0 = $(RTL_DIR)/animals10_dense_i8.sv \
                       $(RTL_DIR)/animals10_fc1_i8.sv
RTL_FILES_fc2_case0 = $(RTL_DIR)/animals10_dense_i8.sv \
                       $(RTL_DIR)/animals10_fc2_i8.sv
RTL_FILES_gap_fc1_fc2_case0 = $(RTL_DIR)/animals10_gap_i8.sv \
                               $(RTL_DIR)/animals10_dense_i8.sv \
                               $(RTL_DIR)/animals10_fc1_i8.sv \
                               $(RTL_DIR)/animals10_fc2_i8.sv \
                               $(RTL_DIR)/animals10_gap_fc1_fc2_i8.sv
RTL_FILES_conv5_conv6_pool3_gap_fc1_fc2_case0 = $(RTL_DIR)/animals10_pe.sv \
                                                $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                                                $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                                                $(RTL_DIR)/animals10_conv5_systolic_4x4.sv \
                                                $(RTL_DIR)/animals10_conv6_systolic_4x4.sv \
                                                $(RTL_DIR)/animals10_maxpool2x2_i8.sv \
                                                $(RTL_DIR)/animals10_conv5_conv6_pool3_systolic_4x4.sv \
                                                $(RTL_DIR)/animals10_gap_i8.sv \
                                                $(RTL_DIR)/animals10_dense_i8.sv \
                                                $(RTL_DIR)/animals10_fc1_i8.sv \
                                                $(RTL_DIR)/animals10_fc2_i8.sv \
                                                $(RTL_DIR)/animals10_gap_fc1_fc2_i8.sv \
                                                $(RTL_DIR)/animals10_conv5_conv6_pool3_gap_fc1_fc2_i8.sv
RTL_FILES_full_network_case0 = $(RTL_DIR)/animals10_pe.sv \
                               $(RTL_DIR)/animals10_systolic_array_4x4.sv \
                               $(RTL_DIR)/animals10_conv1_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv2_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv3_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv4_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv5_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv6_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_maxpool2x2_i8.sv \
                               $(RTL_DIR)/animals10_conv1_conv2_pool1_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv3_conv4_pool2_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_conv5_conv6_pool3_systolic_4x4.sv \
                               $(RTL_DIR)/animals10_gap_i8.sv \
                               $(RTL_DIR)/animals10_dense_i8.sv \
                               $(RTL_DIR)/animals10_fc1_i8.sv \
                               $(RTL_DIR)/animals10_fc2_i8.sv \
                               $(RTL_DIR)/animals10_gap_fc1_fc2_i8.sv \
                               $(RTL_DIR)/animals10_conv5_conv6_pool3_gap_fc1_fc2_i8.sv \
                               $(RTL_DIR)/animals10_full_network_i8.sv
RTL_FILES_full_network_10cases = $(RTL_FILES_full_network_case0)
RTL_FILES ?= $(RTL_FILES_$(TEST))

CASE_INDEX ?= 0
XSIM_ARGS  ?=

.PHONY: all help list run compile compile_sa_core elaborate simulate test_conv1_case0 \
	test_conv1_systolic_case0 \
	test_conv2_systolic_case0 \
	test_conv1_conv2_pool1_case0 \
	test_conv3_systolic_case0 \
	test_conv4_systolic_case0 \
	test_conv3_conv4_pool2_case0 \
	test_conv5_systolic_case0 \
	test_conv6_systolic_case0 \
	test_conv5_conv6_pool3_case0 \
	test_gap_case0 \
	test_fc1_case0 \
	test_fc2_case0 \
	test_gap_fc1_fc2_case0 \
	test_conv5_conv6_pool3_gap_fc1_fc2_case0 \
	test_full_network_case0 \
	test_full_network_10cases \
	verilate_conv1_case0 gui clean

all: run

help: list
	@echo ""
	@echo "Usage:"
	@echo "  make test_conv1_case0"
	@echo "  make test_conv1_dut_case0"
	@echo "  make test_conv1_systolic_case0"
	@echo "  make test_conv2_systolic_case0"
	@echo "  make test_conv1_conv2_pool1_case0"
	@echo "  make test_conv3_systolic_case0"
	@echo "  make test_conv4_systolic_case0"
	@echo "  make test_conv3_conv4_pool2_case0"
	@echo "  make test_conv5_systolic_case0"
	@echo "  make test_conv6_systolic_case0"
	@echo "  make test_conv5_conv6_pool3_case0"
	@echo "  make test_gap_case0"
	@echo "  make test_fc1_case0"
	@echo "  make test_fc2_case0"
	@echo "  make test_gap_fc1_fc2_case0"
	@echo "  make test_conv5_conv6_pool3_gap_fc1_fc2_case0"
	@echo "  make test_full_network_case0"
	@echo "  make test_full_network_10cases"
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
	@echo "  conv1_systolic_case0"
	@echo "  conv2_systolic_case0"
	@echo "  conv1_conv2_pool1_case0"
	@echo "  conv3_systolic_case0"
	@echo "  conv4_systolic_case0"
	@echo "  conv3_conv4_pool2_case0"
	@echo "  conv5_systolic_case0"
	@echo "  conv6_systolic_case0"
	@echo "  conv5_conv6_pool3_case0"
	@echo "  gap_case0"
	@echo "  fc1_case0"
	@echo "  fc2_case0"
	@echo "  gap_fc1_fc2_case0"
	@echo "  conv5_conv6_pool3_gap_fc1_fc2_case0"
	@echo "  full_network_case0"
	@echo "  full_network_10cases"

run: simulate

test_conv1_case0:
	$(MAKE) run TEST=conv1_case0

test_conv1_dut_case0:
	$(MAKE) run TEST=conv1_dut_case0

test_conv1_systolic_case0:
	$(MAKE) run TEST=conv1_systolic_case0

test_conv2_systolic_case0:
	$(MAKE) run TEST=conv2_systolic_case0

test_conv1_conv2_pool1_case0:
	$(MAKE) run TEST=conv1_conv2_pool1_case0

test_conv3_systolic_case0:
	$(MAKE) run TEST=conv3_systolic_case0

test_conv4_systolic_case0:
	$(MAKE) run TEST=conv4_systolic_case0

test_conv3_conv4_pool2_case0:
	$(MAKE) run TEST=conv3_conv4_pool2_case0

test_conv5_systolic_case0:
	$(MAKE) run TEST=conv5_systolic_case0

test_conv6_systolic_case0:
	$(MAKE) run TEST=conv6_systolic_case0

test_conv5_conv6_pool3_case0:
	$(MAKE) run TEST=conv5_conv6_pool3_case0

test_gap_case0:
	$(MAKE) run TEST=gap_case0

test_fc1_case0:
	$(MAKE) run TEST=fc1_case0

test_fc2_case0:
	$(MAKE) run TEST=fc2_case0

test_gap_fc1_fc2_case0:
	$(MAKE) run TEST=gap_fc1_fc2_case0

test_conv5_conv6_pool3_gap_fc1_fc2_case0:
	$(MAKE) run TEST=conv5_conv6_pool3_gap_fc1_fc2_case0

test_full_network_case0:
	$(MAKE) run TEST=full_network_case0

test_full_network_10cases:
	$(MAKE) run TEST=full_network_10cases

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

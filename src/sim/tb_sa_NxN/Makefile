# Directories
RTL_VERSION ?= v2
RTL_DIR ?= ../../rtl/$(RTL_VERSION)
SIM_DIR ?= .

# Available test aliases
TEST ?= sa_2x2

TOP_sa_2x2               = test_sa_2x2_computation
TOP_staggered_activation = test_staggered_activation
TOP_weight_double_buffer = test_weight_double_buffer
TOP_weight_fifo_fetcher  = test_weight_fifo_fetcher_mxu
TOP_activation_skew      = test_activation_skew_ws_sa
TOP_vpu_post_process     = test_vpu_post_process
TOP_accumulator_array    = test_accumulator_array_ws_sa_vpu
TOP_tpu_datapath         = test_tpu_datapath_v2
TOP_controller_buffer    = test_controller_unified_buffer_v2
TOP_controller_rom_tile  = test_controller_rom_tile
TOP_controller_rom_kloop = test_controller_rom_kloop
TOP_controller_rom_layer = test_controller_rom_layer
TOP_controller_conv1_pixel = test_controller_conv1_pixel
TOP_controller_conv1_layer = test_controller_conv1_layer
TOP_controller_conv2_layer = test_controller_conv2_layer
TOP_maxpool2d_pool1     = test_maxpool2d_pool1
TOP_maxpool2d_pool2     = test_maxpool2d_pool2
TOP_tpu_top_e2e         = test_tpu_top_end_to_end
TOP_tpu_axi_lite        = test_tpu_top_axi_lite_compile
TOP_rom_load             = test_rom_load
TOP_conv_fc_addr         = test_conv_fc_address_generator

TOP_MODULE ?= $(TOP_$(TEST))
SNAPSHOT   ?= $(TOP_MODULE)_snapshot
TB_FILE    ?= $(SIM_DIR)/$(TOP_MODULE).sv
XSIM_ARGS  ?=

E2E_CASES      ?= 4
E2E_CASE_DIR   ?= ../../../CNN_model/python/mnist_classification/18_05/e2e_cases
E2E_INPUT_HEX  ?= $(E2E_CASE_DIR)/tpu_top_e2e_inputs_i8.hex
E2E_LOGITS_HEX ?= $(E2E_CASE_DIR)/tpu_top_e2e_logits_i8.hex
E2E_GENERATOR_ARGS ?= --include-synthetic
MNIST_TXT_IMAGES ?= /home/pah/Pictures/mnist_data_txt/mnist_images.txt
MNIST_TXT_LABELS ?= /home/pah/Pictures/mnist_data_txt/mnist_labels.txt
MNIST_TXT_COUNT  ?= 10
MNIST_TXT_START  ?= 0

# Source files
RTL_FILES = $(wildcard $(RTL_DIR)/*.sv) $(wildcard $(RTL_DIR)/*/*.sv)

.PHONY: all help list run compile elaborate simulate gui clean \
	test_sa_2x2 test_staggered_activation test_weight_double_buffer \
	test_weight_fifo_fetcher test_activation_skew test_vpu_post_process \
	test_accumulator_array test_tpu_datapath test_controller_buffer \
	test_controller_rom_tile test_controller_rom_kloop test_controller_rom_layer \
	test_controller_conv1_pixel test_controller_conv1_layer test_controller_conv2_layer \
	test_maxpool2d_pool1 test_maxpool2d_pool2 test_tpu_top_e2e test_tpu_axi_lite \
	test_tpu_top_e2e_file generate_tpu_top_e2e_cases generate_tpu_top_e2e_mnist_txt \
	test_tpu_top_e2e_mnist_txt test_rom_load test_conv_fc_addr

all: run

help: list
	@echo ""
	@echo "Usage:"
	@echo "  make test_activation_skew"
	@echo "  make test_weight_fifo_fetcher"
	@echo "  make test_accumulator_array"
	@echo "  make test_tpu_datapath"
	@echo "  make test_controller_buffer"
	@echo "  make test_controller_rom_tile"
	@echo "  make test_controller_rom_kloop"
	@echo "  make test_controller_rom_layer"
	@echo "  make test_controller_conv1_pixel"
	@echo "  make test_controller_conv1_layer"
	@echo "  make test_controller_conv2_layer"
	@echo "  make test_maxpool2d_pool1"
	@echo "  make test_maxpool2d_pool2"
	@echo "  make test_tpu_top_e2e"
	@echo "  make generate_tpu_top_e2e_cases"
	@echo "  make test_tpu_top_e2e_file E2E_CASES=4"
	@echo "  make generate_tpu_top_e2e_cases E2E_GENERATOR_ARGS=\"--images-txt /path/mnist_images.txt --labels-txt /path/mnist_labels.txt --txt-count 20\""
	@echo "  make test_tpu_top_e2e_mnist_txt MNIST_TXT_COUNT=10"
	@echo "  make test_tpu_axi_lite"
	@echo "  make test_rom_load"
	@echo "  make test_conv_fc_addr"
	@echo "  make run TEST=sa_2x2"
	@echo "  make compile TEST=tpu_axi_lite RTL_VERSION=v3"
	@echo "  make run TEST=tpu_top_e2e RTL_VERSION=v3"
	@echo "  make gui TEST=activation_skew"

list:
	@echo "Available tests:"
	@echo "  sa_2x2"
	@echo "  staggered_activation"
	@echo "  weight_double_buffer"
	@echo "  weight_fifo_fetcher"
	@echo "  activation_skew"
	@echo "  vpu_post_process"
	@echo "  accumulator_array"
	@echo "  tpu_datapath"
	@echo "  controller_buffer"
	@echo "  controller_rom_tile"
	@echo "  controller_rom_kloop"
	@echo "  controller_rom_layer"
	@echo "  controller_conv1_pixel"
	@echo "  controller_conv1_layer"
	@echo "  controller_conv2_layer"
	@echo "  maxpool2d_pool1"
	@echo "  maxpool2d_pool2"
	@echo "  tpu_top_e2e"
	@echo "  tpu_axi_lite"
	@echo "  rom_load"
	@echo "  conv_fc_addr"

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

test_accumulator_array:
	$(MAKE) run TEST=accumulator_array

test_tpu_datapath:
	$(MAKE) run TEST=tpu_datapath

test_controller_buffer:
	$(MAKE) run TEST=controller_buffer

test_controller_rom_tile:
	$(MAKE) run TEST=controller_rom_tile

test_controller_rom_kloop:
	$(MAKE) run TEST=controller_rom_kloop

test_controller_rom_layer:
	$(MAKE) run TEST=controller_rom_layer

test_controller_conv1_pixel:
	$(MAKE) run TEST=controller_conv1_pixel

test_controller_conv1_layer:
	$(MAKE) run TEST=controller_conv1_layer

test_controller_conv2_layer:
	$(MAKE) run TEST=controller_conv2_layer

test_maxpool2d_pool1:
	$(MAKE) run TEST=maxpool2d_pool1

test_maxpool2d_pool2:
	$(MAKE) run TEST=maxpool2d_pool2

test_tpu_top_e2e:
	$(MAKE) run TEST=tpu_top_e2e

test_tpu_top_e2e_file:
	$(MAKE) run TEST=tpu_top_e2e XSIM_ARGS="--testplusarg E2E_FILE_CASES --testplusarg E2E_CASES=$(E2E_CASES) --testplusarg E2E_INPUT_HEX=$(E2E_INPUT_HEX) --testplusarg E2E_LOGITS_HEX=$(E2E_LOGITS_HEX)"

test_tpu_top_e2e_mnist_txt: generate_tpu_top_e2e_mnist_txt
	$(MAKE) run TEST=tpu_top_e2e XSIM_ARGS="--testplusarg E2E_FILE_CASES --testplusarg E2E_CASES=$(MNIST_TXT_COUNT) --testplusarg E2E_INPUT_HEX=$(E2E_INPUT_HEX) --testplusarg E2E_LOGITS_HEX=$(E2E_LOGITS_HEX)"

test_tpu_axi_lite:
	$(MAKE) run TEST=tpu_axi_lite

test_rom_load:
	$(MAKE) run TEST=rom_load

test_conv_fc_addr:
	$(MAKE) run TEST=conv_fc_addr

# Step 1: Parse / compile
compile:
	@test -n "$(TOP_MODULE)" || (echo "Unknown TEST='$(TEST)'. Run 'make list'." && exit 1)
	xvlog -sv $(RTL_FILES) $(TB_FILE)

# Step 2: Elaborate
elaborate: compile
	xelab -debug typical -top $(TOP_MODULE) -snapshot $(SNAPSHOT)

# Step 3: Simulate
simulate: elaborate
	xsim $(SNAPSHOT) -R $(XSIM_ARGS)

# Run with GUI
gui: elaborate
	xsim $(SNAPSHOT) -gui $(XSIM_ARGS)

generate_tpu_top_e2e_cases:
	cd ../../../CNN_model/python/mnist_classification/18_05 && python3 make_tpu_top_e2e_cases.py $(E2E_GENERATOR_ARGS)

generate_tpu_top_e2e_mnist_txt:
	cd ../../../CNN_model/python/mnist_classification/18_05 && python3 make_tpu_top_e2e_cases.py --images-txt $(MNIST_TXT_IMAGES) --labels-txt $(MNIST_TXT_LABELS) --txt-count $(MNIST_TXT_COUNT) --txt-start $(MNIST_TXT_START)

# Cleanup temporary files
clean:
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil *.str

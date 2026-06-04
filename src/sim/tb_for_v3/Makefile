# V3 simulation makefile.

RTL_VERSION ?= v3
RTL_DIR ?= ../../rtl/$(RTL_VERSION)
SIM_DIR ?= .

TEST ?= activation_window_gather

TOP_activation_window_gather = test_activation_window_gather_v3
TOP_weight_tile_buffer       = test_weight_tile_buffer_v3
TOP_mxu_v3_2x2               = test_mxu_v3_2x2
TOP_tpu_datapath_v3          = test_tpu_datapath_v3
TOP_addrgen_tpu_datapath_v3  = test_addrgen_tpu_datapath_v3
TOP_controller_v3_tile       = test_controller_v3_tile
TOP_controller_v3_spatial_block = test_controller_v3_spatial_block
TOP_controller_v3_rom_spatial_block_conv1 = test_controller_v3_rom_spatial_block_conv1
TOP_controller_v3_rom_tile   = test_controller_v3_rom_tile
TOP_controller_v3_rom_layer_fc2 = test_controller_v3_rom_layer_fc2
TOP_controller_v3_conv1_pixel = test_controller_v3_conv1_pixel
TOP_controller_v3_conv1_layer = test_controller_v3_conv1_layer
TOP_controller_v3_conv2_layer = test_controller_v3_conv2_layer
TOP_controller_v3_fc1_layer   = test_controller_v3_fc1_layer
TOP_tpu_top_v3_e2e            = test_tpu_top_v3_end_to_end

TOP_MODULE ?= $(TOP_$(TEST))
SNAPSHOT   ?= $(TOP_MODULE)_snapshot
TB_FILE    ?= $(SIM_DIR)/$(TOP_MODULE).sv
XSIM_ARGS  ?=

RTL_FILES = $(wildcard $(RTL_DIR)/*.sv)

.PHONY: all help list run compile elaborate simulate gui clean test_activation_window_gather test_weight_tile_buffer test_mxu_v3_2x2 test_tpu_datapath_v3 test_addrgen_tpu_datapath_v3 test_controller_v3_tile test_controller_v3_spatial_block test_controller_v3_rom_spatial_block_conv1 test_controller_v3_rom_tile test_controller_v3_rom_layer_fc2 test_controller_v3_conv1_pixel test_controller_v3_conv1_layer test_controller_v3_conv2_layer test_controller_v3_fc1_layer test_tpu_top_v3_e2e

all: run

help: list
	@echo ""
	@echo "Usage:"
	@echo "  make compile TEST=activation_window_gather"
	@echo "  make test_activation_window_gather"
	@echo "  make gui TEST=activation_window_gather"

list:
	@echo "Available V3 tests:"
	@echo "  activation_window_gather"
	@echo "  weight_tile_buffer"
	@echo "  mxu_v3_2x2"
	@echo "  tpu_datapath_v3"
	@echo "  addrgen_tpu_datapath_v3"
	@echo "  controller_v3_tile"
	@echo "  controller_v3_spatial_block"
	@echo "  controller_v3_rom_spatial_block_conv1"
	@echo "  controller_v3_rom_tile"
	@echo "  controller_v3_rom_layer_fc2"
	@echo "  controller_v3_conv1_pixel"
	@echo "  controller_v3_conv1_layer"
	@echo "  controller_v3_conv2_layer"
	@echo "  controller_v3_fc1_layer"
	@echo "  tpu_top_v3_e2e"

run: simulate

test_activation_window_gather:
	$(MAKE) run TEST=activation_window_gather

test_weight_tile_buffer:
	$(MAKE) run TEST=weight_tile_buffer

test_mxu_v3_2x2:
	$(MAKE) run TEST=mxu_v3_2x2

test_tpu_datapath_v3:
	$(MAKE) run TEST=tpu_datapath_v3

test_addrgen_tpu_datapath_v3:
	$(MAKE) run TEST=addrgen_tpu_datapath_v3

test_controller_v3_tile:
	$(MAKE) run TEST=controller_v3_tile

test_controller_v3_spatial_block:
	$(MAKE) run TEST=controller_v3_spatial_block

test_controller_v3_rom_spatial_block_conv1:
	$(MAKE) run TEST=controller_v3_rom_spatial_block_conv1

test_controller_v3_rom_tile:
	$(MAKE) run TEST=controller_v3_rom_tile

test_controller_v3_rom_layer_fc2:
	$(MAKE) run TEST=controller_v3_rom_layer_fc2

test_controller_v3_conv1_pixel:
	$(MAKE) run TEST=controller_v3_conv1_pixel

test_controller_v3_conv1_layer:
	$(MAKE) run TEST=controller_v3_conv1_layer

test_controller_v3_conv2_layer:
	$(MAKE) run TEST=controller_v3_conv2_layer

test_controller_v3_fc1_layer:
	$(MAKE) run TEST=controller_v3_fc1_layer

test_tpu_top_v3_e2e:
	$(MAKE) run TEST=tpu_top_v3_e2e

compile:
	@test -n "$(TOP_MODULE)" || (echo "Unknown TEST='$(TEST)'. Run 'make list'." && exit 1)
	xvlog -sv $(RTL_FILES) $(TB_FILE)

elaborate: compile
	xelab -debug typical -top $(TOP_MODULE) -snapshot $(SNAPSHOT)

simulate: elaborate
	xsim $(SNAPSHOT) -R $(XSIM_ARGS)

gui: elaborate
	xsim $(SNAPSHOT) -gui $(XSIM_ARGS)

clean:
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil *.str

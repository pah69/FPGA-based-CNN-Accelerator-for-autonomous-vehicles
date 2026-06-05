# Versioned simulation entry point.
#
# Examples:
#   make RTL_VERSION=v2 list
#   make RTL_VERSION=v3 compile TEST=tpu_top_e2e
#   make RTL_VERSION=v3 test_tpu_top_e2e_mnist_txt MNIST_TXT_COUNT=10

RTL_VERSION ?= v2
TB_DIR := tb_$(RTL_VERSION)

.PHONY: help list compile elaborate simulate run gui clean test_%

help:
	@echo "Usage:"
	@echo "  make RTL_VERSION=v2 list"
	@echo "  make RTL_VERSION=v3 list"
	@echo "  make RTL_VERSION=v2 compile TEST=tpu_top_e2e"
	@echo "  make RTL_VERSION=v3 test_tpu_top_e2e_mnist_txt MNIST_TXT_COUNT=10"
	@echo ""
	@echo "Version folders:"
	@echo "  tb_v2 -> ../../rtl/v2, TPU_SIZE=2"
	@echo "  tb_v3 -> ../../rtl/v3, TPU_SIZE=4"

list compile elaborate simulate run gui clean:
	@test -d "$(TB_DIR)" || (echo "Unknown RTL_VERSION='$(RTL_VERSION)' -> missing $(TB_DIR)" && exit 1)
	$(MAKE) -C $(TB_DIR) $@

test_%:
	@test -d "$(TB_DIR)" || (echo "Unknown RTL_VERSION='$(RTL_VERSION)' -> missing $(TB_DIR)" && exit 1)
	$(MAKE) -C $(TB_DIR) $@

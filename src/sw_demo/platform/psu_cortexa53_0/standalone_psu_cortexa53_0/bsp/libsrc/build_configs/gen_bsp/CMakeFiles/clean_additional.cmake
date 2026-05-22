# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo/platform/psu_cortexa53_0/standalone_psu_cortexa53_0/bsp/include/sleep.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo/platform/psu_cortexa53_0/standalone_psu_cortexa53_0/bsp/include/xiltimer.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo/platform/psu_cortexa53_0/standalone_psu_cortexa53_0/bsp/include/xtimer_config.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo/platform/psu_cortexa53_0/standalone_psu_cortexa53_0/bsp/lib/libxiltimer.a"
  )
endif()

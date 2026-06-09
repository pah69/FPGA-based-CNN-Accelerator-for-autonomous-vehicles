# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/ps7_cortexa9_1/standalone_ps7_cortexa9_1/bsp/include/sleep.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/ps7_cortexa9_1/standalone_ps7_cortexa9_1/bsp/include/xiltimer.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/ps7_cortexa9_1/standalone_ps7_cortexa9_1/bsp/include/xtimer_config.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/ps7_cortexa9_1/standalone_ps7_cortexa9_1/bsp/lib/libxiltimer.a"
  )
endif()

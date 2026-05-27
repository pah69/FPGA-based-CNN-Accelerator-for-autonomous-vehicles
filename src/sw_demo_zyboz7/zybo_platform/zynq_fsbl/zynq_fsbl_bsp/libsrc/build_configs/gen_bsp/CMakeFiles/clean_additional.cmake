# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/diskio.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/ff.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/ffconf.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/sleep.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/xilffs.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/xilffs_config.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/xilrsa.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/xiltimer.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/include/xtimer_config.h"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/lib/libxilffs.a"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/lib/libxilrsa.a"
  "/home/pah/fpga_cnn_accelerator/FPGA-based-CNN-Accelerator-for-autonomous-vehicles/src/sw_demo_zyboz7/zybo_platform/zynq_fsbl/zynq_fsbl_bsp/lib/libxiltimer.a"
  )
endif()

# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ACC_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ACC_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ACC_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXI_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BANK_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BIAS_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_NUM_TILES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OUT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "REQUANT_MULT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "REQUANT_SHIFT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SIZE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TILE_COUNT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "UB_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WGT_FIFO_DEPTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.ACC_ADDR_WIDTH { PARAM_VALUE.ACC_ADDR_WIDTH } {
	# Procedure called to update ACC_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ACC_ADDR_WIDTH { PARAM_VALUE.ACC_ADDR_WIDTH } {
	# Procedure called to validate ACC_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.ACC_DEPTH { PARAM_VALUE.ACC_DEPTH } {
	# Procedure called to update ACC_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ACC_DEPTH { PARAM_VALUE.ACC_DEPTH } {
	# Procedure called to validate ACC_DEPTH
	return true
}

proc update_PARAM_VALUE.ACC_WIDTH { PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to update ACC_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ACC_WIDTH { PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to validate ACC_WIDTH
	return true
}

proc update_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to update AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to validate AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.AXI_DATA_WIDTH { PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to update AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXI_DATA_WIDTH { PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to validate AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.BANK_DEPTH { PARAM_VALUE.BANK_DEPTH } {
	# Procedure called to update BANK_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BANK_DEPTH { PARAM_VALUE.BANK_DEPTH } {
	# Procedure called to validate BANK_DEPTH
	return true
}

proc update_PARAM_VALUE.BIAS_WIDTH { PARAM_VALUE.BIAS_WIDTH } {
	# Procedure called to update BIAS_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BIAS_WIDTH { PARAM_VALUE.BIAS_WIDTH } {
	# Procedure called to validate BIAS_WIDTH
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to update DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to validate DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.MAX_NUM_TILES { PARAM_VALUE.MAX_NUM_TILES } {
	# Procedure called to update MAX_NUM_TILES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_NUM_TILES { PARAM_VALUE.MAX_NUM_TILES } {
	# Procedure called to validate MAX_NUM_TILES
	return true
}

proc update_PARAM_VALUE.OUT_WIDTH { PARAM_VALUE.OUT_WIDTH } {
	# Procedure called to update OUT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OUT_WIDTH { PARAM_VALUE.OUT_WIDTH } {
	# Procedure called to validate OUT_WIDTH
	return true
}

proc update_PARAM_VALUE.REQUANT_MULT_WIDTH { PARAM_VALUE.REQUANT_MULT_WIDTH } {
	# Procedure called to update REQUANT_MULT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.REQUANT_MULT_WIDTH { PARAM_VALUE.REQUANT_MULT_WIDTH } {
	# Procedure called to validate REQUANT_MULT_WIDTH
	return true
}

proc update_PARAM_VALUE.REQUANT_SHIFT_WIDTH { PARAM_VALUE.REQUANT_SHIFT_WIDTH } {
	# Procedure called to update REQUANT_SHIFT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.REQUANT_SHIFT_WIDTH { PARAM_VALUE.REQUANT_SHIFT_WIDTH } {
	# Procedure called to validate REQUANT_SHIFT_WIDTH
	return true
}

proc update_PARAM_VALUE.SIZE { PARAM_VALUE.SIZE } {
	# Procedure called to update SIZE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SIZE { PARAM_VALUE.SIZE } {
	# Procedure called to validate SIZE
	return true
}

proc update_PARAM_VALUE.TILE_COUNT_WIDTH { PARAM_VALUE.TILE_COUNT_WIDTH } {
	# Procedure called to update TILE_COUNT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TILE_COUNT_WIDTH { PARAM_VALUE.TILE_COUNT_WIDTH } {
	# Procedure called to validate TILE_COUNT_WIDTH
	return true
}

proc update_PARAM_VALUE.UB_ADDR_WIDTH { PARAM_VALUE.UB_ADDR_WIDTH } {
	# Procedure called to update UB_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UB_ADDR_WIDTH { PARAM_VALUE.UB_ADDR_WIDTH } {
	# Procedure called to validate UB_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.WGT_FIFO_DEPTH { PARAM_VALUE.WGT_FIFO_DEPTH } {
	# Procedure called to update WGT_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WGT_FIFO_DEPTH { PARAM_VALUE.WGT_FIFO_DEPTH } {
	# Procedure called to validate WGT_FIFO_DEPTH
	return true
}


proc update_MODELPARAM_VALUE.AXI_ADDR_WIDTH { MODELPARAM_VALUE.AXI_ADDR_WIDTH PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.AXI_DATA_WIDTH { MODELPARAM_VALUE.AXI_DATA_WIDTH PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.SIZE { MODELPARAM_VALUE.SIZE PARAM_VALUE.SIZE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SIZE}] ${MODELPARAM_VALUE.SIZE}
}

proc update_MODELPARAM_VALUE.DATA_WIDTH { MODELPARAM_VALUE.DATA_WIDTH PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH}] ${MODELPARAM_VALUE.DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.ACC_WIDTH { MODELPARAM_VALUE.ACC_WIDTH PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ACC_WIDTH}] ${MODELPARAM_VALUE.ACC_WIDTH}
}

proc update_MODELPARAM_VALUE.ACC_DEPTH { MODELPARAM_VALUE.ACC_DEPTH PARAM_VALUE.ACC_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ACC_DEPTH}] ${MODELPARAM_VALUE.ACC_DEPTH}
}

proc update_MODELPARAM_VALUE.ACC_ADDR_WIDTH { MODELPARAM_VALUE.ACC_ADDR_WIDTH PARAM_VALUE.ACC_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ACC_ADDR_WIDTH}] ${MODELPARAM_VALUE.ACC_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.OUT_WIDTH { MODELPARAM_VALUE.OUT_WIDTH PARAM_VALUE.OUT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OUT_WIDTH}] ${MODELPARAM_VALUE.OUT_WIDTH}
}

proc update_MODELPARAM_VALUE.BIAS_WIDTH { MODELPARAM_VALUE.BIAS_WIDTH PARAM_VALUE.BIAS_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BIAS_WIDTH}] ${MODELPARAM_VALUE.BIAS_WIDTH}
}

proc update_MODELPARAM_VALUE.REQUANT_MULT_WIDTH { MODELPARAM_VALUE.REQUANT_MULT_WIDTH PARAM_VALUE.REQUANT_MULT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.REQUANT_MULT_WIDTH}] ${MODELPARAM_VALUE.REQUANT_MULT_WIDTH}
}

proc update_MODELPARAM_VALUE.REQUANT_SHIFT_WIDTH { MODELPARAM_VALUE.REQUANT_SHIFT_WIDTH PARAM_VALUE.REQUANT_SHIFT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.REQUANT_SHIFT_WIDTH}] ${MODELPARAM_VALUE.REQUANT_SHIFT_WIDTH}
}

proc update_MODELPARAM_VALUE.MAX_NUM_TILES { MODELPARAM_VALUE.MAX_NUM_TILES PARAM_VALUE.MAX_NUM_TILES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_NUM_TILES}] ${MODELPARAM_VALUE.MAX_NUM_TILES}
}

proc update_MODELPARAM_VALUE.TILE_COUNT_WIDTH { MODELPARAM_VALUE.TILE_COUNT_WIDTH PARAM_VALUE.TILE_COUNT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TILE_COUNT_WIDTH}] ${MODELPARAM_VALUE.TILE_COUNT_WIDTH}
}

proc update_MODELPARAM_VALUE.WGT_FIFO_DEPTH { MODELPARAM_VALUE.WGT_FIFO_DEPTH PARAM_VALUE.WGT_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WGT_FIFO_DEPTH}] ${MODELPARAM_VALUE.WGT_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.BANK_DEPTH { MODELPARAM_VALUE.BANK_DEPTH PARAM_VALUE.BANK_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BANK_DEPTH}] ${MODELPARAM_VALUE.BANK_DEPTH}
}

proc update_MODELPARAM_VALUE.UB_ADDR_WIDTH { MODELPARAM_VALUE.UB_ADDR_WIDTH PARAM_VALUE.UB_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.UB_ADDR_WIDTH}] ${MODELPARAM_VALUE.UB_ADDR_WIDTH}
}


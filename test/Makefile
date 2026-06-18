SIM              ?= icarus
TOPLEVEL_LANG    ?= verilog
SRC_DIR           = $(PWD)/../src

PROJECT_SOURCES  = tt_um_sem20_mac.v      \
                   sem20_inference_top.v  \
                   q8p8_to_sem20.v        \
                   sem20_mac.v            \
                   sem20_mul.v            \
                   sem20_acc_ip.v         \
                   sem20_add.v            \
                   sem20_to_q8p8.v

ifneq ($(GATES),yes)
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
else
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST -DFUNCTIONAL -DUSE_POWER_PINS -DSIM -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

COMPILE_ARGS    += -I$(SRC_DIR)
COMPILE_ARGS    += -DCOCOTB_SIM
TOPLEVEL         = tt_um_sem20_mac
COCOTB_TEST_MODULES = test

include $(shell cocotb-config --makefiles)/Makefile.sim

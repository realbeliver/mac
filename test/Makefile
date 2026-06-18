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

# RTL simulation
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate-level simulation (gf180mcuD PDK)
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

COMPILE_ARGS    += -I$(SRC_DIR)
COMPILE_ARGS    += -DCOCOTB_SIM

TOPLEVEL         = tt_um_sem20_mac
COCOTB_TEST_MODULES = test

include $(shell cocotb-config --makefiles)/Makefile.sim

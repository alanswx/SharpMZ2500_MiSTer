#============================================================================
#  Sharp MZ-2500 Verilator simulation
#
#    make            # headless sim            -> ./obj_dir_headless/Vtop
#    make netlist    # VHDL leaves -> Verilog  -> gen/*.v
#    make test       # smoke tests (run_tests.sh)
#    make clean
#
#  The machine top (rtl/mz2500.sv) is SystemVerilog and goes to Verilator as is.
#  The VHDL leaves shared with SharpMZ_MiSTer (T80, later the 8255, 8253 and
#  Z80 PIO) are turned into Verilog netlists by "ghdl synth", one per entity, as
#  SharpMZ_MiSTer's sim does for its whole core. Module and register names
#  survive; combinational nodes become nNNNN.
#
#  ghdl synth fixes generics at synthesis time: give each entity the same
#  generic values here (-g...) as its instance in the RTL. A second instance
#  with other generics needs its own netlist and module name.
#
#  Requires: ghdl (5.x, synth built in), verilator (5.x), python3.
#============================================================================

V      = verilator
GHDL   = ghdl
RTL    = ../rtl
GEN    = gen
WORK   = ghdl_work

GHDL_FLAGS = --std=08 -fsynopsys -fexplicit -frelaxed -Wno-hide -Wno-shared -Wno-binding \
	--workdir=$(WORK)

# T80 v350 (Sorgelig's MiSTer T80, ZEXALL-tested), T80s wrapper
T80_SRC = \
	$(RTL)/T80_v350/T80_ALU.vhd \
	$(RTL)/T80_v350/T80_Reg.vhd \
	$(RTL)/T80_v350/T80_MCode.vhd \
	$(RTL)/T80_v350/T80.vhd \
	$(RTL)/T80_v350/T80s.vhd

VHD_SRC = $(T80_SRC)

# One netlist per VHDL entity the SystemVerilog instantiates.
GEN_V = $(GEN)/t80s.v

SV_SRC = sim.v sdram_model.sv $(RTL)/mz2500.sv $(RTL)/mz2500_video.sv $(RTL)/mz2500_int.sv $(RTL)/mz2500_kbd.sv \
	$(RTL)/mz_pit8253.sv $(RTL)/dpram.sv $(RTL)/mz2500_fdc.sv $(RTL)/rp5c15.sv $(RTL)/wd1793.sv $(RTL)/wd1793_mem.v
JT12_SRC = $(wildcard $(RTL)/jt12/*.v) $(wildcard $(RTL)/jt12/jt49/*.v)
V_SRC  = $(SV_SRC) $(JT12_SRC) $(GEN_V)

V_OPT = -O3 --x-assign fast --x-initial fast --noassert --savable \
	-Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-MULTIDRIVEN -Wno-LATCH \
	-Wno-TIMESCALEMOD -Wno-COMBDLY

# EXTRA: more Verilator options, e.g. make fast FAST_DIR=obj_dir_dbg EXTRA=-DDEBUG_FDC_READ
V_OPT += $(EXTRA)

CXXFLAGS = -O3 -std=c++17
HL_DIR   = obj_dir_headless
HL_EXE   = ./$(HL_DIR)/Vtop

all: headless

headless: $(HL_EXE)

# ---------------------------------------------------------------------------
# VHDL -> Verilog netlists
# ---------------------------------------------------------------------------
$(WORK)/.analysed: $(VHD_SRC) Makefile
	@mkdir -p $(WORK)
	$(GHDL) -a $(GHDL_FLAGS) $(VHD_SRC)
	@touch $@

# T80s as rtl/mz2500.sv instantiates it: Mode 0 (Z80), T2Write 1, IOWait 1.
$(GEN)/t80s.v: $(WORK)/.analysed fix_port_aliases.py
	@mkdir -p $(GEN)
	$(GHDL) synth $(GHDL_FLAGS) -gMode=0 -gT2Write=1 -gIOWait=1 --out=verilog T80s > $@.tmp
	$(GHDL) synth $(GHDL_FLAGS) -gMode=0 -gT2Write=1 -gIOWait=1 --out=vhdl T80s > $(GEN)/t80s_netlist.vhd
	python3 fix_port_aliases.py $@.tmp $(GEN)/t80s_netlist.vhd
	@# VHDL names that are (System)Verilog keywords.
	perl -pi -e 's/\b(do|config)\b/$${1}_v/g' $@.tmp
	@mv $@.tmp $@

netlist: $(GEN_V)

# ---------------------------------------------------------------------------
# Headless: no SDL. Screenshots, frame logs and traces for regressions.
# ---------------------------------------------------------------------------
$(HL_EXE): $(V_SRC) sim_headless.cpp ps2_keys.h Makefile
	$V -cc $(V_OPT) --exe --build -j 0 --Mdir $(HL_DIR) --top-module top \
		-CFLAGS "$(CXXFLAGS)" $(V_SRC) sim_headless.cpp -o Vtop

# Fast: clk_sys at half rate (MZ_FAST_SIM), same machine otherwise; about twice the speed. Frame timing and
# CPU cycles per frame are the same; the CPU's wait states can differ by a clock here and there.
FAST_DIR = obj_dir_fast
FAST_EXE = ./$(FAST_DIR)/Vtop

fast: $(FAST_EXE)

$(FAST_EXE): $(V_SRC) sim_headless.cpp ps2_keys.h Makefile
	$V -cc $(V_OPT) -DMZ_FAST_SIM --exe --build -j 0 --Mdir $(FAST_DIR) --top-module top \
		-CFLAGS "$(CXXFLAGS) -DMZ_FAST_SIM" $(V_SRC) sim_headless.cpp -o Vtop

test: headless
	./run_tests.sh

clean:
	rm -rf $(HL_DIR) $(FAST_DIR) $(GEN) $(WORK) out

.PHONY: all headless fast netlist test clean

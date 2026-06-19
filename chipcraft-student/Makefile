# ChipCraft Lab — Verilog compile & simulate
#
# Usage (from any directory):
#   make              – compile + simulate
#   make wave         – compile + simulate + open GTKWave
#   make compile      – compile only
#   make sim          – run simulation only (after compile)
#   make clean        – remove build outputs
#
# LABS can be overridden: make LABS=~/mydir

# Directory where decrypted .v files live (tmpfs)
LABS    ?= $(HOME)/labs

# Auto-detect the testbench and all design files inside LABS
TB      := $(firstword $(wildcard $(LABS)/tb_*.v))
TOP     := $(basename $(notdir $(TB)))
SRCS    := $(wildcard $(LABS)/*.v)
SIM_OUT := $(LABS)/sim.vvp
VCD     := $(LABS)/$(patsubst tb_%.v,%.vcd,$(notdir $(TB)))

# Colour helpers
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RESET  := \033[0m

.PHONY: all compile sim wave clean

all: compile sim

compile: $(SIM_OUT)

$(SIM_OUT): $(SRCS)
	@echo "$(GREEN)Compiling: $(SRCS)$(RESET)"
	iverilog -g2012 -Wall -o $(SIM_OUT) $(SRCS)
	@echo "$(GREEN)Done — run 'make sim' to simulate$(RESET)"

sim: $(SIM_OUT)
	@echo "$(YELLOW)Running simulation …$(RESET)"
	vvp $(SIM_OUT)
	@echo "$(GREEN)Simulation complete.$(RESET)"
	@[ -f $(VCD) ] && echo "$(GREEN)Waveform: $(VCD)  →  run 'make wave' to open GTKWave$(RESET)" || true

wave: sim
	@echo "$(YELLOW)Opening GTKWave …$(RESET)"
	gtkwave $(VCD) &

clean:
	rm -f $(SIM_OUT) *.vcd
	@echo "Cleaned."

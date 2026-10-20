PYTHON ?= python3
VERILATOR ?= verilator
XRUN ?= xrun
BUILD_DIR := build
VLT_EXE := $(BUILD_DIR)/obj_dir/Vrv32i_core_tb

.PHONY: help generate py-test structure check uvm-syntax lint build smoke traps regress waves xcelium-smoke xcelium-traps clean

help:
	@echo "make py-test         Run encoder/reference-model unit tests"
	@echo "make check           Run reference and repository-structure checks"
	@echo "make uvm-syntax      Parse every UVM source unit (syntax only)"
	@echo "make regress         Build with Verilator and run smoke + eight trap tests"
	@echo "make waves           Run smoke and write results/rv32i_core.vcd"
	@echo "make xcelium-smoke   Run the full UVM smoke test in Cadence Xcelium"
	@echo "make xcelium-traps   Run UVM terminal-trap tests in Xcelium"

generate:
	$(PYTHON) scripts/gen_programs.py

py-test: generate
	$(PYTHON) -m unittest -v tests/test_reference.py

structure:
	$(PYTHON) scripts/structure_check.py

check: py-test structure

uvm-syntax:
	$(PYTHON) scripts/uvm_syntax_check.py

lint: generate
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --lint-only --timing --assert -Wall -Wno-fatal \
		-Wno-SYNCASYNCNET -f dv/filelists/portable.f

build: generate
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert --trace -Wall -Wno-fatal \
		-Wno-SYNCASYNCNET \
		--Mdir $(abspath $(BUILD_DIR)/obj_dir) --top-module rv32i_core_tb \
		-f dv/filelists/portable.f

smoke: build
	$(VLT_EXE) +TEST=smoke \
		+PROGRAM=dv/programs/rv32i_smoke.hex \
		+EXPECTED=dv/programs/rv32i_smoke_expected.hex

traps: build
	$(VLT_EXE) +TEST=illegal +PROGRAM=dv/programs/illegal.hex +EXPECTED_CAUSE=2
	$(VLT_EXE) +TEST=instr_misaligned +PROGRAM=dv/programs/instr_misaligned.hex +EXPECTED_CAUSE=0
	$(VLT_EXE) +TEST=load_misaligned +PROGRAM=dv/programs/load_misaligned.hex +EXPECTED_CAUSE=4
	$(VLT_EXE) +TEST=store_misaligned +PROGRAM=dv/programs/store_misaligned.hex +EXPECTED_CAUSE=6
	$(VLT_EXE) +TEST=ecall +PROGRAM=dv/programs/ecall.hex +EXPECTED_CAUSE=11
	$(VLT_EXE) +TEST=imem_access_fault +PROGRAM=dv/programs/imem_access_fault.hex +EXPECTED_CAUSE=1 +IMEM_ERROR=1
	$(VLT_EXE) +TEST=load_access_fault +PROGRAM=dv/programs/load_access_fault.hex +EXPECTED_CAUSE=5 +DMEM_ERROR=1
	$(VLT_EXE) +TEST=store_access_fault +PROGRAM=dv/programs/store_access_fault.hex +EXPECTED_CAUSE=7 +DMEM_ERROR=1

regress: check uvm-syntax smoke traps

waves: build
	mkdir -p results
	$(VLT_EXE) +TEST=smoke +WAVES \
		+PROGRAM=dv/programs/rv32i_smoke.hex \
		+EXPECTED=dv/programs/rv32i_smoke_expected.hex

xcelium-smoke: generate
	mkdir -p build/xcelium results/xcelium
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc \
		-f dv/filelists/uvm.f -top rv32i_uvm_top \
		+UVM_TESTNAME=rv32i_smoke_test \
		+PROGRAM=dv/programs/rv32i_smoke.hex \
		+EXPECTED=dv/programs/rv32i_smoke_expected.hex \
		-covoverwrite -coverage all -covtest rv32i_smoke \
		-l results/xcelium/rv32i_smoke.log

xcelium-traps: generate
	mkdir -p build/xcelium results/xcelium
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/illegal.hex +EXPECTED_CAUSE=2 \
		-l results/xcelium/rv32i_illegal.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/instr_misaligned.hex +EXPECTED_CAUSE=0 \
		-l results/xcelium/rv32i_instr_misaligned.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/load_misaligned.hex +EXPECTED_CAUSE=4 \
		-l results/xcelium/rv32i_load_misaligned.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/store_misaligned.hex +EXPECTED_CAUSE=6 \
		-l results/xcelium/rv32i_store_misaligned.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/ecall.hex +EXPECTED_CAUSE=11 \
		-l results/xcelium/rv32i_ecall.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/imem_access_fault.hex +EXPECTED_CAUSE=1 +IMEM_ERROR=1 \
		-l results/xcelium/rv32i_imem_access_fault.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/load_access_fault.hex +EXPECTED_CAUSE=5 +DMEM_ERROR=1 \
		-l results/xcelium/rv32i_load_access_fault.log
	$(XRUN) -64bit -sv -uvm -uvmhome CDNS-1.2 -access +rwc -f dv/filelists/uvm.f \
		-top rv32i_uvm_top +UVM_TESTNAME=rv32i_trap_test \
		+PROGRAM=dv/programs/store_access_fault.hex +EXPECTED_CAUSE=7 +DMEM_ERROR=1 \
		-l results/xcelium/rv32i_store_access_fault.log

clean:
	rm -rf build xcelium.d INCA_libs waves.shm
	rm -f results/rv32i_core.vcd results/xcelium/*.log

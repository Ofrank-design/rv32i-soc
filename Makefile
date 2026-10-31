# Everything is built under $(BUILD) (default: build). `make release` uses build/release.
CROSS    ?= riscv64-unknown-elf-
BUILD    ?= build
KEY      ?= tools/dev.key
APP      ?= app_blink
APP_DEFS ?=

AS      := $(CROSS)as -march=rv32i_zicsr -mabi=ilp32 -mno-relax
LD      := $(CROSS)ld -m elf32lriscv --no-relax
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
CC      := $(CROSS)gcc -march=rv32i_zicsr -mabi=ilp32 -Os -ffreestanding -fno-builtin -nostdlib \
           -fno-pic -mno-relax -fno-tree-loop-distribute-patterns

FW   := blink matrix cputest traptest matrix_irq
BOOT := boot_ok boot_bad boot_forged
RTL  := rtl/instr_decoder.sv rtl/alu.sv rtl/regfile.sv rtl/control.sv rtl/csr_file.sv \
        rtl/cpu_core.sv rtl/memories.sv rtl/soc_top.sv

# Board settings (ULX3S with the ECP5-25F). Other boards need their own top level and .lpf.
FPGA_FREQ ?= 25
FPGA_ARGS := --25k --package CABGA381 --speed 6

.SECONDARY:
.PHONY: all sim lint synth check clean disasm fpga flash release newkey gatesim gatesim-boot boardsim

all: $(FW:%=$(BUILD)/%.hex) $(BOOT:%=$(BUILD)/%.hex)

# ---- firmware used by the simulations -------------------------------------------------
$(BUILD)/%.elf: fw/start.s fw/%.s fw/link.ld
	@mkdir -p $(BUILD)
	$(AS) fw/start.s -o $(BUILD)/start.o
	$(AS) fw/$*.s -o $(BUILD)/$*.o
	$(LD) -T fw/link.ld $(BUILD)/start.o $(BUILD)/$*.o -o $@

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/%.hex: $(BUILD)/%.bin tools/bin2hex.py
	python3 tools/bin2hex.py $< $@

# ---- bootloader, signed application, full ROM image -----------------------------------
$(BUILD)/sha_consts.h $(BUILD)/key.h: tools/gen_headers.py $(KEY)
	@mkdir -p $(BUILD)
	python3 tools/gen_headers.py $(KEY) $(BUILD)

$(BUILD)/boot.elf: fw/boot.s fw/boot_main.c fw/boot.ld $(BUILD)/sha_consts.h $(BUILD)/key.h
	$(AS) fw/boot.s -o $(BUILD)/boot_s.o
	$(CC) -I$(BUILD) -c fw/boot_main.c -o $(BUILD)/boot_main.o
	$(LD) -T fw/boot.ld $(BUILD)/boot_s.o $(BUILD)/boot_main.o -o $@

$(BUILD)/app.elf: fw/start.s fw/$(APP).s fw/app.ld
	@mkdir -p $(BUILD)
	$(AS) fw/start.s -o $(BUILD)/start_app.o
	$(AS) $(APP_DEFS) fw/$(APP).s -o $(BUILD)/app_main.o
	$(LD) -T fw/app.ld $(BUILD)/start_app.o $(BUILD)/app_main.o -o $@

$(BUILD)/image.hex: $(BUILD)/boot.bin $(BUILD)/app.bin tools/mkimage.py $(KEY)
	python3 tools/mkimage.py $(BUILD)/boot.bin $(BUILD)/app.bin $@ $(KEY)

$(BUILD)/boot_ok.hex: $(BUILD)/image.hex
	cp $< $@

$(BUILD)/boot_bad.hex: $(BUILD)/boot.bin $(BUILD)/app.bin tools/mkimage.py $(KEY)
	python3 tools/mkimage.py $(BUILD)/boot.bin $(BUILD)/app.bin $@ $(KEY) --tamper

$(BUILD)/boot_forged.hex: $(BUILD)/boot.bin $(BUILD)/app.bin tools/mkimage.py tools/attacker.key
	python3 tools/mkimage.py $(BUILD)/boot.bin $(BUILD)/app.bin $@ tools/attacker.key

# ---- simulation, lint, synthesis ------------------------------------------------------
$(BUILD)/sim: $(RTL) rtl/rv_defs.svh tb/tb_soc.sv
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl -o $@ $(RTL) tb/tb_soc.sv

sim: $(BUILD)/sim all
	@fail=0; for t in $(FW) $(BOOT); do \
	    out=$$(vvp $(BUILD)/sim +HEX=$(BUILD)/$$t.hex +TEST=$$t); \
	    echo "$$out" | grep -E "PASS|FAIL|mailbox"; \
	    echo "$$out" | grep -q "^PASS" || fail=1; \
	done; exit $$fail

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Irtl \
	    --top-module fpga_top $(RTL) rtl/fpga_top.sv

# Generic synthesis of the core on its own.
synth:
	yosys -p "read_verilog -sv -Irtl rtl/instr_decoder.sv rtl/alu.sv rtl/regfile.sv rtl/control.sv rtl/csr_file.sv rtl/cpu_core.sv; hierarchy -check -top cpu_core; synth -top cpu_core -flatten; check -assert; stat" | tail -40

# Board-level test on the RTL: power-on reset, signed-image boot, button toggling the LED.
boardsim: $(BUILD)/image.hex
	iverilog -g2012 -Irtl -o $(BUILD)/sim_board $(RTL) rtl/fpga_top.sv tb/tb_fpga.sv
	cd $(BUILD) && vvp sim_board | grep -E "PASS|FAIL"

check: lint synth sim boardsim

# ---- FPGA bitstream (ULX3S) -----------------------------------------------------------
# nextpnr stops with an error if the design misses $(FPGA_FREQ) MHz, so a successful build
# means timing was met.
$(BUILD)/fpga.json: $(RTL) rtl/rv_defs.svh rtl/fpga_top.sv $(BUILD)/image.hex
	printf 'read_verilog -sv -Irtl %s\nchparam -set ROM_INIT "%s" fpga_top\nsynth_ecp5 -top fpga_top -json %s\n' \
	    "$(RTL) rtl/fpga_top.sv" "$(BUILD)/image.hex" "$@" > $(BUILD)/fpga.ys
	yosys -q -l $(BUILD)/yosys.log $(BUILD)/fpga.ys

# Gate-level check of the synthesized logic (CPU, bus, peripherals, reset, button path).
# Yosys' ECP5 simulation library has no behavioral model for block RAM, so for this run the
# memories are synthesized into ordinary logic (-nobram -nolutram), RAM is shrunk to 256 bytes and ROM to 1 KB and the
# power-on delay is cut to 64 clocks to keep the simulation quick. The block-RAM mapping itself
# is covered by yosys, nextpnr and timing, not by this test.
#   make gatesim        runs the polling blink image (starts in about 100 clocks)
#   make gatesim-boot   runs the signed image through the HMAC bootloader (slow: ~110k clocks)
GATE_IMG  ?= $(BUILD)/blink.hex
GATE_WAIT ?= 300
gatesim gatesim-boot:
	@mkdir -p $(BUILD)
	printf 'read_verilog -sv -Irtl %s\nchparam -set ROM_INIT "%s" fpga_top\nchparam -set RAM_WORDS 64 fpga_top\nchparam -set ROM_WORDS $(if $(filter gatesim-boot,$@),2048,256) fpga_top\nchparam -set POR_BITS $(if $(filter gatesim-boot,$@),16,6) fpga_top\nsynth_ecp5 -nobram -nolutram -top fpga_top\nwrite_verilog -noattr %s\n' \
	    "$(RTL) rtl/fpga_top.sv" "$(if $(filter gatesim-boot,$@),$(BUILD)/image.hex,$(GATE_IMG))" "$(BUILD)/$@.v" > $(BUILD)/$@.ys
	yosys -q -l $(BUILD)/$@.log $(BUILD)/$@.ys
	iverilog -g2012 -Ptb_fpga.BOOT_WAIT=$(if $(filter gatesim-boot,$@),60000,$(GATE_WAIT)) -Ptb_fpga.PRESS=$(if $(filter gatesim-boot,$@),3000,300) -I/usr/share/yosys/ecp5 \
	    -o $(BUILD)/$@.vvp $(BUILD)/$@.v /usr/share/yosys/ecp5/cells_sim.v tb/tb_fpga.sv
	cd $(BUILD) && vvp $@.vvp | grep -E "PASS|FAIL"

$(BUILD)/fpga.config: $(BUILD)/fpga.json fpga/ulx3s.lpf
	nextpnr-ecp5 $(FPGA_ARGS) --json $< --lpf fpga/ulx3s.lpf --textcfg $@ \
	    --freq $(FPGA_FREQ) --report $(BUILD)/timing.json -l $(BUILD)/pnr.log -q

$(BUILD)/fpga.bit: $(BUILD)/fpga.config
	ecppack --compress --input $< --bit $@

fpga: $(BUILD)/fpga.bit
	@grep -E "Max frequency|ECP5_|DP16KD|TRELLIS_FF|LUT4" $(BUILD)/pnr.log | tail -12

flash: $(BUILD)/fpga.bit
	openFPGALoader -b ulx3s $<

# ---- release build: your own key, 1 ms debounce tick for a 25 MHz clock ---------------
# Usage: make newkey ; make release KEY=keys/release.key
release:
	@test -f "$(KEY)" || { echo "KEY=$(KEY) not found (make newkey first)"; exit 1; }
	@test "$(KEY)" != "tools/dev.key" || { echo "refusing to release with the demo key"; exit 1; }
	$(MAKE) BUILD=build/release KEY=$(KEY) APP=$(APP) \
	    APP_DEFS="--defsym SAMPLE_CYCLES=25000 --defsym TICK=3125" fpga
	@echo "Bitstream: build/release/fpga.bit"

newkey:
	@mkdir -p keys
	@test ! -e keys/release.key || { echo "keys/release.key already exists"; exit 1; }
	python3 -c "import secrets; print(secrets.token_hex(32))" > keys/release.key
	@chmod 600 keys/release.key
	@echo "Wrote keys/release.key (ignored by git). Back it up somewhere safe."

disasm: all
	@for t in $(FW); do $(OBJDUMP) -d $(BUILD)/$$t.elf; done

clean:
	rm -rf build

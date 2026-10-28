CROSS   ?= riscv64-unknown-elf-
AS      := $(CROSS)as -march=rv32i_zicsr -mabi=ilp32 -mno-relax
LD      := $(CROSS)ld -m elf32lriscv --no-relax -T fw/link.ld
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
FW      := blink matrix cputest traptest matrix_irq
BOOT    := boot_ok boot_bad boot_forged
APP_DEFS ?=
RTL     := rtl/instr_decoder.sv rtl/alu.sv rtl/regfile.sv rtl/control.sv rtl/csr_file.sv \
           rtl/cpu_core.sv rtl/memories.sv rtl/soc_top.sv

.SECONDARY:
.PHONY: all sim lint synth check clean disasm
all: $(FW:%=build/%.hex) $(BOOT:%=build/%.hex)

build/%.elf: fw/start.s fw/%.s fw/link.ld
	@mkdir -p build
	$(AS) fw/start.s -o build/start.o
	$(AS) fw/$*.s -o build/$*.o
	$(LD) build/start.o build/$*.o -o $@

build/%.bin: build/%.elf
	$(OBJCOPY) -O binary $< $@

build/%.hex: build/%.bin tools/bin2hex.py
	python3 tools/bin2hex.py $< $@

build/sha_consts.h build/key.h: tools/gen_headers.py tools/dev.key
	@mkdir -p build
	python3 tools/gen_headers.py tools/dev.key build

build/boot.elf: fw/boot.s fw/boot_main.c fw/boot.ld build/sha_consts.h build/key.h
	$(AS) fw/boot.s -o build/boot_s.o
	$(CROSS)gcc -march=rv32i_zicsr -mabi=ilp32 -Os -ffreestanding -fno-builtin -nostdlib -fno-pic \
	    -mno-relax -fno-tree-loop-distribute-patterns -Ibuild -c fw/boot_main.c -o build/boot_main.o
	$(CROSS)ld -m elf32lriscv --no-relax -T fw/boot.ld build/boot_s.o build/boot_main.o -o $@

build/app.elf: fw/start.s fw/app_blink.s fw/app.ld
	@mkdir -p build
	$(AS) fw/start.s -o build/start_app.o
	$(AS) $(APP_DEFS) fw/app_blink.s -o build/app_blink.o
	$(CROSS)ld -m elf32lriscv --no-relax -T fw/app.ld build/start_app.o build/app_blink.o -o $@

build/boot_ok.hex: build/boot.bin build/app.bin tools/mkimage.py tools/dev.key
	python3 tools/mkimage.py build/boot.bin build/app.bin $@ tools/dev.key

build/boot_bad.hex: build/boot.bin build/app.bin tools/mkimage.py tools/dev.key
	python3 tools/mkimage.py build/boot.bin build/app.bin $@ tools/dev.key --tamper

build/boot_forged.hex: build/boot.bin build/app.bin tools/mkimage.py tools/attacker.key
	python3 tools/mkimage.py build/boot.bin build/app.bin $@ tools/attacker.key

build/sim: $(RTL) rtl/rv_defs.svh tb/tb_soc.sv
	@mkdir -p build
	iverilog -g2012 -Irtl -o $@ $(RTL) tb/tb_soc.sv

sim: build/sim all
	@fail=0; for t in $(FW) $(BOOT); do \
	    out=$$(vvp build/sim +HEX=build/$$t.hex +TEST=$$t); \
	    echo "$$out" | grep -E "PASS|FAIL|mailbox"; \
	    echo "$$out" | grep -q "^PASS" || fail=1; \
	done; exit $$fail

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Irtl \
	    --top-module soc_top $(RTL)

# Generic synthesis of the core only (the SoC memories use $$readmemh, which is simulation-only).
synth:
	yosys -p "read_verilog -sv -Irtl rtl/instr_decoder.sv rtl/alu.sv rtl/regfile.sv rtl/control.sv rtl/csr_file.sv rtl/cpu_core.sv; hierarchy -check -top cpu_core; synth -top cpu_core -flatten; check -assert; stat" | tail -40

check: lint synth sim

disasm: all
	@for t in $(FW); do $(OBJDUMP) -d build/$$t.elf; done

clean:
	rm -rf build

# rv32i-soc

A small RV32I processor in SystemVerilog, plus the bare-metal firmware that runs on it: a
bootloader that checks the application before running it, a button/LED program, and an 8x8 LED
matrix driver. Everything runs in simulation with open-source tools. It was built as a way to
see the whole stack at once, from the instruction decoder up to a button press toggling an LED.

It has not been run on real hardware yet. The peripherals (GPIO, LED matrix, timer) have
register layouts I made up for this project, so expect to adjust them for an actual board.

## What's in it

**The core** is single-cycle: one instruction per clock, no pipeline, except loads, which take two clocks because FPGA block RAM returns data a cycle after the address. It implements all of RV32I
(including byte and halfword loads/stores), treats FENCE and WFI as no-ops, and has enough
machine-mode support for traps and a timer interrupt:

- CSRs: `mstatus` (MIE/MPIE), `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`,
  `mip`, `mcycle`, `minstret`, `mhartid`, with all six CSR instruction forms and `mret`
- Exceptions: illegal instruction, `ebreak`, `ecall`, misaligned jump target, misaligned load,
  misaligned store
- Interrupt: machine timer

An instruction that traps changes nothing: no register write, no store, no CSR update.

**The firmware** (`fw/`):

| File | What it does |
|---|---|
| `start.s` | Startup: stack, copy `.data` out of ROM, clear `.bss`, call `main` |
| `blink.s` | First bring-up program: button toggles the LED (polling, no debounce) |
| `app_blink.s` | Same idea, debounced, and meant to be loaded by the bootloader |
| `matrix.s` | 8x8 matrix refresh by busy-waiting |
| `matrix_irq.s` | Matrix refresh from a timer interrupt; the main loop handles a button that inverts the picture |
| `boot.s`, `boot_main.c` | Bootloader: verifies the app image, then jumps to it |
| `cputest.s`, `traptest.s` | Self-checking tests for the base ISA and for CSRs/traps/interrupts |

## Memory map

| Address | Device |
|---|---|
| `0x0000_0000` | ROM, 8 KB (bootloader in the first 4 KB, application image from `0x1000`) |
| `0x1000_0000` | RAM, 4 KB (first 16 bytes double as a mailbox for the self-tests) |
| `0x4000_0000` | GPIO: `DATA` +0, `DIR` +4, `SET` +8, `CLR` +C. Bit 0 button, bit 1 LED, bit 2 fault LED |
| `0x4000_1000` | LED matrix: `ROW` +0 (one-hot), `COL` +4 |
| `0x4000_2000` | Timer: `MTIME` +0 (counts clocks), `MTIMECMP` +4. Interrupt while `signed(mtime - mtimecmp) >= 0` |

## Building and running

You need `iverilog`, `verilator`, `yosys`, `nextpnr-ecp5`, `fpga-trellis` (for `ecppack`), a RISC-V binutils + gcc (`riscv64-unknown-elf-`), and Python 3. Flashing also needs `openFPGALoader`.

```
make sim          # build every firmware image and run all eight simulations
make lint         # Verilator lint
make synth        # generic Yosys synthesis of the core
make check        # all of the above
make fpga         # ULX3S bitstream (build/fpga.bit), fails if timing isn't met
make boardsim     # board-level test of fpga_top on the RTL
make gatesim      # simulate the synthesized netlist (see "Verification")
make flash        # load the bitstream onto a connected ULX3S
make release      # bitstream signed with your own key (see "Deploying")
make disasm       # disassemble the firmware
```

On Debian/Ubuntu:

```
sudo apt-get install iverilog verilator yosys nextpnr-ecp5 fpga-trellis \
    gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
```

`make sim` runs: `blink`, `matrix`, `cputest`, `traptest`, `matrix_irq`, `boot_ok`, `boot_bad`,
`boot_forged`. It exits non-zero if any of them fails, so it works in CI.

## How the bootloader decides

The application image starts with a 40-byte header: a magic number, the payload length, and an
HMAC-SHA256 of the magic, length and payload. `boot_main.c` recomputes the MAC with the key
baked into the bootloader and compares it in constant time. If it matches, it jumps to
`0x1028`. If not, it lights the fault LED and stops.

Three of the tests cover this: a properly signed image boots, an image changed after signing is
rejected, and an image signed with a different key is rejected. The third one is the case a plain
checksum would have let through.

`tools/dev.key` and `tools/attacker.key` are throwaway keys, committed so the tests run out of the
box. For anything real, generate your own key, keep it out of the repository, and rebuild.

Worth knowing about the scheme: HMAC uses a shared secret, and here that secret sits in ROM. It
protects against someone swapping the application without access to the ROM, but not against
someone who can read the ROM out. A real product would use a public-key signature (Ed25519, for
instance) or keep the key somewhere protected. There is also no version check, so an old signed
image can be loaded again.

## Debounce timing

`app_blink.s` samples the button every `SAMPLE_CYCLES` clocks and needs eight agreeing samples
before it counts a press, so debounce time is `8 * SAMPLE_CYCLES / f_clk`. The simulation uses 20.
For a 50 MHz board and about 8 ms:

```
make APP_DEFS="--defsym SAMPLE_CYCLES=50000"
```

Tune it to your switch.

## Deploying to a ULX3S

The reference board is the ULX3S with the ECP5-25F (25 MHz oscillator). The pin file in
`fpga/ulx3s.lpf` is the relevant part of the board maker's official constraints.

| Board | Function |
|---|---|
| `FIRE1` button | the application's button (active high) |
| `FIRE2` button | hold to reset the CPU |
| `LED0` | application LED |
| `LED1` | fault LED: the bootloader rejected the image |
| `LED2` | on while the CPU is running |
| `GP0`-`GP7` | LED matrix rows (outputs) |
| `GP8`-`GP15` | LED matrix columns (outputs) |

The matrix pins are 3.3 V logic straight from the FPGA. Put current-limiting resistors or a driver
stage between them and any real matrix, and check its polarity against the firmware.

**Try it with the demo key** (this is signed with the throwaway key in `tools/`):

```
make fpga
make flash          # openFPGALoader -b ulx3s build/fpga.bit  (RAM only; gone at power-off)
```

Press FIRE1: LED0 toggles once per press. To store it in the board's flash instead, run
`openFPGALoader -b ulx3s -f build/fpga.bit`.

**Make your own release**, signed with a key nobody else has:

```
make newkey                          # writes keys/release.key (git-ignored; back it up)
make release KEY=keys/release.key    # bitstream in build/release/fpga.bit
```

The release build refuses the demo key. It bakes the key into the bootloader, signs the
application with it, and sets the debounce and matrix timing for a 25 MHz clock (1 ms sample,
8 ms debounce; 1 kHz matrix refresh). `APP=matrix_irq` builds the matrix demo as the application
instead of the button/LED one.

Using a different board means a new top level (clock, reset, pins) and constraint file, and
changing `FPGA_ARGS` in the Makefile.

Resource use on the ECP5-25F: about 4,500 of 24,000 LUTs (18%), 470 flip-flops, 8 of 56 block RAMs.
Timing closes at about 32 MHz against the 25 MHz clock.

## Verification

- Eight simulations of the SoC (`make sim`) pass: `blink`, `matrix`, `cputest`, `traptest`,
  `matrix_irq`, `boot_ok`, `boot_bad`, `boot_forged`.
- A board-level test (`tb/tb_fpga.sv`) drives `fpga_top` the way the board does: power-on reset,
  HMAC check of the signed image, then button presses toggling the LED. It passes on the RTL.
- `make gatesim` runs the same test on the synthesized ECP5 netlist. Yosys has no simulation
  model for ECP5 block RAM, so for that run the memories are turned into plain logic and
  shrunk, and the polling `blink` image is used instead of the signed one. It checks the CPU,
  bus, peripherals, reset and button path as synthesized. It does not check the block RAM
  mapping, which relies on Yosys and nextpnr. `make gatesim-boot` runs the signed image through
  the same netlist but takes much longer.
- Verilator lint is clean, and `make fpga` (nextpnr) reports timing met.

**Not done:** I haven't run it on a physical board, so the pin assignments and the matrix
behavior are untested on real hardware. The first thing to try on a board is the demo flow above.

## Limits

- Machine mode only. No compressed (C) or multiply/divide (M) extensions, no vectored
  interrupts, 32-bit counters, and WFI doesn't actually sleep.
- No anti-rollback for the bootloader, see above.
- Secure boot only checks the application. The bootloader itself lives in the bitstream, so anyone
  who can reprogram the FPGA can replace it.
- The register layouts are this project's own, not any vendor's.

## Layout

```
rtl/    SystemVerilog sources (fpga_top.sv is the board top level)
fw/     firmware and linker scripts
fpga/   board pin constraints
tools/  image signing and helper scripts
tb/     testbenches
```

## License

MIT, see [LICENSE](LICENSE).

# rv32i-soc

A small RV32I processor in SystemVerilog, plus the bare-metal firmware that runs on it: a
bootloader that checks the application before running it, a button/LED program, and an 8x8 LED
matrix driver. Everything runs in simulation with open-source tools. It was built as a way to
see the whole stack at once, from the instruction decoder up to a button press toggling an LED.

It has not been run on real hardware yet. The peripherals (GPIO, LED matrix, timer) have
register layouts I made up for this project, so expect to adjust them for an actual board.

## What's in it

**The core** is single-cycle: one instruction per clock, no pipeline. It implements all of RV32I
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

You need `iverilog`, `verilator`, `yosys`, a RISC-V binutils + gcc (`riscv64-unknown-elf-`), and Python 3.

```
make sim      # build every firmware image and run all eight simulations
make lint     # Verilator lint
make synth    # generic Yosys synthesis of the core
make check    # all of the above
make disasm   # disassemble the firmware
```

On Debian/Ubuntu:

```
sudo apt-get install iverilog verilator yosys gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
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

`tools/dev.key` is a throwaway key for the simulation. Generate your own before using this for
anything real, and don't commit it.

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

## Where things stand

- All eight simulations pass.
- Verilator lint is clean.
- Yosys synthesizes the core with no warnings from its checks and no inferred latches
  (about 8,100 generic cells, mostly the register file). The full SoC isn't synthesized because
  the simulation memories load from a file.
- Not done: place-and-route, timing, a run on a real board.

## Limits

- Machine mode only. No compressed (C) or multiply/divide (M) extensions, no vectored
  interrupts, 32-bit counters, and WFI doesn't actually sleep.
- No anti-rollback for the bootloader, see above.
- The register layouts are this project's own, not any vendor's.

## Layout

```
rtl/    SystemVerilog sources
fw/     firmware and linker scripts
tools/  image signing and helper scripts
tb/     testbench
```

## License

MIT, see [LICENSE](LICENSE).

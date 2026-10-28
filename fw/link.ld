OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 4K
}
/* First 16 bytes of RAM are a test mailbox (used by cputest). */
SECTIONS
{
  .text : { KEEP(*(.text.start)) *(.text*) } > ROM
  .rodata : { *(.rodata*) . = ALIGN(4); } > ROM
  .data ORIGIN(RAM) + 16 : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > ROM
  _sidata = LOADADDR(.data);
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

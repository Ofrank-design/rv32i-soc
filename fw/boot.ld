OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4K }
SECTIONS
{
  .text : { KEEP(*(.text.start)) *(.text*) } > ROM
  .rodata : { *(.rodata*) *(.srodata*) . = ALIGN(4); } > ROM
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.data*) *(.bss*) *(.sdata*) *(.sbss*) }
}

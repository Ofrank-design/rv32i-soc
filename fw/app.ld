OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY
{
  ROM (rx)  : ORIGIN = 0x00001000, LENGTH = 4K
  RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 4K
}
SECTIONS
{
  /* 40-byte header: magic, length, HMAC-SHA256 (patched by tools/mkimage.py) */
  .header : { LONG(0xB007AB1E) LONG(0) . = . + 32; } > ROM
  .text : { KEEP(*(.text.start)) *(.text*) } > ROM
  .rodata : { *(.rodata*) . = ALIGN(4); } > ROM
  .data ORIGIN(RAM) + 16 : { _sdata = .; *(.data*) . = ALIGN(4); _edata = .; } > RAM AT > ROM
  _sidata = LOADADDR(.data);
  .bss (NOLOAD) : { _sbss = .; *(.bss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

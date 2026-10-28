# Startup code: set the stack pointer, copy .data from ROM to RAM, zero .bss, call main.
    .section .text.start
    .globl _start
_start:
    la      sp, _stack_top
    la      t0, _sidata
    la      t1, _sdata
    la      t2, _edata
1:  bgeu    t1, t2, 2f
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       1b
2:  la      t0, _sbss
    la      t1, _ebss
3:  bgeu    t0, t1, 4f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       3b
4:  jal     ra, main
5:  j       5b

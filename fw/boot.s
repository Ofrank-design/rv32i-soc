# Stage-0 entry point. Sets up the fault LED pin and a stack, asks boot_main.c whether the
# application image checks out, and jumps to it if so. If not, it lights the fault LED
# (GPIO bit 2) and stops.
    .section .text.start
    .globl _start
_start:
    lui     t0, 0x40000
    lw      t1, 4(t0)
    ori     t1, t1, 0x4          # bit2 (fault LED) output; the app configures bit1
    sw      t1, 4(t0)
    lui     sp, 0x10001          # stack top = 0x10001000
    jal     ra, boot_main        # a0 = entry address or 0
    beq     a0, zero, bad
    jalr    zero, 0(a0)
bad:
    lui     t0, 0x40000
    addi    t1, zero, 4
    sw      t1, 8(t0)            # GPIO_SET bit2
halt:
    j       halt

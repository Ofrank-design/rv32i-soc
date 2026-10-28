# Simple 8x8 LED matrix refresh, done by busy-waiting. Matrix at 0x40001000: ROW (one-hot
# select) and COL (pixel data). See matrix_irq.s for the timer-driven version.
    .section .data
    .align 2
led_frame:
    .byte 0x18, 0x3C, 0x7E, 0xDB, 0xFF, 0x24, 0x5A, 0x81

    .section .text
    .globl main
main:
    lui     s0, 0x40001
    la      s1, led_frame
refresh:
    addi    s2, zero, 0          # row index
    addi    s3, zero, 1          # row select mask
    addi    s4, zero, 8
row_loop:
    sw      zero, 4(s0)          # blank columns (avoid ghosting)
    sw      s3, 0(s0)            # select row
    add     t0, s1, s2
    lbu     t1, 0(t0)
    sw      t1, 4(s0)            # drive columns
    addi    t2, zero, 20
dwell:
    addi    t2, t2, -1
    bne     t2, zero, dwell
    slli    s3, s3, 1
    addi    s2, s2, 1
    bne     s2, s4, row_loop
    sw      zero, 4(s0)
    j       refresh

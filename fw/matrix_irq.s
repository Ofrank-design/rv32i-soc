# Matrix refresh driven by the timer interrupt: each tick the ISR shows one row, so the main
# loop is free to watch the (debounced) button, which inverts the picture.
# Matrix at 0x40001000, timer at 0x40002000.
    .ifndef TICK
    .equ TICK, 100
    .endif
    .ifndef SAMPLE_CYCLES
    .equ SAMPLE_CYCLES, 20
    .endif

    .section .data
    .align 2
led_frame:
    .byte 0x18, 0x3C, 0x7E, 0xDB, 0xFF, 0x24, 0x5A, 0x81

    .section .bss
    .align 2
save_area: .space 16
row_idx:   .space 4
invert:    .space 4

    .section .text
    .globl main
main:
    la      t0, isr
    csrw    mtvec, t0
    la      t0, save_area
    csrw    mscratch, t0
    lui     t1, 0x40002
    lw      t2, 0(t1)
    addi    t2, t2, TICK
    sw      t2, 4(t1)                # first tick
    li      t0, 0x80
    csrw    mie, t0
    csrsi   mstatus, 8               # global interrupt enable

    # debounced button (bit0 of GPIO) -> toggle 'invert'
    lui     s0, 0x40000
    la      s6, invert
    lui     s4, 0x40002
    lw      s5, 0(s4)
    li      s7, SAMPLE_CYCLES
    li      s1, 0                    # integrator
    li      s2, 0                    # press handled
    li      s3, 8                    # threshold
loop:
    lw      t2, 0(s4)
    sub     t2, t2, s5
    bltu    t2, s7, loop
    add     s5, s5, s7
    lw      t1, 0(s0)
    andi    t1, t1, 1
    beq     t1, zero, dec
    bge     s1, s3, chk
    addi    s1, s1, 1
    j       chk
dec:
    beq     s1, zero, chk
    addi    s1, s1, -1
chk:
    bne     s1, s3, notfull
    bne     s2, zero, loop
    li      s2, 1
    lw      t1, 0(s6)
    xori    t1, t1, 1
    sw      t1, 0(s6)
    j       loop
notfull:
    bne     s1, zero, loop
    li      s2, 0
    j       loop

    .align 2
isr:
    csrrw   t6, mscratch, t6
    sw      t0, 0(t6)
    sw      t1, 4(t6)
    sw      t2, 8(t6)
    sw      t3, 12(t6)
    lui     t0, 0x40001
    sw      zero, 4(t0)              # blank columns
    la      t1, row_idx
    lw      t2, 0(t1)
    addi    t2, t2, 1
    andi    t2, t2, 7
    sw      t2, 0(t1)
    li      t3, 1
    sll     t3, t3, t2
    sw      t3, 0(t0)                # select row
    la      t1, led_frame
    add     t1, t1, t2
    lbu     t1, 0(t1)
    la      t2, invert
    lw      t2, 0(t2)
    beq     t2, zero, 1f
    xori    t1, t1, 0xFF
1:  sw      t1, 4(t0)                # drive columns
    lui     t0, 0x40002              # schedule next tick: mtimecmp += TICK
    lw      t1, 4(t0)
    addi    t1, t1, TICK
    sw      t1, 4(t0)
    lw      t0, 0(t6)
    lw      t1, 4(t6)
    lw      t2, 8(t6)
    lw      t3, 12(t6)
    csrrw   t6, mscratch, t6
    mret

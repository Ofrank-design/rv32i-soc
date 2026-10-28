# Button toggles the LED, once per press, with debouncing.
# The button is sampled every SAMPLE_CYCLES clocks (timed off MTIME). An up/down counter has to
# reach 8 before a press counts, so debounce time = 8 * SAMPLE_CYCLES / f_clk.
# Hardware example: 50 MHz clock, SAMPLE_CYCLES=50000 (1 ms) -> 8 ms debounce
#   (build with: make APP_DEFS="--defsym SAMPLE_CYCLES=50000").
    .ifndef SAMPLE_CYCLES
    .equ SAMPLE_CYCLES, 20          # fast value used in simulation
    .endif
    .section .text
    .globl main
main:
    lui     t0, 0x40000
    lw      t1, 4(t0)
    ori     t1, t1, 0x2
    sw      t1, 4(t0)
    lui     s4, 0x40002              # timer: MTIME at +0
    lw      s5, 0(s4)                # next sample deadline base
    li      s7, SAMPLE_CYCLES
    li      s1, 0                    # integrator
    li      s2, 0                    # 1 = press already handled
    li      s3, 8                    # threshold N
loop:
    lw      t2, 0(s4)
    sub     t2, t2, s5
    bltu    t2, s7, loop             # wait for the next sample slot
    add     s5, s5, s7
    lw      t1, 0(t0)
    andi    t1, t1, 1
    beq     t1, zero, dec
    bge     s1, s3, chk              # saturate at N
    addi    s1, s1, 1
    j       chk
dec:
    beq     s1, zero, chk
    addi    s1, s1, -1
chk:
    bne     s1, s3, notfull
    bne     s2, zero, loop           # still held, already toggled
    li      s2, 1
    lw      t1, 0(t0)
    xori    t1, t1, 0x2              # toggle LED
    sw      t1, 0(t0)
    j       loop
notfull:
    bne     s1, zero, loop
    li      s2, 0                    # fully released: re-arm
    j       loop

# First bring-up program: press the button, the LED toggles.
# GPIO at 0x40000000, bit 0 = button, bit 1 = LED. Plain polling, no debounce; app_blink.s
# is the version to use with a real switch.
    .section .text
    .globl main
main:
    lui     t0, 0x40000
    lw      t1, 4(t0)
    ori     t1, t1, 0x2          # bit1 output
    sw      t1, 4(t0)
main_loop:
    lw      t1, 0(t0)
    andi    t2, t1, 0x1
    beq     t2, zero, main_loop  # wait for press
    lw      t1, 0(t0)
    xori    t1, t1, 0x2          # toggle LED
    sw      t1, 0(t0)
    addi    t3, zero, 100
delay_loop:
    addi    t3, t3, -1
    bne     t3, zero, delay_loop
wait_release:
    lw      t1, 0(t0)
    andi    t2, t1, 0x1
    bne     t2, zero, wait_release
    jal     zero, main_loop

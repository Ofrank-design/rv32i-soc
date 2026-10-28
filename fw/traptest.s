# Self-checking test for CSRs, exceptions and the timer interrupt. Same convention as
# cputest.s: 0x600D600D at 0x10000000 means pass, 0xBAD00000 | id means check `id` failed.
    .macro CHECK reg, val, id
    li      t6, \val
    li      a0, \id
    bne     \reg, t6, fail
    .endm
    .macro CHECKVAR var, val, id
    la      t0, \var
    lw      t1, 0(t0)
    CHECK   t1, \val, \id
    .endm

    .section .bss
    .align 2
save_area:   .space 16
last_cause:  .space 4
last_tval:   .space 4
trap_count:  .space 4
irq_count:   .space 4

    .section .text
    .globl main
main:
    la      t0, trap_handler
    csrw    mtvec, t0
    la      t0, save_area
    csrw    mscratch, t0

    # ---- CSR read/write/set/clear (mtval used as scratch CSR) ----
    li t0, 0xAA55
    csrw mtval, t0
    csrr t1, mtval
    CHECK t1, 0xAA55, 1
    li t0, 0xFF
    csrrs t1, mtval, t0
    CHECK t1, 0xAA55, 2
    csrr t2, mtval
    CHECK t2, 0xAAFF, 3
    li t0, 0x0F
    csrrc t1, mtval, t0
    CHECK t1, 0xAAFF, 4
    csrr t2, mtval
    CHECK t2, 0xAAF0, 5
    csrrwi t1, mtval, 7
    CHECK t1, 0xAAF0, 6
    csrr t2, mtval
    CHECK t2, 7, 7
    csrrsi t1, mtval, 8
    csrr t2, mtval
    CHECK t2, 0xF, 8
    csrrci t1, mtval, 3
    csrr t2, mtval
    CHECK t2, 0xC, 9
    csrr t1, misa
    CHECK t1, 0x40000100, 10
    csrr t1, mhartid
    CHECK t1, 0, 11

    # ---- ECALL ----
    ecall
    CHECKVAR last_cause, 11, 12
    CHECKVAR trap_count, 1, 13

    # ---- EBREAK ----
    ebreak
    CHECKVAR last_cause, 3, 14

    # ---- illegal instruction (mtval = instruction word) ----
    .word 0xFFFFFFFF
    CHECKVAR last_cause, 2, 15
    CHECKVAR last_tval, 0xFFFFFFFF, 16
    # illegal funct7 on OP: add with funct7=0x10
    .word 0x201080B3
    CHECKVAR last_cause, 2, 17
    CHECKVAR last_tval, 0x201080B3, 18

    # ---- misaligned load: no side effects on rd ----
    li t1, 0x55
    li t0, 0x10000101
    lw t1, 0(t0)
    CHECK t1, 0x55, 19
    CHECKVAR last_cause, 4, 20
    CHECKVAR last_tval, 0x10000101, 21
    li t0, 0x10000103
    lh t1, 0(t0)
    CHECKVAR last_cause, 4, 22

    # ---- misaligned store: memory unchanged ----
    li t0, 0x10000100
    li t1, 0x12345678
    sw t1, 0(t0)
    li t0, 0x10000102
    li t2, 0xDEADBEEF
    sw t2, 0(t0)
    CHECKVAR last_cause, 6, 23
    li t0, 0x10000100
    lw t1, 0(t0)
    CHECK t1, 0x12345678, 24

    # ---- misaligned jump target (mtval = target) ----
    la t0, mj
    addi t0, t0, 2
    jalr zero, 0(t0)
mj: CHECKVAR last_cause, 0, 25

    # ---- trapping CSR write has no effect: illegal SYSTEM encoding ----
    li t1, 0
    .word 0x10500073                 # WFI executes as a NOP (no trap)
    CHECKVAR trap_count, 8, 26
    .word 0x00200073                 # unsupported SYSTEM encoding -> illegal
    CHECKVAR last_cause, 2, 32

    # ---- MRET restores MIE from MPIE ----
    csrr t1, mstatus
    andi t1, t1, 0x8
    CHECK t1, 0, 27                  # MIE is 0 after reset/traps

    # ---- machine timer interrupt ----
    lui t1, 0x40002
    lw t2, 0(t1)
    addi t2, t2, 200
    sw t2, 4(t1)                     # mtimecmp = mtime + 200
    li t0, 0x80
    csrw mie, t0
    csrr t3, mie
    CHECK t3, 0x80, 28
    csrsi mstatus, 8                 # enable MIE
    la t3, irq_count
wait_irq:
    lw t4, 0(t3)
    beq t4, zero, wait_irq
    csrci mstatus, 8
    CHECK t4, 1, 29
    CHECKVAR last_cause, 0x80000007, 30
    # interrupt returns to the interrupted instruction stream; no second IRQ after disarm
    li t0, 0
    li t1, 400
spin: addi t0, t0, 1
    bne t0, t1, spin
    CHECKVAR irq_count, 1, 31

    li t0, 0x600D600D
    li t1, 0x10000000
    sw t0, 0(t1)
done:
    j done

fail:
    li t1, 0xBAD00000
    or t1, t1, a0
    li t2, 0x10000000
    sw t1, 0(t2)
fail_loop:
    j fail_loop

# ---- trap handler: preserves all registers (t6 swapped with mscratch) ----
    .align 2
trap_handler:
    csrrw t6, mscratch, t6
    sw t0, 0(t6)
    sw t1, 4(t6)
    sw t2, 8(t6)
    csrr t0, mcause
    la t1, last_cause
    sw t0, 0(t1)
    csrr t2, mtval
    la t1, last_tval
    sw t2, 0(t1)
    la t1, trap_count
    lw t2, 0(t1)
    addi t2, t2, 1
    sw t2, 0(t1)
    bgez t0, sync_exc
    lui t1, 0x40002                  # timer IRQ: disarm (mtimecmp far in future)
    li t2, 0x7FFFFFFF
    sw t2, 4(t1)
    la t1, irq_count
    lw t2, 0(t1)
    addi t2, t2, 1
    sw t2, 0(t1)
    j restore
sync_exc:
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
restore:
    lw t0, 0(t6)
    lw t1, 4(t6)
    lw t2, 8(t6)
    csrrw t6, mscratch, t6
    mret

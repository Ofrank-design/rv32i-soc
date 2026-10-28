# Self-checking test for the base ISA. Each CHECK compares a result with the expected value.
# On success the word at 0x10000000 becomes 0x600D600D; on failure it becomes 0xBAD00000 | id,
# where id is the number of the failing check.
    .macro CHECK reg, val, id
    li      t6, \val
    li      a0, \id
    bne     \reg, t6, fail
    .endm

    .section .text
    .globl main
main:
    li t0, 5
    li t1, 7
    add t2, t0, t1
    CHECK t2, 12, 1
    sub t2, t0, t1
    CHECK t2, -2, 2
    li t3, 0xF0F0F0F0
    li t4, 0x0FF00FF0
    and t2, t3, t4
    CHECK t2, 0x00F000F0, 3
    or  t2, t3, t4
    CHECK t2, 0xFFF0FFF0, 4
    xor t2, t3, t4
    CHECK t2, 0xFF00FF00, 5
    li t0, 1
    li t1, 4
    sll t2, t0, t1
    CHECK t2, 16, 6
    li t3, 0x80000000
    srl t2, t3, t1
    CHECK t2, 0x08000000, 7
    sra t2, t3, t1
    CHECK t2, 0xF8000000, 8
    li t0, -1
    li t1, 1
    slt t2, t0, t1
    CHECK t2, 1, 9
    sltu t2, t0, t1
    CHECK t2, 0, 10
    slti t2, t0, 0
    CHECK t2, 1, 11
    sltiu t2, t0, 0
    CHECK t2, 0, 12
    xori t2, t1, 3
    CHECK t2, 2, 13
    ori t2, t1, 6
    CHECK t2, 7, 14
    andi t2, t1, 3
    CHECK t2, 1, 15
    slli t2, t1, 5
    CHECK t2, 32, 16
    srli t2, t3, 31
    CHECK t2, 1, 17
    srai t2, t3, 31
    CHECK t2, -1, 18
    lui t2, 0x12345
    CHECK t2, 0x12345000, 19
    addi zero, zero, 5
    CHECK zero, 0, 20

    li a0, 21
auipc_t:
    auipc t2, 0
    la t3, auipc_t
    bne t2, t3, fail

    # branches
    li a0, 22
    li t0, 3
    li t1, 3
    beq t0, t1, 1f
    j fail
1:  li a0, 23
    bne t0, t1, fail
    li a0, 24
    li t1, 4
    bne t0, t1, 2f
    j fail
2:  li a0, 25
    blt t0, t1, 3f
    j fail
3:  li a0, 26
    bge t0, t1, fail
    li a0, 27
    bge t1, t0, 4f
    j fail
4:  li a0, 28
    li t2, -1
    blt t2, t0, 5f
    j fail
5:  li a0, 29
    bltu t2, t0, fail
    li a0, 30
    bgeu t2, t0, 6f
    j fail
6:  li a0, 31
    bltu t0, t2, 7f
    j fail
7:  li t0, 0
    li t1, 5
loop:
    addi t0, t0, 1
    bne t0, t1, loop
    CHECK t0, 5, 32

    # jumps
    li a0, 33
    jal t0, jt
    j fail
jt: la t1, jt
    addi t1, t1, -4
    bne t0, t1, fail
    li a0, 34
    la t2, jr_t
    jalr t3, 0(t2)
    j fail
jr_t:
    la t4, jr_t
    addi t4, t4, -4
    bne t3, t4, fail
    li a0, 35
    la t2, jr2
    addi t2, t2, 1          # bit0 must be cleared by JALR
    jalr zero, 0(t2)
    j fail
jr2:

    # memory
    li s0, 0x10000100
    li t0, 0x11223344
    sw t0, 0(s0)
    lw t1, 0(s0)
    CHECK t1, 0x11223344, 36
    lbu t1, 0(s0)
    CHECK t1, 0x44, 37
    lbu t1, 3(s0)
    CHECK t1, 0x11, 38
    lb t1, 1(s0)
    CHECK t1, 0x33, 39
    lhu t1, 2(s0)
    CHECK t1, 0x1122, 40
    li t0, 0x80FF7F80
    sw t0, 0(s0)
    lb t1, 0(s0)
    CHECK t1, 0xFFFFFF80, 41
    lb t1, 1(s0)
    CHECK t1, 0x7F, 42
    lb t1, 2(s0)
    CHECK t1, 0xFFFFFFFF, 43
    lh t1, 0(s0)
    CHECK t1, 0x7F80, 44
    lh t1, 2(s0)
    CHECK t1, 0xFFFF80FF, 45
    lhu t1, 2(s0)
    CHECK t1, 0x80FF, 46
    li t0, 0xAB
    sb t0, 1(s0)
    lw t1, 0(s0)
    CHECK t1, 0x80FFAB80, 47
    li t0, 0x1234
    sh t0, 2(s0)
    lw t1, 0(s0)
    CHECK t1, 0x1234AB80, 48
    addi s1, s0, 8
    li t0, 0xCAFEF00D
    sw t0, 0(s1)
    lw t1, 0(s1)
    CHECK t1, 0xCAFEF00D, 49

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

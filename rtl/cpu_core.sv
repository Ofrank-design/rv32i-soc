// Single-cycle RV32I core: one instruction per clock, no pipeline, except that loads take two.
//
// Block RAM returns data a clock after the address, so instruction memory is addressed with the
// *next* PC (imem_addr = pc_next) and its output register holds the current instruction. A load
// takes an extra cycle: cycle one presents the address and holds the PC, cycle two (load_wait)
// uses the data that came back and finishes the instruction.
//
// Besides the base ISA it has machine-mode CSRs, a handful of synchronous exceptions
// (illegal instruction, EBREAK, ECALL, misaligned jump/load/store) and a timer interrupt.
// An instruction that traps does nothing else: no register write, no store, no CSR update.
// That keeps the handler's view of the machine simple (mepc just points at the culprit).
module cpu_core #(parameter [31:0] RESET_PC = 32'h0) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        timer_irq,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_data,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    output logic        dmem_re,
    input  logic [31:0] dmem_rdata
);
`include "rv_defs.svh"

    logic [31:0] pc, pc_next, pc_plus4;
    logic        load_wait, stall;
    assign imem_addr = rst_n ? pc_next : RESET_PC;   // fetch address for the NEXT instruction
    assign pc_plus4  = pc + 32'd4;

    // ---- decode ----
    logic [6:0] opcode, funct7; logic [2:0] funct3; logic [4:0] rs1, rs2, rd;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    instr_decoder u_dec (.instr(imem_data), .opcode, .funct3, .funct7, .rs1, .rs2, .rd,
                         .imm_i, .imm_s, .imm_b, .imm_u, .imm_j);

    logic reg_write, alu_a_pc, alu_b_imm, mem_read, mem_write, branch, jal, jalr, is_system, ctl_illegal;
    logic [2:0] imm_sel; logic [3:0] alu_op; logic [1:0] wb_sel;
    control u_ctl (.opcode, .funct3, .funct7, .reg_write, .alu_a_pc, .alu_b_imm,
                   .imm_sel, .alu_op, .mem_read, .mem_write, .branch, .jal, .jalr, .wb_sel,
                   .is_system, .illegal(ctl_illegal));

    // ---- SYSTEM decode ----
    wire        is_csr    = is_system && funct3 != 3'b000 && funct3 != 3'b100;
    wire        is_ecall  = is_system && imem_data == 32'h00000073;
    wire        is_ebreak = is_system && imem_data == 32'h00100073;
    wire        is_mret   = is_system && imem_data == 32'h30200073;
    wire        is_wfi    = is_system && imem_data == 32'h10500073;   // executed as NOP
    wire        sys_illegal = is_system && !(is_csr || is_ecall || is_ebreak || is_mret || is_wfi);
    wire        illegal   = ctl_illegal || sys_illegal;

    // ---- register file ----
    logic [31:0] rs1_data, rs2_data, wb_data, csr_rdata;
    logic        trap, reg_we;
    assign stall  = mem_read && !trap && !load_wait;   // first cycle of a load: address out, no commit
    assign reg_we = (reg_write || is_csr) && !trap && !stall;
    regfile u_rf (.clk, .we(reg_we), .ra1(rs1), .ra2(rs2), .wa(rd), .wd(wb_data),
                  .rd1(rs1_data), .rd2(rs2_data));

    // ---- execute ----
    logic [31:0] imm, alu_a, alu_b, alu_y;
    always_comb begin
        case (imm_sel)
            IMM_S:   imm = imm_s;
            IMM_B:   imm = imm_b;
            IMM_U:   imm = imm_u;
            IMM_J:   imm = imm_j;
            default: imm = imm_i;
        endcase
    end
    assign alu_a = alu_a_pc  ? pc  : rs1_data;
    assign alu_b = alu_b_imm ? imm : rs2_data;
    alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .y(alu_y));

    // ---- branch / jump targets ----
    logic eq, lt, ltu, cond;
    assign eq  = (rs1_data == rs2_data);
    assign lt  = ($signed(rs1_data) < $signed(rs2_data));
    assign ltu = (rs1_data < rs2_data);
    always_comb begin
        case (funct3)
            3'b000:  cond = eq;
            3'b001:  cond = ~eq;
            3'b100:  cond = lt;
            3'b101:  cond = ~lt;
            3'b110:  cond = ltu;
            3'b111:  cond = ~ltu;
            default: cond = 1'b0;
        endcase
    end
    wire [31:0] jal_tgt  = pc + imm_j;
    wire [31:0] br_tgt   = pc + imm_b;
    wire [31:0] jalr_tgt = {alu_y[31:1], 1'b0};
    wire        take_br  = branch && cond;
    wire [31:0] tgt      = jal ? jal_tgt : (jalr ? jalr_tgt : br_tgt);
    wire        tgt_misal = (jal || jalr || take_br) && tgt[1];

    // ---- memory ----
    assign dmem_addr = alu_y;
    assign dmem_re   = mem_read && !trap;
    always_comb begin
        case (funct3[1:0])
            2'b00:   begin dmem_wdata = {4{rs2_data[7:0]}};  dmem_wstrb = 4'b0001 << dmem_addr[1:0]; end
            2'b01:   begin dmem_wdata = {2{rs2_data[15:0]}}; dmem_wstrb = dmem_addr[1] ? 4'b1100 : 4'b0011; end
            default: begin dmem_wdata = rs2_data;            dmem_wstrb = 4'b1111; end
        endcase
        if (!mem_write || trap) dmem_wstrb = 4'b0000;
    end
    wire ld_misal = mem_read  && ((funct3[1:0] == 2'b10 && alu_y[1:0] != 2'b00) ||
                                  (funct3[1:0] == 2'b01 && alu_y[0]));
    wire st_misal = mem_write && ((funct3[1:0] == 2'b10 && alu_y[1:0] != 2'b00) ||
                                  (funct3[1:0] == 2'b01 && alu_y[0]));

    logic [31:0] shifted, load_data;
    assign shifted = dmem_rdata >> {dmem_addr[1:0], 3'b000};
    always_comb begin
        case (funct3)
            3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};
            3'b100:  load_data = {24'b0, shifted[7:0]};
            3'b101:  load_data = {16'b0, shifted[15:0]};
            default: load_data = dmem_rdata;
        endcase
    end

    // ---- traps ----
    logic        exc, irq_pending;
    logic [31:0] exc_cause, exc_val, trap_cause, trap_val, mtvec, mepc;
    always_comb begin
        exc = 1'b1; exc_cause = 32'd0; exc_val = 32'd0;
        if      (illegal)    begin exc_cause = 32'd2;  exc_val = imem_data; end
        else if (is_ebreak)  begin exc_cause = 32'd3;  end
        else if (is_ecall)   begin exc_cause = 32'd11; end
        else if (tgt_misal)  begin exc_cause = 32'd0;  exc_val = tgt; end
        else if (ld_misal)   begin exc_cause = 32'd4;  exc_val = alu_y; end
        else if (st_misal)   begin exc_cause = 32'd6;  exc_val = alu_y; end
        else                 begin exc = 1'b0; end
    end
    assign trap       = irq_pending || exc;
    assign trap_cause = irq_pending ? 32'h80000007 : exc_cause;
    assign trap_val   = irq_pending ? 32'd0 : exc_val;

    // ---- CSR file ----
    wire [31:0] csr_src = funct3[2] ? {27'b0, rs1} : rs1_data;
    wire        csr_wen = is_csr && !trap && (funct3[1:0] == 2'b01 || rs1 != 5'd0);
    csr_file u_csr (.clk, .rst_n, .addr(imem_data[31:20]), .wdata(csr_src), .op(funct3[1:0]),
                    .wen(csr_wen), .rdata(csr_rdata),
                    .trap_enter(trap), .trap_cause, .trap_pc(pc), .trap_val,
                    .mret_en(is_mret && !trap), .retire(!trap && !stall), .timer_irq,
                    .mtvec_o(mtvec), .mepc_o(mepc), .irq_pending);

    // ---- next PC ----
    always_comb begin
        if (trap)                   pc_next = mtvec;
        else if (stall)             pc_next = pc;
        else if (is_mret)           pc_next = mepc;
        else if (jal)               pc_next = jal_tgt;
        else if (jalr)              pc_next = jalr_tgt;
        else if (take_br)           pc_next = br_tgt;
        else                        pc_next = pc_plus4;
    end
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin pc <= RESET_PC; load_wait <= 1'b0; end
        else        begin pc <= pc_next;  load_wait <= stall;  end

    // ---- write-back ----
    always_comb begin
        if (is_csr)          wb_data = csr_rdata;
        else case (wb_sel)
            2'd1:    wb_data = load_data;
            2'd2:    wb_data = pc_plus4;
            default: wb_data = alu_y;
        endcase
    end
endmodule

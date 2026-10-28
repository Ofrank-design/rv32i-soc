// Control unit. Looks at opcode/funct3/funct7 and decides what the datapath should do this
// cycle. It also flags encodings the core doesn't implement so the core can raise a trap.
module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic       reg_write,
    output logic       alu_a_pc,
    output logic       alu_b_imm,
    output logic [2:0] imm_sel,
    output logic [3:0] alu_op,
    output logic       mem_read,
    output logic       mem_write,
    output logic       branch,
    output logic       jal,
    output logic       jalr,
    output logic [1:0] wb_sel,       // 0 ALU, 1 memory, 2 PC+4
    output logic       is_system,
    output logic       illegal
);
`include "rv_defs.svh"

    wire f7_5 = funct7[5];
    logic [3:0] arith_op;
    always_comb begin
        case (funct3)
            3'b000:  arith_op = (opcode == OP_REG && f7_5) ? ALU_SUB : ALU_ADD;
            3'b001:  arith_op = ALU_SLL;
            3'b010:  arith_op = ALU_SLT;
            3'b011:  arith_op = ALU_SLTU;
            3'b100:  arith_op = ALU_XOR;
            3'b101:  arith_op = f7_5 ? ALU_SRA : ALU_SRL;
            3'b110:  arith_op = ALU_OR;
            default: arith_op = ALU_AND;
        endcase
    end

    always_comb begin
        reg_write = 0; alu_a_pc = 0; alu_b_imm = 0; imm_sel = IMM_I;
        alu_op = ALU_ADD; mem_read = 0; mem_write = 0; branch = 0;
        jal = 0; jalr = 0; wb_sel = 2'd0; is_system = 0; illegal = 0;

        case (opcode)
            OP_LUI:    begin reg_write=1; alu_b_imm=1; imm_sel=IMM_U; alu_op=ALU_PASSB; end
            OP_AUIPC:  begin reg_write=1; alu_a_pc=1; alu_b_imm=1; imm_sel=IMM_U; end
            OP_JAL:    begin reg_write=1; jal=1; wb_sel=2'd2; end
            OP_JALR:   begin reg_write=1; jalr=1; alu_b_imm=1; imm_sel=IMM_I; wb_sel=2'd2;
                             illegal = (funct3 != 3'b000); end
            OP_BRANCH: begin branch=1; illegal = (funct3 == 3'b010 || funct3 == 3'b011); end
            OP_LOAD:   begin reg_write=1; alu_b_imm=1; imm_sel=IMM_I; mem_read=1; wb_sel=2'd1;
                             illegal = !(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 ||
                                         funct3 == 3'b100 || funct3 == 3'b101); end
            OP_STORE:  begin alu_b_imm=1; imm_sel=IMM_S; mem_write=1;
                             illegal = !(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010); end
            OP_IMM:    begin reg_write=1; alu_b_imm=1; imm_sel=IMM_I; alu_op=arith_op;
                             if (funct3 == 3'b001)      illegal = (funct7 != 7'b0000000);
                             else if (funct3 == 3'b101) illegal = !(funct7 == 7'b0000000 || funct7 == 7'b0100000);
                       end
            OP_REG:    begin reg_write=1; alu_op=arith_op;
                             if (funct7 == 7'b0000000)      illegal = 0;
                             else if (funct7 == 7'b0100000) illegal = !(funct3 == 3'b000 || funct3 == 3'b101);
                             else                           illegal = 1;
                       end
            OP_FENCE:  ; // NOP
            OP_SYSTEM: is_system = 1;
            default:   illegal = 1;
        endcase
    end
endmodule

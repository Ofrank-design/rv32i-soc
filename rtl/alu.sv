module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  op,
    output logic [31:0] y
);
`include "rv_defs.svh"
    always_comb begin
        case (op)
            ALU_ADD:   y = a + b;
            ALU_SUB:   y = a - b;
            ALU_SLL:   y = a << b[4:0];
            ALU_SLT:   y = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU:  y = {31'b0, (a < b)};
            ALU_XOR:   y = a ^ b;
            ALU_SRL:   y = a >> b[4:0];
            ALU_SRA:   y = $signed(a) >>> b[4:0];
            ALU_OR:    y = a | b;
            ALU_AND:   y = a & b;
            ALU_PASSB: y = b;
            default:   y = 32'b0;
        endcase
    end
endmodule

// Machine-mode CSRs, just enough for traps and a timer interrupt: mstatus (MIE/MPIE only),
// misa, mie (MTIE only), mtvec (direct mode), mscratch, mepc, mcause, mtval, mip (MTIP),
// mcycle, minstret and mhartid. The counters are 32 bits wide, not 64.
module csr_file (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [11:0] addr,
    input  logic [31:0] wdata,
    input  logic [1:0]  op,          // 01 write, 10 set, 11 clear
    input  logic        wen,
    output logic [31:0] rdata,
    input  logic        trap_enter,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_val,
    input  logic        mret_en,
    input  logic        retire,
    input  logic        timer_irq,
    output logic [31:0] mtvec_o,
    output logic [31:0] mepc_o,
    output logic        irq_pending
);
    logic mie_b, mpie, mtie;
    logic [31:0] mtvec, mepc, mcause, mtval, mscratch, cyc, inst;

    wire [31:0] mstatus = {19'b0, 2'b11, 3'b0, mpie, 3'b0, mie_b, 3'b0};

    always_comb begin
        case (addr)
            12'h300: rdata = mstatus;
            12'h301: rdata = 32'h40000100;                  // misa: RV32I
            12'h304: rdata = {24'b0, mtie, 7'b0};
            12'h305: rdata = mtvec;
            12'h340: rdata = mscratch;
            12'h341: rdata = mepc;
            12'h342: rdata = mcause;
            12'h343: rdata = mtval;
            12'h344: rdata = {24'b0, timer_irq, 7'b0};
            12'hB00, 12'hC00: rdata = cyc;
            12'hB02, 12'hC02: rdata = inst;
            12'hF14: rdata = 32'b0;
            default: rdata = 32'b0;
        endcase
    end

    logic [31:0] nv;
    always_comb begin
        case (op)
            2'b01:   nv = wdata;
            2'b10:   nv = rdata | wdata;
            default: nv = rdata & ~wdata;
        endcase
    end

    assign mtvec_o = {mtvec[31:2], 2'b00};
    assign mepc_o  = mepc;
    assign irq_pending = mie_b & mtie & timer_irq;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mie_b <= 0; mpie <= 0; mtie <= 0;
            mtvec <= 0; mepc <= 0; mcause <= 0; mtval <= 0; mscratch <= 0;
            cyc <= 0; inst <= 0;
        end else begin
            cyc <= cyc + 1;
            if (retire) inst <= inst + 1;
            if (trap_enter) begin
                mepc <= trap_pc; mcause <= trap_cause; mtval <= trap_val;
                mpie <= mie_b;   mie_b <= 1'b0;
            end else begin
                if (mret_en) begin mie_b <= mpie; mpie <= 1'b1; end
                if (wen) begin
                    case (addr)
                        12'h300: begin mie_b <= nv[3]; mpie <= nv[7]; end
                        12'h304: mtie     <= nv[7];
                        12'h305: mtvec    <= {nv[31:2], 2'b00};
                        12'h340: mscratch <= nv;
                        12'h341: mepc     <= {nv[31:2], 2'b00};
                        12'h342: mcause   <= nv;
                        12'h343: mtval    <= nv;
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule

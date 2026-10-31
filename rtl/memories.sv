// Memories written so FPGA tools map them onto block RAM: reads are registered (they return data
// one clock after the address), so the core is built around that (see cpu_core.sv).

// ROM with two read ports: instruction fetch and data reads (startup code copies .data out of ROM).
// Contents come from INIT_FILE (one 32-bit hex word per line), or from +HEX=<file> in simulation.
// Anything the file doesn't cover reads as a NOP.
module rom_mem #(parameter WORDS = 2048, parameter INIT_FILE = "") (
    input  logic        clk,
    input  logic [31:0] i_addr,
    output logic [31:0] i_data,
    input  logic [31:0] d_addr,
    output logic [31:0] d_data
);
    localparam AW = $clog2(WORDS);
    logic [31:0] mem [0:WORDS-1];
    // With INIT_FILE set (the FPGA build) the file is the whole story. Without it (simulation) the
    // ROM starts as NOPs and +HEX=<file> overlays an image. These are separate generate branches
    // because synthesis tools only reliably honor $readmemh when it is not behind a runtime `if`.
    generate
        if (INIT_FILE != "") begin : g_file
            initial $readmemh(INIT_FILE, mem);
        end else begin : g_sim
            integer k;
`ifndef SYNTHESIS
            reg [8*256-1:0] hexfile;
`endif
            initial begin
                for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'h00000013;
`ifndef SYNTHESIS
                if ($value$plusargs("HEX=%s", hexfile)) $readmemh(hexfile, mem);
`endif
            end
        end
    endgenerate
    always_ff @(posedge clk) begin
        i_data <= mem[i_addr[AW+1:2]];
        d_data <= mem[d_addr[AW+1:2]];
    end
endmodule

// RAM: four byte lanes so each lane has a single write port (maps cleanly to block RAM).
module ram_mem #(parameter WORDS = 1024) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    output logic [31:0] rdata
);
    localparam AW = $clog2(WORDS);
    logic [7:0] m0 [0:WORDS-1];
    logic [7:0] m1 [0:WORDS-1];
    logic [7:0] m2 [0:WORDS-1];
    logic [7:0] m3 [0:WORDS-1];
    integer k;
    initial for (k = 0; k < WORDS; k = k + 1) begin
        m0[k] = 8'h00; m1[k] = 8'h00; m2[k] = 8'h00; m3[k] = 8'h00;
    end
    always_ff @(posedge clk) begin
        if (wstrb[0]) m0[addr[AW+1:2]] <= wdata[7:0];
        if (wstrb[1]) m1[addr[AW+1:2]] <= wdata[15:8];
        if (wstrb[2]) m2[addr[AW+1:2]] <= wdata[23:16];
        if (wstrb[3]) m3[addr[AW+1:2]] <= wdata[31:24];
        rdata <= {m3[addr[AW+1:2]], m2[addr[AW+1:2]], m1[addr[AW+1:2]], m0[addr[AW+1:2]]};
    end
    wire [31:0] word0 = {m3[0], m2[0], m1[0], m0[0]};   // handy for testbenches
endmodule

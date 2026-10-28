// ROM with two read ports: one for instruction fetch, one for data reads (the startup code
// copies .data out of ROM, so the data side needs to see it). Load it with +HEX=<file>, one
// 32-bit hex word per line. Anything not covered by the file reads as a NOP.
module rom_mem #(parameter WORDS = 1024) (
    input  logic [31:0] i_addr, output logic [31:0] i_data,
    input  logic [31:0] d_addr, output logic [31:0] d_data
);
    logic [31:0] mem [0:WORDS-1];
    reg [8*256-1:0] hexfile;
    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'h00000013;
        if ($value$plusargs("HEX=%s", hexfile)) $readmemh(hexfile, mem);
    end
    localparam AW = $clog2(WORDS);
    assign i_data = mem[i_addr[AW+1:2]];
    assign d_data = mem[d_addr[AW+1:2]];
endmodule

// RAM: byte-enable writes on the clock edge, combinational reads.
module ram_mem #(parameter WORDS = 1024) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    output logic [31:0] rdata
);
    localparam AW = $clog2(WORDS);
    logic [31:0] mem [0:WORDS-1];
    integer k;
    initial for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'b0;
    always_ff @(posedge clk) begin
        if (wstrb[0]) mem[addr[AW+1:2]][7:0]   <= wdata[7:0];
        if (wstrb[1]) mem[addr[AW+1:2]][15:8]  <= wdata[15:8];
        if (wstrb[2]) mem[addr[AW+1:2]][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[addr[AW+1:2]][31:24] <= wdata[31:24];
    end
    assign rdata = mem[addr[AW+1:2]];
endmodule

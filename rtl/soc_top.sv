// Small SoC used to run the firmware in simulation.
//   0x0000_0000  ROM    8 KB
//   0x1000_0000  RAM    4 KB
//   0x4000_0000  GPIO   DATA/DIR/SET/CLR
//   0x4000_1000  LED matrix   ROW/COL
//   0x4000_2000  Timer  MTIME (+0), MTIMECMP (+4); interrupt while signed(mtime - mtimecmp) >= 0
// The peripheral layouts are made up for this project, not copied from a real chip.
module soc_top #(parameter ROM_WORDS = 2048, RAM_WORDS = 1024, parameter ROM_INIT = "") (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] gpio_in,
    output logic [31:0] gpio_out,
    output logic [31:0] gpio_dir,
    output logic [7:0]  matrix_row,
    output logic [7:0]  matrix_col
);
    logic [31:0] pc, instr, d_addr, d_wdata, d_rdata, rom_rd, ram_rd;
    logic [3:0]  d_wstrb;
    logic        d_re;
    logic        timer_irq;

    cpu_core u_cpu (.clk, .rst_n, .timer_irq, .imem_addr(pc), .imem_data(instr),
                    .dmem_addr(d_addr), .dmem_wdata(d_wdata), .dmem_wstrb(d_wstrb),
                    .dmem_re(d_re), .dmem_rdata(d_rdata));

    rom_mem #(ROM_WORDS, ROM_INIT) u_rom (.clk, .i_addr(pc), .i_data(instr), .d_addr(d_addr), .d_data(rom_rd));

    wire sel_rom  = (d_addr[31:28] == 4'h0);
    wire sel_ram  = (d_addr[31:28] == 4'h1);
    wire sel_per  = (d_addr[31:28] == 4'h4);
    wire sel_gpio = sel_per && (d_addr[15:12] == 4'h0);
    wire sel_mtx  = sel_per && (d_addr[15:12] == 4'h1);
    wire sel_tmr  = sel_per && (d_addr[15:12] == 4'h2);

    ram_mem #(RAM_WORDS) u_ram (.clk, .addr(d_addr), .wdata(d_wdata),
                                .wstrb(sel_ram ? d_wstrb : 4'b0), .rdata(ram_rd));

    function automatic [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] s);
        merge = { s[3] ? nw[31:24] : old[31:24], s[2] ? nw[23:16] : old[23:16],
                  s[1] ? nw[15:8]  : old[15:8],  s[0] ? nw[7:0]   : old[7:0] };
    endfunction

    // GPIO: 0x0 DATA, 0x4 DIR, 0x8 SET, 0xC CLR
    logic [31:0] latch, dir;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin latch <= 32'b0; dir <= 32'b0; end
        else if (sel_gpio && |d_wstrb) begin
            case (d_addr[3:2])
                2'd0: latch <= merge(latch, d_wdata, d_wstrb);
                2'd1: dir   <= merge(dir,   d_wdata, d_wstrb);
                2'd2: latch <= latch |  d_wdata;
                2'd3: latch <= latch & ~d_wdata;
            endcase
        end
    end
    assign gpio_out = latch;
    assign gpio_dir = dir;
    wire [31:0] gpio_rd = (d_addr[3:2] == 2'd0) ? ((latch & dir) | (gpio_in & ~dir)) :
                          (d_addr[3:2] == 2'd1) ? dir : 32'b0;

    // LED matrix: 0x0 ROW (one-hot select), 0x4 COL data
    logic [31:0] mrow, mcol;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mrow <= 32'b0; mcol <= 32'b0; end
        else if (sel_mtx && |d_wstrb) begin
            if (d_addr[2]) mcol <= merge(mcol, d_wdata, d_wstrb);
            else           mrow <= merge(mrow, d_wdata, d_wstrb);
        end
    end
    assign matrix_row = mrow[7:0];
    assign matrix_col = mcol[7:0];
    wire [31:0] mtx_rd = d_addr[2] ? mcol : mrow;

    // Timer
    logic [31:0] mtime, mtimecmp;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mtime <= 32'b0; mtimecmp <= 32'h7FFFFFFF; end
        else begin
            mtime <= mtime + 32'd1;
            if (sel_tmr && |d_wstrb) begin
                if (d_addr[2]) mtimecmp <= merge(mtimecmp, d_wdata, d_wstrb);
                else           mtime    <= merge(mtime,    d_wdata, d_wstrb);
            end
        end
    end
    wire [31:0] tdiff = mtime - mtimecmp;
    assign timer_irq = ~tdiff[31];   // signed(mtime - mtimecmp) >= 0
    wire [31:0] tmr_rd = d_addr[2] ? mtimecmp : mtime;

    always_comb begin
        if      (sel_rom)  d_rdata = rom_rd;
        else if (sel_ram)  d_rdata = ram_rd;
        else if (sel_gpio) d_rdata = gpio_rd;
        else if (sel_mtx)  d_rdata = mtx_rd;
        else if (sel_tmr)  d_rdata = tmr_rd;
        else               d_rdata = 32'b0;
    end
endmodule

// Top level for the ULX3S (Lattice ECP5-25F, 25 MHz oscillator).
//
//   btn[1]  FIRE1   the application's button (active high), run through a 2-flop synchronizer
//   btn[2]  FIRE2   hold to reset the CPU
//   led[0]  the application's LED (GPIO bit 1)
//   led[1]  fault LED, lit when the bootloader rejects the image (GPIO bit 2)
//   led[2]  lit while the CPU is running (out of reset)
//   gp[7:0]   LED matrix rows,  gp[15:8]  LED matrix columns (outputs only)
//
// The matrix pins drive a header, not LEDs. Put current-limiting resistors or a driver stage
// between them and the matrix, and check the polarity of your matrix against the firmware.
module fpga_top #(parameter ROM_INIT = "image.hex", parameter ROM_WORDS = 2048, parameter RAM_WORDS = 1024, parameter POR_BITS = 16) (
    input  logic        clk_25mhz,
    input  logic [6:0]  btn,
    output logic [7:0]  led,
    output logic [15:0] gp
);
    // Power-on reset: hold the CPU for 2^POR_BITS clocks (65k by default) after configuration, and while FIRE2 is held.
    logic [POR_BITS-1:0] por = '0;
    wire         por_done = &por;
    always_ff @(posedge clk_25mhz) if (!por_done) por <= por + 1'b1;

    // Reset asserts immediately but releases synchronously.
    logic [1:0] rst_sync = 2'b00;
    wire        rst_in_n = por_done & ~btn[2];
    always_ff @(posedge clk_25mhz or negedge rst_in_n)
        if (!rst_in_n) rst_sync <= 2'b00;
        else           rst_sync <= {rst_sync[0], 1'b1};
    wire rst_n = rst_sync[1];

    // Button synchronizer (the debouncing is done in firmware).
    logic [1:0] btn_sync = 2'b00;
    always_ff @(posedge clk_25mhz) btn_sync <= {btn_sync[0], btn[1]};

    logic [31:0] gpio_out, gpio_dir;
    logic [7:0]  matrix_row, matrix_col;

    soc_top #(.ROM_INIT(ROM_INIT), .ROM_WORDS(ROM_WORDS), .RAM_WORDS(RAM_WORDS)) u_soc (
        .clk(clk_25mhz), .rst_n,
        .gpio_in({31'b0, btn_sync[1]}),
        .gpio_out, .gpio_dir,
        .matrix_row, .matrix_col
    );

    assign led[0]   = gpio_dir[1] & gpio_out[1];
    assign led[1]   = gpio_dir[2] & gpio_out[2];
    assign led[2]   = rst_n;
    assign led[7:3] = 5'b0;
    assign gp       = {matrix_col, matrix_row};
endmodule

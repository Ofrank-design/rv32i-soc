`timescale 1ns/1ps
// Board-level test of fpga_top. Run on the RTL, or on the synthesized netlist (make gatesim).
module tb_fpga #(parameter BOOT_WAIT = 60000, parameter PRESS = 3000);
    reg clk = 0;
    reg [6:0] btn = 0;
    wire [7:0] led;
    wire [15:0] gp;
    fpga_top dut (.clk_25mhz(clk), .btn(btn), .led(led), .gp(gp));
    always #20 clk = ~clk;   // 25 MHz

    integer i, errors = 0;
    task check(input cond, input [8*48-1:0] msg);
        if (!cond) begin errors = errors + 1; $display("  FAIL: %0s", msg); end
    endtask
    task wait_clk(input integer n); repeat (n) @(negedge clk); endtask

    initial begin
        // power-on reset (65k clocks) + HMAC verification (~45k clocks) + app start
        i = 0; while (!led[2] && i < 200000) begin wait_clk(1); i = i + 1; end
        check(led[2] == 1, "CPU left reset");
        wait_clk(BOOT_WAIT);
        check(led[1] == 0, "no fault LED with the signed image");
        check(led[0] == 0, "LED off before any press");
        btn[1] = 1; wait_clk(PRESS); btn[1] = 0; wait_clk(PRESS);
        check(led[0] == 1, "FIRE1 press turns the LED on");
        btn[1] = 1; wait_clk(PRESS); btn[1] = 0; wait_clk(PRESS);
        check(led[0] == 0, "second press turns it off");
        if (errors == 0) $display("PASS: tb_fpga"); else $display("FAILED: tb_fpga (%0d errors)", errors);
        $finish;
    end
endmodule

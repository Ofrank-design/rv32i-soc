`timescale 1ns/1ps
module tb_soc;
    reg clk = 0, rst_n = 0;
    reg [31:0] gpio_in = 0;
    wire [31:0] gpio_out, gpio_dir;
    wire [7:0] mrow, mcol;
    soc_top dut (.clk, .rst_n, .gpio_in, .gpio_out, .gpio_dir, .matrix_row(mrow), .matrix_col(mcol));
    always #5 clk = ~clk;

    wire led = gpio_dir[1] & gpio_out[1];
    reg [8*16-1:0] test;
    integer errors = 0, i, idx;
    reg [7:0] cap [0:7];
    reg [7:0] exp [0:7];

    task check(input cond, input [8*40-1:0] msg);
        if (!cond) begin errors = errors + 1; $display("  FAIL: %0s", msg); end
    endtask
    task cycles(input integer n); repeat (n) @(negedge clk); endtask

    // matrix capture: record COL value whenever a single row is selected and COL != 0
    always @(negedge clk)
        if (mrow != 0 && (mrow & (mrow - 1)) == 0 && mcol != 0) begin
            for (idx = 0; idx < 8; idx = idx + 1) if (mrow[idx]) cap[idx] = mcol;
        end

    initial begin
        if (!$value$plusargs("TEST=%s", test)) test = "blink";
        for (i = 0; i < 8; i = i + 1) cap[i] = 8'h00;
        exp[0]=8'h18; exp[1]=8'h3C; exp[2]=8'h7E; exp[3]=8'hDB;
        exp[4]=8'hFF; exp[5]=8'h24; exp[6]=8'h5A; exp[7]=8'h81;
        cycles(4); rst_n = 1;

        if (test == "blink") begin
            cycles(300);
            check(gpio_dir[1] == 1, "LED pin configured as output");
            check(led == 0, "LED off at idle");
            gpio_in[0] = 1; cycles(300);
            check(led == 1, "LED on after first press");
            cycles(800);
            check(led == 1, "no retoggle while held");
            gpio_in[0] = 0; cycles(300);
            check(led == 1, "LED stays on after release");
            gpio_in[0] = 1; cycles(300);
            check(led == 0, "second press toggles LED off");
            gpio_in[0] = 0; cycles(100);
        end else if (test == "boot_ok") begin
            i = 0; while (!gpio_dir[1] && i < 800000) begin cycles(1); i = i + 1; end
            $display("  app started after %0d cycles (HMAC verified)", i);
            check(gpio_dir[1] == 1, "authentic image booted");
            check(gpio_out[2] == 0, "no fault LED with valid image");
            cycles(200);
            // press with contact bounce, then clean hold
            gpio_in[0]=1; cycles(12); gpio_in[0]=0; cycles(9); gpio_in[0]=1; cycles(15);
            gpio_in[0]=0; cycles(10); gpio_in[0]=1; cycles(1500);
            check(led == 1, "bouncy press -> exactly one toggle (on)");
            gpio_in[0]=0; cycles(10); gpio_in[0]=1; cycles(12); gpio_in[0]=0; cycles(1500);
            check(led == 1, "release bounce does not toggle");
            gpio_in[0]=1; cycles(1500); gpio_in[0]=0; cycles(1500);
            check(led == 0, "second press toggles off");
            gpio_in[0]=1; cycles(30); gpio_in[0]=0; cycles(1500);
            check(led == 0, "short glitch ignored");
        end else if (test == "boot_bad" || test == "boot_forged") begin
            i = 0; while (!gpio_out[2] && i < 800000) begin cycles(1); i = i + 1; end
            check(gpio_out[2] == 1, "fault LED set: image rejected");
            gpio_in[0]=1; cycles(1500); gpio_in[0]=0; cycles(500);
            check(led == 0, "application never ran");
        end else if (test == "matrix") begin
            cycles(4000);
            for (i = 0; i < 8; i = i + 1)
                check(cap[i] == exp[i], "matrix row pattern matches frame");
        end else if (test == "traptest") begin
            cycles(20000);
            if (dut.u_ram.word0 !== 32'h600D600D)
                $display("  mailbox = %h (0xBAD000NN -> failing test id NN)", dut.u_ram.word0);
            check(dut.u_ram.word0 === 32'h600D600D, "traptest mailbox == 600D600D");
        end else if (test == "matrix_irq") begin
            cycles(8000);
            for (i = 0; i < 8; i = i + 1)
                check(cap[i] == exp[i], "ISR-driven rows match frame");
            gpio_in[0] = 1; cycles(3000); gpio_in[0] = 0; cycles(1500);
            for (i = 0; i < 8; i = i + 1) cap[i] = 8'h00;
            cycles(8000);
            for (i = 0; i < 8; i = i + 1)
                check(cap[i] == (exp[i] ^ 8'hFF), "button inverts display while ISR keeps refreshing");
            gpio_in[0] = 1; cycles(3000); gpio_in[0] = 0; cycles(1500);
            for (i = 0; i < 8; i = i + 1) cap[i] = 8'h00;
            cycles(8000);
            for (i = 0; i < 8; i = i + 1)
                check(cap[i] == exp[i], "second press restores display");
        end else if (test == "cputest") begin
            cycles(6000);
            if (dut.u_ram.word0 !== 32'h600D600D)
                $display("  mailbox = %h (0xBAD000NN -> failing test id NN)", dut.u_ram.word0);
            check(dut.u_ram.word0 === 32'h600D600D, "cputest mailbox == 600D600D");
        end

        if (errors == 0) $display("PASS: %0s", test);
        else             $display("FAILED: %0s (%0d errors)", test, errors);
        $finish;
    end
endmodule

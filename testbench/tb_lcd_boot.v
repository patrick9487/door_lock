`timescale 1ns/1ps

// Decode physical LCD pins; do not substitute a ready/done mock.
module tb_lcd_boot;
    parameter integer CLK_HZ = 1_000_000;
    parameter integer QUICK = 0;
    parameter RESET_ACTIVE_LOW = 1'b1;
    localparam integer US_CYCLES = (CLK_HZ + 999999) / 1000000;
    reg clk = 0;
    reg rst = RESET_ACTIVE_LOW; // Released button; no manual reset at power-up.
    always #(500000000.0 / CLK_HZ) clk = ~clk;
    reg pressed = 0;
    wire [3:0] row;
    wire [3:0] col = (pressed && row[0] === 1'b0) ? 4'b1110 : 4'b1111;
    wire rs, rw, e;
    wire [3:0] data;
    integer cycle = 0, rise_cycle = 0, change_cycle = 0;
    integer init_index = 0, address = 0, writes = 0;
    reg [3:0] hi;
    reg half = 0;
    reg [7:0] value;
    reg [7:0] ddram [0:127];
    reg [127:0] line1, line2;
    reg [55:0] init_nibbles = 56'h3332280801060c;
    integer n;

    door_lock_top #(.CLK_HZ(CLK_HZ), .RESET_ACTIVE_LOW(RESET_ACTIVE_LOW)) dut (
        .i_clk(clk), .i_rst(rst), .i_col(col), .o_row(row),
        .o_lcd_rs(rs), .o_lcd_rw(rw), .o_lcd_e(e), .o_lcd_data(data)
    );

    always @(posedge clk) begin
        cycle = cycle + 1;
        #1;
        if (rw !== 1'b0) $fatal(1, "LCD RW must stay low, including reset");
        if (dut.reset_active) begin
            init_index = 0; half = 0; writes = 0; address = 0;
            for (integer j = 0; j < 128; j = j + 1) ddram[j] = 8'h20;
        end
    end
    always @(data or rs) begin
        if (e === 1'b1 && !dut.reset_active)
            $fatal(1, "LCD data/RS changed while E high");
        change_cycle = cycle;
    end
    always @(posedge e) if (!dut.reset_active) begin
        if (cycle - change_cycle < US_CYCLES)
            $fatal(1, "LCD setup interval too short");
        rise_cycle = cycle;
    end
    always @(negedge e) if (!dut.reset_active && cycle > 0) begin
        if (cycle - rise_cycle < US_CYCLES)
            $fatal(1, "LCD enable pulse too short");
        if (init_index < 14) begin
            if (rs !== 0 || data !== ((init_nibbles >> ((13-init_index)*4)) & 4'hf))
                $fatal(1, "bad initialization nibble %0d: %h", init_index, data);
            init_index = init_index + 1;
        end else if (!half) begin
            hi = data; half = 1;
        end else begin
            value = {hi, data}; half = 0;
            if (!rs && value[7]) address = value & 127;
            else if (rs) begin
                ddram[address] = value;
                address = (address + 1) & 127;
                writes = writes + 1;
            end
        end
    end
    task check_screen;
        begin
            for (n = 0; n < 16; n = n + 1) begin
                line1[(15-n)*8 +: 8] = ddram[n];
                line2[(15-n)*8 +: 8] = ddram[64+n];
            end
            if (line1 !== "ENTER PIN       ") $fatal(1, "bad header: %s", line1);
        end
    endtask
    initial begin
        wait (writes >= 32);
        check_screen;
        if (line2 !== "                ") $fatal(1, "initial second line not blank");
        if (!dut.lcd_init_done) $fatal(1, "initialization never completed");
        $display("PASS: boot without external reset, RW low, initialization, both rows (%0d Hz)", CLK_HZ);
        if (!QUICK) begin
            @(negedge clk); pressed = 1;
            repeat (CLK_HZ/25) @(negedge clk);
            pressed = 0;
            wait (ddram[64] === 8'h2a);
            if (dut.pin_length !== 8'd1) $fatal(1, "physical key not accepted exactly once");
            $display("PASS: physical key appears as star on second row");
            // Assert reset between clock edges; restart the entire LCD sequence.
            @(negedge clk); #1; rst = !RESET_ACTIVE_LOW;
            repeat (5) @(negedge clk);
            rst = RESET_ACTIVE_LOW;
            wait (writes >= 32);
            check_screen;
            if (line2 !== "                ") $fatal(1, "reset did not clear display");
            $display("PASS: external reset reinitializes LCD and clears PIN");
        end
        $finish;
    end
    initial begin #1500000000; $fatal(1, "LCD boot timeout"); end
endmodule

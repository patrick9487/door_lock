`timescale 1ns/1ps

// Simulation only. Compile together with your pin_entry.v.
// Function keys: 10=Enter, 11=Backspace, 12=Cancel.
// A/B/... are represented by codes 13..31, not ASCII characters.
module tb_pin_entry;
    localparam MIN_DIGITS = 6;
    localparam MAX_DIGITS = 128;
    localparam [4:0] KEY_ENTER     = 5'd10;
    localparam [4:0] KEY_BACKSPACE = 5'd11;
    localparam [4:0] KEY_CANCEL    = 5'd12;

    reg        i_clk;
    reg        i_rst;
    reg        i_clear;
    reg        i_key_pulse;
    reg  [4:0] i_key_code;
    reg        i_enable;
    reg  [6:0] i_read_addr;
    wire [3:0] o_read_digit;
    wire       o_read_valid;
    wire [7:0] o_length;
    wire       o_submit_pulse;
    wire       o_submitted;
    wire       o_short_pulse;
    wire       o_full;

    integer checks;
    integer errors;
    integer n;

    pin_entry #(
        .MIN_DIGITS(MIN_DIGITS),
        .MAX_DIGITS(MAX_DIGITS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear),
        .i_key_pulse(i_key_pulse),
        .i_key_code(i_key_code),
        .i_enable(i_enable),
        .i_read_addr(i_read_addr),
        .o_read_digit(o_read_digit),
        .o_read_valid(o_read_valid),
        .o_length(o_length),
        .o_submit_pulse(o_submit_pulse),
        .o_submitted(o_submitted),
        .o_short_pulse(o_short_pulse),
        .o_full(o_full)
    );

    // 20 ns period = 50 MHz. Inputs change on falling edges;
    // checks occur 1 ns after rising edges to avoid NBA races.
    initial i_clk = 1'b0;
    always #10 i_clk = ~i_clk;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL @ %0t: %0s", $time, message);
            end
        end
    endtask

    task check_state;
        input [7:0] expected_length;
        input expected_submitted;
        begin
            check(o_length === expected_length, "length mismatch");
            check(o_submitted === expected_submitted, "submitted mismatch");
            check(o_full === (expected_length >= MAX_DIGITS), "full mismatch");
        end
    endtask

    task read_digit;
        input [6:0] address;
        input [3:0] expected_digit;
        input expected_valid;
        begin
            i_read_addr = address;
            #1;
            check(o_read_valid === expected_valid, "read_valid mismatch");
            check(o_read_digit === expected_digit, "read_digit mismatch");
        end
    endtask

    task press_key;
        input [4:0] code;
        input expected_submit;
        input expected_short;
        begin
            @(negedge i_clk);
            i_key_code  = code;
            i_key_pulse = 1'b1;
            @(posedge i_clk);
            #1;
            check(o_submit_pulse === expected_submit, "submit pulse mismatch");
            check(o_short_pulse === expected_short, "short pulse mismatch");
            @(negedge i_clk);
            i_key_pulse = 1'b0;
            @(posedge i_clk);
            #1;
            check(o_submit_pulse === 1'b0, "submit pulse must clear next cycle");
            check(o_short_pulse === 1'b0, "short pulse must clear next cycle");
        end
    endtask

    task clear_entry;
        begin
            @(negedge i_clk);
            i_clear = 1'b1;
            @(posedge i_clk);
            #1;
            check_state(8'd0, 1'b0);
            check(o_submit_pulse === 1'b0, "clear: submit pulse must be zero");
            check(o_short_pulse === 1'b0, "clear: short pulse must be zero");
            read_digit(7'd0, 4'd0, 1'b0);
            @(negedge i_clk);
            i_clear = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        i_rst = 1'b1;
        i_clear = 1'b0;
        i_key_pulse = 1'b0;
        i_key_code = 5'd0;
        i_enable = 1'b1;
        i_read_addr = 7'd0;

        repeat (2) @(posedge i_clk);
        #1;
        check_state(8'd0, 1'b0);
        check(o_submit_pulse === 1'b0, "reset: submit pulse");
        check(o_short_pulse === 1'b0, "reset: short pulse");
        read_digit(7'd0, 4'd0, 1'b0);
        read_digit(7'd127, 4'd0, 1'b0);
        @(negedge i_clk);
        i_rst = 1'b0;

        $display("TEST: empty backspace / empty Enter");
        press_key(KEY_BACKSPACE, 1'b0, 1'b0);
        check_state(8'd0, 1'b0);
        press_key(KEY_ENTER, 1'b0, 1'b1);
        check_state(8'd0, 1'b0);

        $display("TEST: all digits 0..9 / asynchronous read");
        for (n = 0; n <= 9; n = n + 1) begin
            press_key(n, 1'b0, 1'b0);
            check_state(n + 1, 1'b0);
            read_digit(n, n, 1'b1);
        end
        for (n = 0; n <= 9; n = n + 1)
            read_digit(n, n, 1'b1);
        read_digit(7'd10, 4'd0, 1'b0);

        $display("TEST: unsupported A/B/etc., codes 13..31");
        // 13=A, 14=B. All 13..31 must be ignored by pin_entry.
        for (n = 13; n <= 31; n = n + 1) begin
            press_key(n, 1'b0, 1'b0);
            check_state(8'd10, 1'b0);
        end
        for (n = 0; n <= 9; n = n + 1)
            read_digit(n, n, 1'b1);

        $display("TEST: backspace invalidates old position / overwrite");
        press_key(KEY_BACKSPACE, 1'b0, 1'b0);
        check_state(8'd9, 1'b0);
        read_digit(7'd9, 4'd0, 1'b0);
        press_key(5'd4, 1'b0, 1'b0);
        check_state(8'd10, 1'b0);
        read_digit(7'd9, 4'd4, 1'b1);

        $display("TEST: Cancel / short PIN / exact minimum");
        press_key(KEY_CANCEL, 1'b0, 1'b0);
        check_state(8'd0, 1'b0);
        read_digit(7'd9, 4'd0, 1'b0);
        for (n = 1; n <= 5; n = n + 1)
            press_key(n, 1'b0, 1'b0);
        press_key(KEY_ENTER, 1'b0, 1'b1);
        check_state(8'd5, 1'b0);
        press_key(5'd6, 1'b0, 1'b0);
        press_key(KEY_ENTER, 1'b1, 1'b0);
        check_state(8'd6, 1'b1);

        $display("TEST: submitted freezes ALL key codes, including Cancel");
        for (n = 0; n <= 31; n = n + 1) begin
            press_key(n, 1'b0, 1'b0);
            check_state(8'd6, 1'b1);
        end
        for (n = 0; n < 6; n = n + 1)
            read_digit(n, n + 1, 1'b1);
        clear_entry;
        press_key(5'd8, 1'b0, 1'b0);
        check_state(8'd1, 1'b0);
        read_digit(7'd0, 4'd8, 1'b1);

        $display("TEST: enable=0 ignores ALL keys but preserves data");
        @(negedge i_clk);
        i_enable = 1'b0;
        for (n = 0; n <= 31; n = n + 1) begin
            press_key(n, 1'b0, 1'b0);
            check_state(8'd1, 1'b0);
        end
        read_digit(7'd0, 4'd8, 1'b1);
        clear_entry;  // clear must work even when disabled
        @(negedge i_clk);
        i_enable = 1'b1;

        $display("TEST: code changes without key_pulse do nothing");
        for (n = 0; n <= 31; n = n + 1) begin
            @(negedge i_clk);
            i_key_code = n;
            @(posedge i_clk);
            #1;
            check_state(8'd0, 1'b0);
            check(o_submit_pulse === 1'b0, "no key pulse: submit");
            check(o_short_pulse === 1'b0, "no key pulse: short");
        end

        $display("TEST: full 128 digits / ignored overflow / refill / submit");
        for (n = 0; n < MAX_DIGITS; n = n + 1) begin
            press_key(n % 10, 1'b0, 1'b0);
            check_state(n + 1, 1'b0);
        end
        for (n = 0; n < MAX_DIGITS; n = n + 1)
            read_digit(n, n % 10, 1'b1);
        press_key(5'd9, 1'b0, 1'b0);
        check_state(8'd128, 1'b0);
        for (n = 0; n < MAX_DIGITS; n = n + 1)
            read_digit(n, n % 10, 1'b1);
        press_key(KEY_BACKSPACE, 1'b0, 1'b0);
        check_state(8'd127, 1'b0);
        read_digit(7'd127, 4'd0, 1'b0);
        press_key(5'd9, 1'b0, 1'b0);
        check_state(8'd128, 1'b0);
        read_digit(7'd127, 4'd9, 1'b1);
        press_key(KEY_ENTER, 1'b1, 1'b0);
        check_state(8'd128, 1'b1);
        clear_entry;

        $display("TEST: clear has priority over a simultaneous digit");
        press_key(5'd2, 1'b0, 1'b0);
        @(negedge i_clk);
        i_clear = 1'b1;
        i_key_pulse = 1'b1;
        i_key_code = 5'd7;
        @(posedge i_clk);
        #1;
        check_state(8'd0, 1'b0);
        read_digit(7'd0, 4'd0, 1'b0);
        @(negedge i_clk);
        i_clear = 1'b0;
        i_key_pulse = 1'b0;

        $display("TEST: clear has priority over a simultaneous Enter");
        for (n = 0; n < 6; n = n + 1)
            press_key(n, 1'b0, 1'b0);
        @(negedge i_clk);
        i_clear = 1'b1;
        i_key_pulse = 1'b1;
        i_key_code = KEY_ENTER;
        @(posedge i_clk);
        #1;
        check_state(8'd0, 1'b0);
        check(o_submit_pulse === 1'b0, "clear must suppress submit");
        check(o_short_pulse === 1'b0, "clear must suppress short");
        @(negedge i_clk);
        i_clear = 1'b0;
        i_key_pulse = 1'b0;

        $display("TEST: reset releases submitted state while disabled");
        for (n = 0; n < 6; n = n + 1)
            press_key(n, 1'b0, 1'b0);
        press_key(KEY_ENTER, 1'b1, 1'b0);
        @(negedge i_clk);
        i_enable = 1'b0;
        i_rst = 1'b1;
        i_clear = 1'b1;
        i_key_pulse = 1'b1;
        i_key_code = 5'd9;
        @(posedge i_clk);
        #1;
        check_state(8'd0, 1'b0);
        check(o_submit_pulse === 1'b0, "reset must suppress submit");
        check(o_short_pulse === 1'b0, "reset must suppress short");
        read_digit(7'd0, 4'd0, 1'b0);
        @(negedge i_clk);
        i_rst = 1'b0;
        i_clear = 1'b0;
        i_key_pulse = 1'b0;
        i_enable = 1'b1;
        press_key(5'd0, 1'b0, 1'b0);
        check_state(8'd1, 1'b0);
        read_digit(7'd0, 4'd0, 1'b1);

        if (errors == 0)
            $display("ALL PASS: %0d checks", checks);
        else
            $display("TEST FAILED: %0d errors / %0d checks", errors, checks);
        $finish;
    end

    // Catch a stalled test rather than run forever.
    initial begin
        #100000;
        $display("TEST FAILED: watchdog timeout");
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_keypad_input;
    // Accelerate simulation by reducing the DUT's cycles per row.
    // The clock remains 50 MHz; CLK_HZ here is a simulation override.
    localparam integer TEST_CLK_HZ = 10_000;
    localparam integer ROW_CYCLES = TEST_CLK_HZ / 1000;
    localparam integer FRAME_CYCLES = 4 * ROW_CYCLES;
    localparam integer SETTLE_CYCLES = 8 * FRAME_CYCLES;

    reg i_clk;
    reg i_rst;
    wire [3:0] i_col;
    wire [3:0] o_row;
    wire o_key_pulse;
    wire [4:0] o_key_code;

    // A 1 means the physical switch is closed.
    // bit = row * 4 + column, matching key_bitmap.
    reg [15:0] pressed;
    reg allow_pulse;
    reg [4:0] expected_code;
    reg previous_pulse;
    reg [1:0] previous_row;
    reg row_seen;
    integer pulse_count;
    integer checks;
    integer idx;
    integer start_count;
    integer first_key;
    integer second_key;

    keypad_input #(.CLK_HZ(TEST_CLK_HZ)) dut (
        .i_clk(i_clk), .i_rst(i_rst), .i_col(i_col),
        .o_row(o_row), .o_key_pulse(o_key_pulse),
        .o_key_code(o_key_code)
    );

    initial i_clk = 1'b0;
    always #10 i_clk = ~i_clk;

    // Model a diode-free matrix with column pull-ups.
    // A low row pulls connected columns low. Closed switches can also
    // carry that low through inactive (Z) rows, producing ghost keys.
    // Eight propagation rounds cover all eight row/column nodes.
    function [3:0] matrix_columns;
        input [3:0] rows;
        input [15:0] switches;
        reg [3:0] low_rows;
        reg [3:0] low_cols;
        integer step;
        integer r;
        integer c;
        begin
            low_rows = 4'b0000;
            low_cols = 4'b0000;
            for (r = 0; r < 4; r = r + 1)
                if (rows[r] === 1'b0)
                    low_rows[r] = 1'b1;
            for (step = 0; step < 8; step = step + 1) begin
                for (r = 0; r < 4; r = r + 1) begin
                    for (c = 0; c < 4; c = c + 1) begin
                        if (switches[r * 4 + c]) begin
                            if (low_rows[r]) low_cols[c] = 1'b1;
                            if (low_cols[c]) low_rows[r] = 1'b1;
                        end
                    end
                end
            end
            matrix_columns = ~low_cols;
        end
    endfunction

    assign i_col = matrix_columns(o_row, pressed);

    function [4:0] code_for_position;
        input integer position;
        begin
            case (position)
                 0: code_for_position = 5'd1;
                 1: code_for_position = 5'd2;
                 2: code_for_position = 5'd3;
                 3: code_for_position = 5'd11;
                 4: code_for_position = 5'd4;
                 5: code_for_position = 5'd5;
                 6: code_for_position = 5'd6;
                 7: code_for_position = 5'd12;
                 8: code_for_position = 5'd7;
                 9: code_for_position = 5'd8;
                10: code_for_position = 5'd9;
                11: code_for_position = 5'd14;
                12: code_for_position = 5'd15;
                13: code_for_position = 5'd0;
                14: code_for_position = 5'd10;
                15: code_for_position = 5'd13;
                default: code_for_position = 5'd31;
            endcase
        end
    endfunction

    task check;
        input condition;
        input [8*120-1:0] description;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, description);
                $fatal(1, "keypad_input test failed");
            end
        end
    endtask

    task wait_cycles;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge i_clk);
                #2; // Observe after nonblocking updates and monitor.
            end
        end
    endtask

    task drive_keys;
        input [15:0] switches;
        begin
            @(negedge i_clk);
            pressed = switches;
        end
    endtask

    task release_all;
        begin
            allow_pulse = 1'b0;
            drive_keys(16'd0);
            wait_cycles(SETTLE_CYCLES);
        end
    endtask

    task test_key;
        input integer position;
        integer before_press;
        begin
            before_press = pulse_count;
            expected_code = code_for_position(position);
            allow_pulse = 1'b1;
            drive_keys(16'h0001 << position);
            wait_cycles(SETTLE_CYCLES);
            check(pulse_count == before_press + 1,
                  "each key must generate exactly one event");
            wait_cycles(SETTLE_CYCLES);
            check(pulse_count == before_press + 1,
                  "holding a key must not repeat");
            release_all;
            check(pulse_count == before_press + 1,
                  "release must not generate a key event");
        end
    endtask

    // Monitor every clock, including the clocks between scan ticks.
    always @(posedge i_clk) begin
        #1;
        if (i_rst) begin
            check(o_row === 4'bzzzz, "reset must release all row outputs");
            check(o_key_pulse === 1'b0, "reset must clear output pulse");
            previous_pulse = 1'b0;
            row_seen = 1'b0;
        end
        else begin
            case (dut.scan_row)
                2'd0: check(o_row === 4'bzzz0, "row0 selected; others must be Z");
                2'd1: check(o_row === 4'bzz0z, "row1 selected; others must be Z");
                2'd2: check(o_row === 4'bz0zz, "row2 selected; others must be Z");
                2'd3: check(o_row === 4'b0zzz, "row3 selected; others must be Z");
                default: check(1'b0, "scan_row must be known");
            endcase
            if (row_seen && dut.scan_row != previous_row)
                check(dut.scan_row === ((previous_row + 2'd1) & 2'b11),
                      "row scan order must be 0,1,2,3,0");
            previous_row = dut.scan_row;
            row_seen = 1'b1;

            check((o_key_pulse === 1'b0) || (o_key_pulse === 1'b1),
                  "output pulse must be known");
            check(!(previous_pulse && o_key_pulse),
                  "output pulse must last only one clock");
            if (o_key_pulse === 1'b1) begin
                check(allow_pulse, "unexpected key event");
                check(o_key_code === expected_code, "wrong decoded key code");
                pulse_count = pulse_count + 1;
            end
            previous_pulse = o_key_pulse;
        end
    end

    initial begin
        i_rst = 1'b1;
        pressed = 16'd0;
        allow_pulse = 1'b0;
        expected_code = 5'd0;
        previous_pulse = 1'b0;
        previous_row = 2'd0;
        row_seen = 1'b0;
        pulse_count = 0;
        checks = 0;
        wait_cycles(5);
        @(negedge i_clk);
        i_rst = 1'b0;

        $display("TEST: idle / row outputs / scan order / pulse width");
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == 0, "idle must not generate events");

        $display("TEST: all 16 keys / long hold / stable release");
        for (idx = 0; idx < 16; idx = idx + 1)
            test_key(idx);

        $display("TEST: short press below debounce threshold");
        start_count = pulse_count;
        drive_keys(16'h0001);
        wait_cycles(2 * FRAME_CYCLES);
        release_all;
        check(pulse_count == start_count, "short press must be rejected");

        $display("TEST: press bounce then stable key / release bounce");
        for (idx = 0; idx < 6; idx = idx + 1) begin
            drive_keys(16'h0020);
            wait_cycles(ROW_CYCLES);
            drive_keys(16'd0);
            wait_cycles(ROW_CYCLES);
        end
        check(pulse_count == start_count, "bounce must not generate events");
        expected_code = 5'd5;
        allow_pulse = 1'b1;
        drive_keys(16'h0020);
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == start_count + 1, "stable press after bounce accepted once");
        allow_pulse = 1'b0;
        for (idx = 0; idx < 6; idx = idx + 1) begin
            drive_keys(16'd0);
            wait_cycles(ROW_CYCLES);
            drive_keys(16'h0020);
            wait_cycles(ROW_CYCLES);
        end
        release_all;
        check(pulse_count == start_count + 1, "release bounce must not repeat");
        test_key(5);

        $display("TEST: all 120 two-key combinations rejected");
        for (first_key = 0; first_key < 16; first_key = first_key + 1) begin
            for (second_key = first_key + 1; second_key < 16;
                 second_key = second_key + 1) begin
                start_count = pulse_count;
                drive_keys((16'h0001 << first_key) | (16'h0001 << second_key));
                wait_cycles(SETTLE_CYCLES);
                check(pulse_count == start_count, "two keys must be rejected");
                // Dropping only one key must not unlock the input state.
                drive_keys(16'h0001 << first_key);
                wait_cycles(SETTLE_CYCLES);
                check(pulse_count == start_count, "partial release must remain blocked");
                release_all;
            end
        end
        test_key(0);

        $display("TEST: three-key ghost rectangle / all keys rejected");
        start_count = pulse_count;
        drive_keys(16'h0031); // positions 0,4,5; phantom position 1
        wait_cycles(SETTLE_CYCLES);
        check(dut.key_bitmap === 16'h0033, "matrix model must produce phantom key");
        check(pulse_count == start_count, "ghost rectangle must be rejected");
        release_all;
        drive_keys(16'hffff);
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == start_count, "all-key press must be rejected");
        release_all;

        $display("TEST: changing keys without stable all-release must not repeat");
        start_count = pulse_count;
        expected_code = 5'd1;
        allow_pulse = 1'b1;
        drive_keys(16'h0001);
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == start_count + 1, "initial key accepted");
        allow_pulse = 1'b0;
        drive_keys(16'h0002);
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == start_count + 1, "direct key change must be ignored");
        release_all;
        test_key(1);

        $display("TEST: reset while held / restart from WAIT_PRESS");
        expected_code = 5'd10;
        allow_pulse = 1'b1;
        drive_keys(16'h4000);
        wait_cycles(SETTLE_CYCLES);
        start_count = pulse_count;
        @(negedge i_clk);
        i_rst = 1'b1;
        wait_cycles(5);
        @(negedge i_clk);
        i_rst = 1'b0;
        wait_cycles(SETTLE_CYCLES);
        check(pulse_count == start_count + 1,
              "held key after reset must be accepted once by current design");
        release_all;

        $display("ALL PASS: %0d checks, %0d key events", checks, pulse_count);
        $finish;
    end

    // Fail rather than hang if the test stops making progress.
    initial begin
        #10_000_000;
        $fatal(1, "testbench timeout");
    end
endmodule

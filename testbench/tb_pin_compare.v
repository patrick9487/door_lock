`timescale 1ns/1ps

module tb_pin_compare;

    reg        i_clk;
    reg        i_rst;
    reg        i_start;
    reg [7:0]  i_pin_length;
    reg [7:0]  i_ref_length;

    wire [3:0] i_pin_digit;
    wire       i_pin_valid;
    wire [3:0] i_ref_digit;
    wire       i_ref_valid;

    wire [6:0] o_read_addr;
    wire       o_read_enable;
    wire       o_busy;
    wire       o_done_pulse;
    wire       o_match;

    // 模擬兩份密碼記憶體
    reg [3:0] pin_memory [0:127];
    reg [3:0] ref_memory [0:127];

    // 控制資料是否準備好
    reg pin_ready;
    reg ref_ready;

    integer checks;
    integer idx;
    integer mismatch_pos;

    pin_compare dut (
        .i_clk        (i_clk),
        .i_rst        (i_rst),
        .i_start      (i_start),
        .i_pin_length (i_pin_length),
        .i_ref_length (i_ref_length),
        .i_pin_digit  (i_pin_digit),
        .i_pin_valid  (i_pin_valid),
        .i_ref_digit  (i_ref_digit),
        .i_ref_valid  (i_ref_valid),
        .o_read_addr  (o_read_addr),
        .o_read_enable(o_read_enable),
        .o_busy       (o_busy),
        .o_done_pulse (o_done_pulse),
        .o_match      (o_match)
    );

    initial i_clk = 1'b0;
    always #10 i_clk = ~i_clk;

    // 非同步讀取，與目前 pin_entry 的讀取方式一致
    assign i_pin_digit = pin_memory[o_read_addr];
    assign i_ref_digit = ref_memory[o_read_addr];

    assign i_pin_valid = o_read_enable && pin_ready;
    assign i_ref_valid = o_read_enable && ref_ready;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            checks = checks + 1;

            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1, "pin_compare test failed");
            end
        end
    endtask

    task wait_cycles;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge i_clk);
                #1;
            end
        end
    endtask

    // 準備兩份完全相同的密碼，包含數字 0～9
    task fill_equal;
        integer n;
        begin
            for (n = 0; n < 128; n = n + 1) begin
                pin_memory[n] = n % 10;
                ref_memory[n] = n % 10;
            end
        end
    endtask

    // 送出一個 clock 寬的開始訊號
    task start_compare;
        input [7:0] pin_len;
        input [7:0] ref_len;
        begin
            check(o_busy === 1'b0, "must be idle before starting");

            @(negedge i_clk);
            i_pin_length = pin_len;
            i_ref_length = ref_len;
            i_start = 1'b1;

            @(negedge i_clk);
            i_start = 1'b0;
        end
    endtask

    // 等待完成，超過 300 個 clock 就判定失敗
    task expect_result;
        input expected_match;
        integer timeout_count;
        begin
            timeout_count = 0;

            while ((o_done_pulse !== 1'b1) &&
                   (timeout_count < 300)) begin
                wait_cycles(1);
                timeout_count = timeout_count + 1;
            end

            check(o_done_pulse === 1'b1, "completion timeout");
            check(o_match === expected_match, "wrong comparison result");
            check(o_busy === 1'b0, "busy must clear when done");
            check(o_read_enable === 1'b0, "read enable must clear when done");

            wait_cycles(1);
            check(o_done_pulse === 1'b0, "done pulse must last one clock");
            check(o_match === expected_match, "result must remain available");
        end
    endtask

    initial begin
        checks = 0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_pin_length = 8'd0;
        i_ref_length = 8'd0;
        pin_ready = 1'b1;
        ref_ready = 1'b1;
        fill_equal;

        wait_cycles(3);
        check(o_busy === 1'b0, "reset clears busy");
        check(o_match === 1'b0, "reset clears match");
        check(o_done_pulse === 1'b0, "reset clears done");
        check(o_read_addr === 7'd0, "reset clears address");

        @(negedge i_clk);
        i_rst = 1'b0;

        $display("TEST: idle does not start automatically");
        wait_cycles(10);
        check(o_busy === 1'b0, "idle must stay idle");
        check(o_done_pulse === 1'b0, "idle must not generate done");

        $display("TEST: all equal lengths 1..128");
        for (idx = 1; idx <= 128; idx = idx + 1) begin
            start_compare(idx, idx);
            expect_result(1'b1);
        end

        $display("TEST: every mismatch position in a 128-digit PIN");
        for (mismatch_pos = 0; mismatch_pos < 128;
             mismatch_pos = mismatch_pos + 1) begin
            fill_equal;
            ref_memory[mismatch_pos] =
                (pin_memory[mismatch_pos] + 1) % 10;

            start_compare(8'd128, 8'd128);
            expect_result(1'b0);

            check(o_read_addr == mismatch_pos,
                  "must stop at first mismatched position");
        end
        fill_equal;

        $display("TEST: different lengths / empty / oversized");
        start_compare(8'd6, 8'd7);
        expect_result(1'b0);
        start_compare(8'd7, 8'd6);
        expect_result(1'b0);
        start_compare(8'd0, 8'd0);
        expect_result(1'b0);
        start_compare(8'd0, 8'd6);
        expect_result(1'b0);
        start_compare(8'd129, 8'd129);
        expect_result(1'b0);
        start_compare(8'd128, 8'd129);
        expect_result(1'b0);
        start_compare(8'd255, 8'd255);
        expect_result(1'b0);

        $display("TEST: wait for reference data at address zero");
        ref_ready = 1'b0;
        start_compare(8'd6, 8'd6);
        wait_cycles(10);

        check(o_busy === 1'b1, "must remain busy while waiting");
        check(o_read_enable === 1'b1, "must request data while waiting");
        check(o_read_addr === 7'd0, "must hold address while waiting");
        check(o_done_pulse === 1'b0, "must not finish without valid data");

        @(negedge i_clk);
        ref_ready = 1'b1;
        expect_result(1'b1);

        $display("TEST: stall partway / ignore start while busy / latch lengths");
        start_compare(8'd128, 8'd128);

        // 停在地址 3，暫時不提供輸入密碼資料
        wait (o_read_addr == 7'd3);
        @(negedge i_clk);
        pin_ready = 1'b0;

        // 忙碌期間的新 start 與新長度不得改變這次比對
        i_start = 1'b1;
        i_pin_length = 8'd0;
        i_ref_length = 8'd1;

        wait_cycles(10);
        check(o_read_addr === 7'd3, "stall must hold current address");
        check(o_busy === 1'b1, "new start must not interrupt comparison");
        check(o_done_pulse === 1'b0, "stall must not generate completion");

        @(negedge i_clk);
        i_start = 1'b0;
        pin_ready = 1'b1;
        expect_result(1'b1);

        check(o_read_addr === 7'd127,
              "must use captured length and compare through address 127");

        $display("TEST: reset aborts an active comparison");
        pin_ready = 1'b0;
        ref_ready = 1'b0;
        start_compare(8'd128, 8'd128);
        wait_cycles(5);

        @(negedge i_clk);
        i_rst = 1'b1;
        wait_cycles(2);

        check(o_busy === 1'b0, "reset must abort comparison");
        check(o_read_enable === 1'b0, "reset must stop reading");
        check(o_done_pulse === 1'b0, "reset must not report completion");
        check(o_match === 1'b0, "reset must clear old result");

        @(negedge i_clk);
        i_rst = 1'b0;
        pin_ready = 1'b1;
        ref_ready = 1'b1;

        start_compare(8'd6, 8'd6);
        expect_result(1'b1);

        $display("ALL PASS: %0d checks", checks);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "testbench timeout");
    end

endmodule
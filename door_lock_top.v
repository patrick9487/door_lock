module door_lock_top #(
    parameter integer CLK_HZ = 50_000_000,

    // 整合測試用固定密碼，每個十六進位 nibble 存一個數字
    // 123456：PIN_LENGTH = 6，PIN_CODE = 512'h123456
    parameter integer PIN_LENGTH = 6,
    parameter [511:0] PIN_CODE = 512'h123456
)(
    input  wire       i_clk,
    input  wire       i_rst,

    input  wire [3:0] i_col,
    output wire [3:0] o_row,

    output wire       o_lcd_rs,
    output wire       o_lcd_e,
    output wire [3:0] o_lcd_data,

    output reg        o_unlock_pulse,
    output reg        o_error_pulse,
    output wire       o_locked
);

    localparam [1:0] INPUT_PIN    = 2'd0;
    localparam [1:0] CHECK_PIN    = 2'd1;
    localparam [1:0] SHOW_RESULT  = 2'd2;
    localparam [1:0] LOCKED       = 2'd3;

    localparam [2:0] STATUS_INPUT  = 3'd0;
    localparam [2:0] STATUS_CHECK  = 3'd1;
    localparam [2:0] STATUS_OPEN   = 3'd2;
    localparam [2:0] STATUS_WRONG  = 3'd3;
    localparam [2:0] STATUS_LOCKED = 3'd4;

    localparam integer RESULT_CYCLES = CLK_HZ * 2;
    localparam integer LOCK_CYCLES   = CLK_HZ * 30;

    reg [1:0]  state;
    reg [2:0]  display_status;
    reg [1:0]  fail_count;
    reg [31:0] timer_counter;
    reg        pin_clear;

    // 鍵盤事件
    wire       key_pulse;
    wire [4:0] key_code;

    // PIN 輸入模組
    wire [7:0] pin_length;
    wire       pin_submitted;
    wire       pin_submit_pulse;
    wire       pin_short_pulse;
    wire       pin_full;
    wire [3:0] pin_read_digit;
    wire       pin_read_valid;
    wire [6:0] pin_read_addr;
    wire       pin_enable;

    // 密碼比對
    wire       compare_start;
    wire       compare_busy;
    wire       compare_read_enable;
    wire [6:0] compare_read_addr;
    wire       compare_done;
    wire       compare_match;

    reg  [3:0] ref_digit;
    wire       ref_valid;
    wire [7:0] ref_length;

    // LCD UI
    wire [6:0] ui_read_addr;
    wire       ui_read_valid;
    wire       digit_pulse;
    wire       toggle_pulse;
    wire       hide_pulse;
    wire       brief_mode;

    // UI 與 LCD driver 的介面
    wire       lcd_ready;
    wire       lcd_init_done;
    wire       lcd_done_pulse;
    wire       lcd_write_pulse;
    wire       lcd_write_rs;
    wire [7:0] lcd_write_data;


    // --------------------------------------------------------
    // 1. 輸入允許與 UI 事件
    // --------------------------------------------------------
    assign pin_enable = (state == INPUT_PIN);

    // 只在數字確實能被 pin_entry 接受時通知 UI
    assign digit_pulse =
        pin_enable &&
        !pin_submitted &&
        !pin_clear &&
        !i_rst &&
        key_pulse &&
        (key_code <= 5'd9) &&
        !pin_full;

    assign toggle_pulse =
        pin_enable &&
        !pin_submitted &&
        key_pulse &&
        (key_code == 5'd14);

    assign hide_pulse =
        pin_clear ||
        pin_submit_pulse ||
        (pin_enable &&
         key_pulse &&
         ((key_code == 5'd11) || (key_code == 5'd12)));

    assign compare_start =
        (state == INPUT_PIN) && pin_submit_pulse;

    assign o_locked = (state == LOCKED);


    // --------------------------------------------------------
    // 2. PIN 記憶體讀取地址選擇
    //    比對期間優先給 comparator，其餘時間給 LCD UI
    // --------------------------------------------------------
    assign pin_read_addr =
        compare_busy ? compare_read_addr : ui_read_addr;

    // comparator 使用讀取埠時，不提供數字資料給 UI
    assign ui_read_valid = pin_read_valid && !compare_busy;


    // --------------------------------------------------------
    // 3. 固定參考密碼
    //    第一位放在有效密碼範圍的最高 nibble
    // --------------------------------------------------------
    assign ref_length = PIN_LENGTH;

    assign ref_valid =
        compare_read_enable &&
        (PIN_LENGTH >= 1) &&
        (PIN_LENGTH <= 128) &&
        (compare_read_addr < PIN_LENGTH);

    always @(*) begin
        ref_digit = 4'd0;

        if ((PIN_LENGTH >= 1) &&
            (PIN_LENGTH <= 128) &&
            (compare_read_addr < PIN_LENGTH)) begin

            ref_digit = PIN_CODE >>
                ((PIN_LENGTH - 1 - compare_read_addr) * 4);
        end
    end


    // --------------------------------------------------------
    // 4. 鍵盤掃描
    // --------------------------------------------------------
    keypad_input #(
        .CLK_HZ(CLK_HZ)
    ) u_keypad (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_col      (i_col),
        .o_row      (o_row),
        .o_key_pulse(key_pulse),
        .o_key_code (key_code)
    );


    // --------------------------------------------------------
    // 5. 保存使用者輸入
    // --------------------------------------------------------
    pin_entry #(
        .MIN_DIGITS(6),
        .MAX_DIGITS(128)
    ) u_pin_entry (
        .i_clk         (i_clk),
        .i_rst         (i_rst),
        .i_clear       (pin_clear),
        .i_key_pulse   (key_pulse),
        .i_key_code    (key_code),
        .i_enable      (pin_enable),
        .i_read_addr   (pin_read_addr),

        .o_read_digit  (pin_read_digit),
        .o_read_valid  (pin_read_valid),
        .o_length      (pin_length),
        .o_submit_pulse(pin_submit_pulse),
        .o_submitted   (pin_submitted),
        .o_short_pulse (pin_short_pulse),
        .o_full        (pin_full)
    );


    // --------------------------------------------------------
    // 6. 密碼比對
    // --------------------------------------------------------
    pin_compare #(
        .MAX_DIGITS(128)
    ) u_pin_compare (
        .i_clk        (i_clk),
        .i_rst        (i_rst),
        .i_start      (compare_start),

        .i_pin_length (pin_length),
        .i_ref_length (ref_length),

        .i_pin_digit  (pin_read_digit),
        .i_pin_valid  (pin_read_valid),
        .i_ref_digit  (ref_digit),
        .i_ref_valid  (ref_valid),

        .o_read_addr  (compare_read_addr),
        .o_read_enable(compare_read_enable),
        .o_busy       (compare_busy),
        .o_done_pulse (compare_done),
        .o_match      (compare_match)
    );


    // --------------------------------------------------------
    // 7. 畫面內容
    // --------------------------------------------------------
    lcd_ui #(
        .CLK_HZ(CLK_HZ)
    ) u_lcd_ui (
        .i_clk            (i_clk),
        .i_rst            (i_rst),

        .i_pin_length     (pin_length),
        .o_pin_read_addr  (ui_read_addr),
        .i_pin_read_digit (pin_read_digit),
        .i_pin_read_valid (ui_read_valid),

        .i_digit_pulse    (digit_pulse),
        .i_toggle_pulse   (toggle_pulse),
        .i_hide_pulse     (hide_pulse),
        .i_status         (display_status),

        .i_lcd_ready      (lcd_ready),
        .i_lcd_done_pulse (lcd_done_pulse),
        .o_lcd_write_pulse(lcd_write_pulse),
        .o_lcd_rs         (lcd_write_rs),
        .o_lcd_data       (lcd_write_data),
        .o_brief_mode     (brief_mode)
    );


    // --------------------------------------------------------
    // 8. LCD 實體寫入時序
    // --------------------------------------------------------
    lcd_ctrl #(
        .CLK_HZ(CLK_HZ)
    ) u_lcd_ctrl (
        .i_clk        (i_clk),
        .i_rst        (i_rst),

        .i_write_pulse(lcd_write_pulse),
        .i_rs         (lcd_write_rs),
        .i_data       (lcd_write_data),

        .o_ready      (lcd_ready),
        .o_init_done  (lcd_init_done),
        .o_done_pulse (lcd_done_pulse),

        .o_lcd_rs     (o_lcd_rs),
        .o_lcd_e      (o_lcd_e),
        .o_lcd_data   (o_lcd_data)
    );


    // --------------------------------------------------------
    // 9. 暫時放在頂層的鎖定控制
    //    後續可移到 lock_ctrl，並接入 EEPROM 持久狀態
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            state          <= INPUT_PIN;
            display_status <= STATUS_INPUT;
            fail_count     <= 2'd0;
            timer_counter  <= 32'd0;
            pin_clear      <= 1'b0;
            o_unlock_pulse <= 1'b0;
            o_error_pulse  <= 1'b0;
        end
        else begin
            pin_clear      <= 1'b0;
            o_unlock_pulse <= 1'b0;
            o_error_pulse  <= 1'b0;

            case (state)
                INPUT_PIN: begin
                    timer_counter <= 32'd0;

                    // 位數不足只提示，不累積密碼錯誤
                    if (pin_short_pulse) begin
                        o_error_pulse <= 1'b1;
                    end

                    if (pin_submit_pulse) begin
                        display_status <= STATUS_CHECK;
                        state          <= CHECK_PIN;
                    end
                end

                CHECK_PIN: begin
                    if (compare_done) begin
                        pin_clear     <= 1'b1;
                        timer_counter <= 32'd0;

                        if (compare_match) begin
                            fail_count     <= 2'd0;
                            o_unlock_pulse <= 1'b1;
                            display_status <= STATUS_OPEN;
                            state          <= SHOW_RESULT;
                        end
                        else begin
                            o_error_pulse <= 1'b1;

                            if (fail_count == 2'd2) begin
                                // 第三次錯誤，開始鎖定
                                fail_count     <= 2'd3;
                                display_status <= STATUS_LOCKED;
                                state          <= LOCKED;
                            end
                            else begin
                                fail_count <= fail_count + 1'b1;
                                display_status <= STATUS_WRONG;
                                state <= SHOW_RESULT;
                            end
                        end
                    end
                end

                SHOW_RESULT: begin
                    // 顯示成功或失敗約兩秒
                    if (timer_counter >= RESULT_CYCLES - 1) begin
                        timer_counter  <= 32'd0;
                        display_status <= STATUS_INPUT;
                        state          <= INPUT_PIN;
                    end
                    else begin
                        timer_counter <= timer_counter + 1'b1;
                    end
                end

                LOCKED: begin
                    // 鎖定期間不接受 PIN 輸入
                    if (timer_counter >= LOCK_CYCLES - 1) begin
                        timer_counter  <= 32'd0;
                        fail_count     <= 2'd0;
                        pin_clear      <= 1'b1;
                        display_status <= STATUS_INPUT;
                        state          <= INPUT_PIN;
                    end
                    else begin
                        timer_counter <= timer_counter + 1'b1;
                    end
                end

                default: begin
                    // 非預期狀態保持鎖定
                    timer_counter  <= 32'd0;
                    pin_clear      <= 1'b1;
                    display_status <= STATUS_LOCKED;
                    state          <= LOCKED;
                end
            endcase
        end
    end

endmodule
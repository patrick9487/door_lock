module lcd_ui #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst,

    // pin_entry 的目前輸入長度
    input  wire [7:0] i_pin_length,

    // pin_entry 的非同步讀取介面
    output reg  [6:0] o_pin_read_addr,
    input  wire [3:0] i_pin_read_digit,
    input  wire       i_pin_read_valid,

    // 必須是「數字成功存入 pin_entry」的事件
    input  wire       i_digit_pulse,

    // B 鍵切換顯示模式
    input  wire       i_toggle_pulse,

    // 退格、取消、提交等事件，取消最新數字明文顯示
    input  wire       i_hide_pulse,

    // 狀態由上層控制模組提供
    input  wire [2:0] i_status,

    // 接到 lcd_ctrl
    input  wire       i_lcd_ready,
    input  wire       i_lcd_done_pulse,
    output reg        o_lcd_write_pulse,
    output reg        o_lcd_rs,
    output reg  [7:0] o_lcd_data,

    // 0：全部遮蔽；1：最新一位短暫顯示
    output reg        o_brief_mode
);

    localparam [2:0] STATUS_INPUT   = 3'd0;
    localparam [2:0] STATUS_CHECK   = 3'd1;
    localparam [2:0] STATUS_OPEN    = 3'd2;
    localparam [2:0] STATUS_WRONG   = 3'd3;
    localparam [2:0] STATUS_LOCKED  = 3'd4;
    localparam [2:0] STATUS_NEW_PIN = 3'd5;
    localparam [2:0] STATUS_CONFIRM = 3'd6;
    localparam [2:0] STATUS_SAVING  = 3'd7;

    localparam integer MS_CYCLES =
        (CLK_HZ + 999) / 1000;

    localparam integer REVEAL_CYCLES = MS_CYCLES * 800;
    localparam integer REFRESH_CYCLES = MS_CYCLES * 100;

    localparam [1:0] WAIT_REFRESH = 2'd0;
    localparam [1:0] SEND_ITEM    = 2'd1;
    localparam [1:0] WAIT_LCD     = 2'd2;

    reg [1:0]  state;
    reg [31:0] refresh_counter;
    reg [31:0] reveal_counter;

    // 一輪更新共 34 筆：
    // 0：第一行地址
    // 1～16：第一行文字
    // 17：第二行地址
    // 18～33：第二行文字
    reg [5:0] item_index;

    // 每輪更新開始時保存畫面資訊
    reg [7:0] length_snapshot;
    reg [2:0] status_snapshot;
    reg [7:0] window_start;

    reg [127:0] header_text;
    reg [7:0]   item_data;
    reg         item_rs;

    reg [7:0] digit_address;

    wire input_screen;
    wire reveal_active;

    assign input_screen =
        (status_snapshot == STATUS_INPUT) ||
        (status_snapshot == STATUS_NEW_PIN) ||
        (status_snapshot == STATUS_CONFIRM);

    assign reveal_active =
        o_brief_mode &&
        (reveal_counter != 32'd0) &&
        !i_hide_pulse &&
        !i_toggle_pulse;


    // --------------------------------------------------------
    // 1. 顯示模式與最新數字的明文計時
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            o_brief_mode  <= 1'b0;
            reveal_counter <= 32'd0;
        end
        else begin
            // 計時器每個 clock 遞減
            if (reveal_counter != 32'd0) begin
                reveal_counter <= reveal_counter - 1'b1;
            end

            if (i_toggle_pulse) begin
                o_brief_mode   <= !o_brief_mode;
                reveal_counter <= 32'd0;
            end
            else if (
                i_hide_pulse ||
                !((i_status == STATUS_INPUT) ||
                  (i_status == STATUS_NEW_PIN) ||
                  (i_status == STATUS_CONFIRM))
            ) begin
                reveal_counter <= 32'd0;
            end
            else if (i_digit_pulse && o_brief_mode) begin
                // 新數字成功存入後，重新計時
                reveal_counter <= REVEAL_CYCLES;
            end
        end
    end


    // --------------------------------------------------------
    // 2. 第一行狀態文字，每份固定 16 個字元
    // --------------------------------------------------------
    always @(*) begin
        case (status_snapshot)
            STATUS_INPUT:
                header_text = "ENTER PIN       ";
            STATUS_CHECK:
                header_text = "CHECKING...     ";
            STATUS_OPEN:
                header_text = "UNLOCKED        ";
            STATUS_WRONG:
                header_text = "WRONG PIN       ";
            STATUS_LOCKED:
                header_text = "LOCKED          ";
            STATUS_NEW_PIN:
                header_text = "NEW PIN         ";
            STATUS_CONFIRM:
                header_text = "CONFIRM PIN     ";
            STATUS_SAVING:
                header_text = "SAVING...       ";
            default:
                header_text = "                ";
        endcase
    end


    // --------------------------------------------------------
    // 3. 決定目前要傳送的指令或字元
    // --------------------------------------------------------
    always @(*) begin
        item_rs         = 1'b1;
        item_data       = 8'h20; // 空白
        digit_address   = 8'd0;
        o_pin_read_addr = 7'd0;

        if (item_index == 6'd0) begin
            item_rs   = 1'b0;
            item_data = 8'h80; // 第一行開頭
        end
        else if ((item_index >= 6'd1) &&
                 (item_index <= 6'd16)) begin
            // 從 128 bit 文字中取出目前的 ASCII 字元
            item_data = header_text >>
                        ((16 - item_index) * 8);
        end
        else if (item_index == 6'd17) begin
            item_rs   = 1'b0;
            item_data = 8'hC0; // 第二行開頭
        end
        else if ((item_index >= 6'd18) &&
                 (item_index <= 6'd33)) begin

            digit_address = window_start +
                            (item_index - 6'd18);

            o_pin_read_addr = digit_address[6:0];

            if (input_screen &&
                (digit_address < length_snapshot)) begin

                item_data = 8'h2A; // 星號 *

                // 只有最後一位可以短暫明文顯示
                // 長度改變時，先遮蔽，等待下一輪更新
                if (reveal_active &&
                    (i_pin_length == length_snapshot) &&
                    (i_status == status_snapshot) &&
                    (digit_address ==
                     (length_snapshot - 8'd1)) &&
                    i_pin_read_valid &&
                    (i_pin_read_digit <= 4'd9)) begin

                    item_data = 8'h30 +
                                {4'd0, i_pin_read_digit};
                end
            end
        end
    end


    // --------------------------------------------------------
    // 4. 依序把畫面送到 lcd_ctrl
    //    每筆都等待 lcd_ctrl 完成，才傳下一筆
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= WAIT_REFRESH;

            // 初始化完成後，可以立即開始第一輪更新
            refresh_counter <= REFRESH_CYCLES - 1;

            item_index      <= 6'd0;
            length_snapshot <= 8'd0;
            status_snapshot <= STATUS_INPUT;
            window_start    <= 8'd0;

            o_lcd_write_pulse <= 1'b0;
            o_lcd_rs          <= 1'b0;
            o_lcd_data        <= 8'd0;
        end
        else begin
            o_lcd_write_pulse <= 1'b0;

            case (state)
                WAIT_REFRESH: begin
                    if (refresh_counter >=
                        REFRESH_CYCLES - 1) begin

                        if (i_lcd_ready) begin
                            refresh_counter <= 32'd0;
                            item_index      <= 6'd0;

                            length_snapshot <= i_pin_length;
                            status_snapshot <= i_status;

                            // 超過 16 位，視窗移到最後 16 位
                            if (i_pin_length > 8'd16) begin
                                window_start <=
                                    i_pin_length - 8'd16;
                            end
                            else begin
                                window_start <= 8'd0;
                            end

                            state <= SEND_ITEM;
                        end
                    end
                    else begin
                        refresh_counter <=
                            refresh_counter + 1'b1;
                    end
                end

                SEND_ITEM: begin
                    if (i_lcd_ready) begin
                        o_lcd_rs          <= item_rs;
                        o_lcd_data        <= item_data;
                        o_lcd_write_pulse <= 1'b1;
                        state             <= WAIT_LCD;
                    end
                end

                WAIT_LCD: begin
                    if (i_lcd_done_pulse) begin
                        if (item_index == 6'd33) begin
                            refresh_counter <= 32'd0;
                            state           <= WAIT_REFRESH;
                        end
                        else begin
                            item_index <= item_index + 1'b1;
                            state      <= SEND_ITEM;
                        end
                    end
                end

                default: begin
                    state             <= WAIT_REFRESH;
                    refresh_counter   <= 32'd0;
                    o_lcd_write_pulse <= 1'b0;
                end
            endcase
        end
    end

endmodule
module lcd_ctrl #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst,

    // o_ready 為 1 時，可送出一次寫入
    input  wire       i_write_pulse,
    input  wire       i_rs,          // 0：指令，1：字元
    input  wire [7:0] i_data,

    output wire       o_ready,
    output reg        o_init_done,
    output reg        o_done_pulse,

    // LCD 實體腳位；RW 直接接地
    output reg        o_lcd_rs,
    output reg        o_lcd_e,
    output reg  [3:0] o_lcd_data     // [3:0] 對應 D7～D4
);

    // 常數在編譯時計算，不會產生除法器
    // 要求 CLK_HZ >= 1000
    localparam integer US_CYCLES =
        (CLK_HZ + 999_999) / 1_000_000;

    localparam integer MS_CYCLES =
        (CLK_HZ + 999) / 1000;

    localparam integer POWER_CYCLES = MS_CYCLES * 50;
    localparam integer FIRST_CYCLES = MS_CYCLES * 5;
    localparam integer EXEC_CYCLES  = MS_CYCLES * 3;

    localparam [2:0] POWER_WAIT = 3'd0;
    localparam [2:0] INIT_LOAD  = 3'd1;
    localparam [2:0] SETUP      = 3'd2;
    localparam [2:0] E_HIGH     = 3'd3;
    localparam [2:0] HOLD       = 3'd4;
    localparam [2:0] EXEC_WAIT  = 3'd5;
    localparam [2:0] IDLE       = 3'd6;

    reg [2:0]  state;
    reg [31:0] counter;
    reg [31:0] wait_cycles;

    reg [3:0] init_step;
    reg       init_active;

    reg [7:0] tx_data;
    reg       single_nibble;
    reg       low_nibble;

    assign o_ready =
        !i_rst && o_init_done && (state == IDLE);


    // 前四步只傳高四位：3、3、3、2
    // 後面才以兩次四位傳輸組成完整指令
    function [7:0] init_command;
        input [3:0] step;
        begin
            case (step)
                4'd0: init_command = 8'h30;
                4'd1: init_command = 8'h30;
                4'd2: init_command = 8'h30;
                4'd3: init_command = 8'h20;

                4'd4: init_command = 8'h28; // 4 bit、雙行、5x8
                4'd5: init_command = 8'h08; // 暫時關閉顯示
                4'd6: init_command = 8'h01; // 清除畫面
                4'd7: init_command = 8'h06; // 寫入後地址加一
                4'd8: init_command = 8'h0C; // 顯示開、游標關

                default: init_command = 8'h00;
            endcase
        end
    endfunction


    always @(posedge i_clk) begin
        if (i_rst) begin
            state         <= POWER_WAIT;
            counter       <= 32'd0;
            wait_cycles   <= 32'd0;

            init_step     <= 4'd0;
            init_active   <= 1'b1;

            tx_data       <= 8'd0;
            single_nibble <= 1'b0;
            low_nibble    <= 1'b0;

            o_init_done   <= 1'b0;
            o_done_pulse  <= 1'b0;

            o_lcd_rs      <= 1'b0;
            o_lcd_e       <= 1'b0;
            o_lcd_data    <= 4'd0;
        end
        else begin
            o_done_pulse <= 1'b0;

            case (state)

                // 上電或 reset 後，先等待約 50 ms
                POWER_WAIT: begin
                    if (counter >= POWER_CYCLES - 1) begin
                        counter <= 32'd0;
                        state   <= INIT_LOAD;
                    end
                    else begin
                        counter <= counter + 1'b1;
                    end
                end

                // 準備下一個初始化指令
                INIT_LOAD: begin
                    tx_data <= init_command(init_step);

                    // 先輸出高四位
                    o_lcd_data <= init_command(init_step) >> 4;
                    o_lcd_rs   <= 1'b0;
                    o_lcd_e    <= 1'b0;

                    single_nibble <= (init_step < 4'd4);
                    low_nibble    <= 1'b0;

                    // 第一次送 3 後等待 5 ms，其餘等待 3 ms
                    if (init_step == 4'd0) begin
                        wait_cycles <= FIRST_CYCLES;
                    end
                    else begin
                        wait_cycles <= EXEC_CYCLES;
                    end

                    counter <= 32'd0;
                    state   <= SETUP;
                end

                // RS 和資料先穩定約 1 us，再將 E 拉高
                SETUP: begin
                    if (counter >= US_CYCLES - 1) begin
                        o_lcd_e <= 1'b1;
                        counter <= 32'd0;
                        state   <= E_HIGH;
                    end
                    else begin
                        counter <= counter + 1'b1;
                    end
                end

                // E 高電位維持約 1 us
                // LCD 在 E 下降緣接收這四個 bit
                E_HIGH: begin
                    if (counter >= US_CYCLES - 1) begin
                        o_lcd_e <= 1'b0;
                        counter <= 32'd0;
                        state   <= HOLD;
                    end
                    else begin
                        counter <= counter + 1'b1;
                    end
                end

                // E 拉低後，資料再保持約 1 us
                HOLD: begin
                    if (counter >= US_CYCLES - 1) begin
                        counter <= 32'd0;

                        if (!single_nibble && !low_nibble) begin
                            // 高四位送完，接著送低四位
                            o_lcd_data <= tx_data[3:0];
                            low_nibble <= 1'b1;
                            state      <= SETUP;
                        end
                        else begin
                            // 整筆傳輸完成，等待 LCD 執行
                            state <= EXEC_WAIT;
                        end
                    end
                    else begin
                        counter <= counter + 1'b1;
                    end
                end

                // 不讀 busy flag，改用固定等待時間
                EXEC_WAIT: begin
                    if (counter >= wait_cycles - 1) begin
                        counter <= 32'd0;

                        if (init_active) begin
                            if (init_step == 4'd8) begin
                                init_active <= 1'b0;
                                o_init_done <= 1'b1;
                                state       <= IDLE;
                            end
                            else begin
                                init_step <= init_step + 1'b1;
                                state     <= INIT_LOAD;
                            end
                        end
                        else begin
                            o_done_pulse <= 1'b1;
                            state        <= IDLE;
                        end
                    end
                    else begin
                        counter <= counter + 1'b1;
                    end
                end

                // 接受上層送來的指令或字元
                IDLE: begin
                    if (i_write_pulse) begin
                        tx_data    <= i_data;
                        o_lcd_rs   <= i_rs;
                        o_lcd_data <= i_data[7:4];
                        o_lcd_e    <= 1'b0;

                        single_nibble <= 1'b0;
                        low_nibble    <= 1'b0;
                        wait_cycles   <= EXEC_CYCLES;

                        counter <= 32'd0;
                        state   <= SETUP;
                    end
                end

                default: begin
                    // 非預期狀態：重新初始化
                    state       <= POWER_WAIT;
                    counter     <= 32'd0;
                    init_step   <= 4'd0;
                    init_active <= 1'b1;
                    o_init_done <= 1'b0;
                    o_lcd_rs    <= 1'b0;
                    o_lcd_e     <= 1'b0;
                    o_lcd_data  <= 4'd0;
                end

            endcase
        end
    end

endmodule
module keypad_input #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire [3:0] i_col,

    output reg  [3:0] o_row,
    output reg        o_key_pulse,
    output reg  [4:0] o_key_code
);

    // 每條 row 停留約 1 ms；CLK_HZ 必須至少為 1000
    localparam integer SCAN_CYCLES = CLK_HZ / 1000;

    localparam WAIT_PRESS   = 1'b0;
    localparam WAIT_RELEASE = 1'b1;

    // 掃描計時與目前排號
    reg [31:0] scan_counter;
    reg        scan_tick;
    reg [1:0]  scan_row;

    // 外部 column 輸入的兩級同步器
    reg [3:0] col_meta;
    reg [3:0] col_sync;

    // 原始掃描結果：每個 bit 對應一顆按鍵，1 表示按下
    reg [15:0] key_bitmap;
    reg        frame_done;

    // 去抖動：確認同一份結果連續出現五輪
    reg [15:0] candidate_bitmap;
    reg [2:0]  stable_count;
    reg [15:0] stable_bitmap;
    reg        stable_pulse;

    // 單鍵解碼結果
    reg       single_key_valid;
    reg [4:0] decoded_key_code;

    // 按下／等待放開的狀態
    reg key_state;


    // --------------------------------------------------------
    // 1. 計時器：每隔約 1 ms 產生一個 clock 寬的 scan_tick
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            scan_counter <= 32'd0;
            scan_tick    <= 1'b0;
        end
        else begin
            scan_tick <= 1'b0;

            if (scan_counter >= SCAN_CYCLES - 1) begin
                scan_counter <= 32'd0;
                scan_tick    <= 1'b1;
            end
            else begin
                scan_counter <= scan_counter + 1'b1;
            end
        end
    end


    // --------------------------------------------------------
    // 2. 排號：每次 scan_tick 切換下一排
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            scan_row <= 2'd0;
        end
        else if (scan_tick) begin
            if (scan_row == 2'd3) begin
                scan_row <= 2'd0;
            end
            else begin
                scan_row <= scan_row + 1'b1;
            end
        end
    end


    // --------------------------------------------------------
    // 3. Row 輸出：選中的排拉低，其餘保持高阻抗
    //    reset 期間全部保持高阻抗
    // --------------------------------------------------------
    always @(*) begin
        o_row = 4'bzzzz;

        if (!i_rst) begin
            case (scan_row)
                2'd0: o_row = 4'bzzz0;
                2'd1: o_row = 4'bzz0z;
                2'd2: o_row = 4'bz0zz;
                2'd3: o_row = 4'b0zzz;
                default: o_row = 4'bzzzz;
            endcase
        end
    end


    // --------------------------------------------------------
    // 4. Column 同步：每個 clock 都更新，不受 scan_tick 限制
    //    column 有上拉，因此 1 表示未按下
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            col_meta <= 4'b1111;
            col_sync <= 4'b1111;
        end
        else begin
            col_meta <= i_col;
            col_sync <= col_meta;
        end
    end


    // --------------------------------------------------------
    // 5. 收集掃描結果
    //    與排號區塊讀取相同的舊 scan_row：
    //    保存目前排的結果，再切換下一排
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            key_bitmap <= 16'd0;
            frame_done <= 1'b0;
        end
        else begin
            frame_done <= 1'b0;

            if (scan_tick) begin
                case (scan_row)
                    2'd0: begin
                        key_bitmap[3:0] <= ~col_sync;
                    end

                    2'd1: begin
                        key_bitmap[7:4] <= ~col_sync;
                    end

                    2'd2: begin
                        key_bitmap[11:8] <= ~col_sync;
                    end

                    2'd3: begin
                        key_bitmap[15:12] <= ~col_sync;
                        frame_done       <= 1'b1;
                    end
                endcase
            end
        end
    end


    // --------------------------------------------------------
    // 6. 去抖動：每完成一輪掃描才比較一次
    //    第五輪相同時保存結果，並產生 stable_pulse
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            candidate_bitmap <= 16'd0;
            stable_count     <= 3'd0;
            stable_bitmap    <= 16'd0;
            stable_pulse     <= 1'b0;
        end
        else begin
            stable_pulse <= 1'b0;

            if (frame_done) begin
                if (key_bitmap != candidate_bitmap) begin
                    // 換成新候選，重新從第一輪開始
                    candidate_bitmap <= key_bitmap;
                    stable_count     <= 3'd1;
                end
                else if (stable_count < 3'd5) begin
                    // 相同結果累積到五輪後停止計數
                    stable_count <= stable_count + 1'b1;

                    if (stable_count == 3'd4) begin
                        stable_bitmap <= key_bitmap;
                        stable_pulse  <= 1'b1;
                    end
                end
            end
        end
    end


    // --------------------------------------------------------
    // 7. 單鍵解碼：只有恰好一個 bit 為 1 才有效
    //
    // 實體排列：
    // row0：1、2、3、*（退格）
    // row1：4、5、6、D（取消）
    // row2：7、8、9、B（顯示切換）
    // row3：C（保留）、0、#（確認）、A（修改密碼）
    // --------------------------------------------------------
    always @(*) begin
        single_key_valid = 1'b1;
        decoded_key_code = 5'd0;

        case (stable_bitmap)
            16'h0001: decoded_key_code = 5'd1;
            16'h0002: decoded_key_code = 5'd2;
            16'h0004: decoded_key_code = 5'd3;
            16'h0008: decoded_key_code = 5'd11; // *

            16'h0010: decoded_key_code = 5'd4;
            16'h0020: decoded_key_code = 5'd5;
            16'h0040: decoded_key_code = 5'd6;
            16'h0080: decoded_key_code = 5'd12; // D

            16'h0100: decoded_key_code = 5'd7;
            16'h0200: decoded_key_code = 5'd8;
            16'h0400: decoded_key_code = 5'd9;
            16'h0800: decoded_key_code = 5'd14; // B

            16'h1000: decoded_key_code = 5'd15; // C
            16'h2000: decoded_key_code = 5'd0;
            16'h4000: decoded_key_code = 5'd10; // #
            16'h8000: decoded_key_code = 5'd13; // A

            default: begin
                // 全部放開或多鍵同時按下
                single_key_valid = 1'b0;
            end
        endcase
    end


    // --------------------------------------------------------
    // 8. 事件輸出：一次按下只輸出一次
    //    單鍵或多鍵之後，都必須確認全部放開才能再輸入
    // --------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            key_state   <= WAIT_PRESS;
            o_key_code  <= 5'd0;
            o_key_pulse <= 1'b0;
        end
        else begin
            o_key_pulse <= 1'b0;

            if (stable_pulse) begin
                case (key_state)
                    WAIT_PRESS: begin
                        if (stable_bitmap != 16'd0) begin
                            if (single_key_valid) begin
                                o_key_code  <= decoded_key_code;
                                o_key_pulse <= 1'b1;
                            end

                            key_state <= WAIT_RELEASE;
                        end
                    end

                    WAIT_RELEASE: begin
                        if (stable_bitmap == 16'd0) begin
                            key_state <= WAIT_PRESS;
                        end
                    end

                    default: begin
                        key_state <= WAIT_PRESS;
                    end
                endcase
            end
        end
    end

endmodule
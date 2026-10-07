module pin_compare #(
    parameter integer MAX_DIGITS = 128
)(
    input  wire       i_clk,
    input  wire       i_rst,

    // 開始比對：高一個 clock；忙碌時忽略
    input  wire       i_start,

    // 輸入密碼與參考密碼的長度
    input  wire [7:0] i_pin_length,
    input  wire [7:0] i_ref_length,

    // 目前讀取地址所對應的數字
    input  wire [3:0] i_pin_digit,
    input  wire       i_pin_valid,
    input  wire [3:0] i_ref_digit,
    input  wire       i_ref_valid,

    // 兩邊共用同一個讀取地址
    output reg  [6:0] o_read_addr,
    output wire       o_read_enable,

    output wire       o_busy,
    output reg        o_done_pulse,
    output reg        o_match
);

    localparam [1:0] IDLE         = 2'd0;
    localparam [1:0] CHECK_LENGTH = 2'd1;
    localparam [1:0] COMPARE      = 2'd2;

    reg [1:0] state;
    reg [7:0] pin_length;
    reg [7:0] ref_length;

    assign o_busy        = (state != IDLE);
    assign o_read_enable = (state == COMPARE);

    always @(posedge i_clk) begin
        if (i_rst) begin
            state        <= IDLE;
            pin_length   <= 8'd0;
            ref_length   <= 8'd0;
            o_read_addr  <= 7'd0;
            o_done_pulse <= 1'b0;
            o_match      <= 1'b0;
        end
        else begin
            // 完成通知只維持一個 clock
            o_done_pulse <= 1'b0;

            case (state)
                IDLE: begin
                    if (i_start) begin
                        // 保存本次比對的長度
                        pin_length  <= i_pin_length;
                        ref_length  <= i_ref_length;
                        o_read_addr <= 7'd0;
                        o_match     <= 1'b0;
                        state       <= CHECK_LENGTH;
                    end
                end

                CHECK_LENGTH: begin
                    // 空密碼、超過容量或長度不同，直接失敗
                    if ((pin_length == 8'd0) ||
                        (pin_length > MAX_DIGITS) ||
                        (ref_length > MAX_DIGITS) ||
                        (pin_length != ref_length)) begin

                        o_match      <= 1'b0;
                        o_done_pulse <= 1'b1;
                        state        <= IDLE;
                    end
                    else begin
                        state <= COMPARE;
                    end
                end

                COMPARE: begin
                    // 等待兩邊目前地址的資料都有效
                    if (i_pin_valid && i_ref_valid) begin
                        if (i_pin_digit != i_ref_digit) begin
                            // 任一位不同，比對失敗
                            o_match      <= 1'b0;
                            o_done_pulse <= 1'b1;
                            state        <= IDLE;
                        end
                        else if (
                            {1'b0, o_read_addr} ==
                            (pin_length - 8'd1)
                        ) begin
                            // 最後一位也相同，比對成功
                            o_match      <= 1'b1;
                            o_done_pulse <= 1'b1;
                            state        <= IDLE;
                        end
                        else begin
                            // 目前這位相同，繼續下一位
                            o_read_addr <= o_read_addr + 1'b1;
                        end
                    end
                end

                default: begin
                    state   <= IDLE;
                    o_match <= 1'b0;
                end
            endcase
        end
    end

endmodule
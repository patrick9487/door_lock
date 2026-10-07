module pin_entry #(
    parameter MIN_DIGITS = 6,
    parameter MAX_DIGITS = 128
)(
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire       i_clear,
    input  wire       i_key_pulse,
    input  wire [4:0] i_key_code,
    input  wire       i_enable,
    input  wire [6:0] i_read_addr,

    output reg  [3:0] o_read_digit,
    output reg        o_read_valid,
    output wire [7:0] o_length,
    output reg        o_submit_pulse,
    output wire       o_submitted,
    output reg        o_short_pulse,
    output wire       o_full
);

    localparam [4:0] KEY_ENTER     = 5'd10;
    localparam [4:0] KEY_BACKSPACE = 5'd11;
    localparam [4:0] KEY_CANCEL    = 5'd12;

    reg [3:0] digits [0:MAX_DIGITS-1];
    reg [7:0] length;
    reg       submitted;

    always @(posedge i_clk) begin
        // 每個週期先把事件訊號歸零
        o_submit_pulse <= 1'b0;
        o_short_pulse  <= 1'b0;

        if (i_rst) begin
            length    <= 8'd0;
            submitted <= 1'b0;
        end
        else if (i_clear) begin
            length    <= 8'd0;
            submitted <= 1'b0;
        end
        else if (i_enable && !submitted && i_key_pulse) begin
            if (i_key_code <= 5'd9) begin
                // 未滿：存入數字，長度加一
                if (length < MAX_DIGITS) begin
                    digits[length] <= i_key_code[3:0];
                    length         <= length + 1'b1;
                end
            end
            else begin
                case (i_key_code)
                    KEY_BACKSPACE: begin
                        // 非空：長度減一
                        if (length > 0) begin
                            length <= length - 1'b1;
                        end
                    end

                    KEY_CANCEL: begin
                        length    <= 8'd0;
                        submitted <= 1'b0;
                    end

                    KEY_ENTER: begin
                        if (length >= MIN_DIGITS) begin
                            // 位數足夠：提交並凍結輸入
                            o_submit_pulse <= 1'b1;
                            submitted      <= 1'b1;
                        end
                        else begin
                            // 位數不足：發出通知
                            o_short_pulse <= 1'b1;
                        end
                    end

                    default: begin
                        // 其他按鍵不處理
                    end
                endcase
            end
        end
    end

    assign o_length    = length;
    assign o_submitted = submitted;
    assign o_full      = (length >= MAX_DIGITS);

    always @(*) begin
        o_read_digit = 4'd0;
        o_read_valid = 1'b0;

        if ((i_read_addr < MAX_DIGITS) &&
            (i_read_addr < length)) begin
            o_read_digit = digits[i_read_addr];
            o_read_valid = 1'b1;
        end
    end

endmodule
`timescale 1ns/1ps
module tb_lcd_privacy;
reg clk=0,rst=1,toggle=0,digit=0,hide=0;
always #5 clk=~clk;
wire ready,done,wr,rs,brief,init,e,lrs;
wire [7:0] data;
wire [3:0] ld;
integer cycles=0,addr=0,shown=-1,hide_cycle;
reg [7:0] length=1;
reg [2:0] status=0;
reg half=0;
reg [3:0] hi;
reg [7:0] value;
lcd_ui #(.CLK_HZ(1000000)) ui(.i_clk(clk),.i_rst(rst),.i_pin_length(length),.i_pin_read_digit(4'd7),.i_pin_read_valid(1'b1),.i_digit_pulse(digit),.i_toggle_pulse(toggle),.i_hide_pulse(hide),.i_status(status),.i_lcd_ready(ready),.i_lcd_done_pulse(done),.o_lcd_write_pulse(wr),.o_lcd_rs(rs),.o_lcd_data(data),.o_brief_mode(brief));
lcd_ctrl #(.CLK_HZ(1000000)) ctrl(.i_clk(clk),.i_rst(rst),.i_write_pulse(wr),.i_rs(rs),.i_data(data),.o_ready(ready),.o_init_done(init),.o_done_pulse(done),.o_lcd_rs(lrs),.o_lcd_e(e),.o_lcd_data(ld));
always @(posedge clk) cycles=cycles+1;
always @(negedge e) if(init) begin
 if(!half) begin hi=ld;half=1;end
 else begin
  value={hi,ld};half=0;
  if(!lrs && value[7]) addr=value & 127;
  else if(lrs) begin if(addr==64) shown=value;addr=addr+1;end
 end
end
initial begin
 repeat(4) @(negedge clk);rst=0;toggle=1;
 @(negedge clk);toggle=0;digit=1;
 @(negedge clk);digit=0;
 wait(shown==8'h37);
 @(negedge clk);hide=1;hide_cycle=cycles;
 @(negedge clk);hide=0;
 wait(shown==8'h2a);
 if(cycles-hide_cycle>10000) $fatal(1,"hide latency exceeds 10 ms");
 $display("PASS: hide overwrites plaintext in %0d us", cycles-hide_cycle);
 // Reveal once more, then let the 800 ms timer expire naturally.
 @(negedge clk);digit=1;
 @(negedge clk);digit=0;
 wait(shown==8'h37);
 wait(ui.reveal_counter==0);hide_cycle=cycles;
 wait(shown==8'h2a);
 if(cycles-hide_cycle>10000) $fatal(1,"expiry latency exceeds 10 ms");
 $display("PASS: expiry overwrites plaintext in %0d us", cycles-hide_cycle);
 // Cancel while a digit is physically visible.
 @(negedge clk);digit=1;
 @(negedge clk);digit=0;
 wait(shown==8'h37);
 @(negedge clk);hide=1;length=0;hide_cycle=cycles;
 @(negedge clk);hide=0;
 wait(shown==8'h20);
 if(cycles-hide_cycle>10000) $fatal(1,"cancel latency exceeds 10 ms");
 $display("PASS: cancel clears plaintext in %0d us", cycles-hide_cycle);
 $finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule

`timescale 1ns/1ps
module tb_lcd_timing;
reg clk=0,rst=1,write=0,rs=0;
reg [7:0] data=0;
wire ready,done;
integer cycle=0,started;
always #500 clk=~clk; // 1 MHz; cycles measure microseconds.
always @(posedge clk) cycle=cycle+1;
lcd_ctrl #(.CLK_HZ(1000000)) dut(.i_clk(clk),.i_rst(rst),.i_write_pulse(write),.i_rs(rs),.i_data(data),.o_ready(ready),.o_done_pulse(done));
task send(input bit is_data,input [7:0] value,input integer minimum,input integer maximum);
begin
 wait(ready);
 @(negedge clk);rs=is_data;data=value;write=1;started=cycle;
 @(negedge clk);write=0;
 wait(done);
 if(cycle-started<minimum || cycle-started>maximum)
 $fatal(1,"bad execution interval for RS=%b data=%h: %0d us",is_data,value,cycle-started);
 @(negedge clk);
end endtask
initial begin
 repeat(4) @(negedge clk);rst=0;
 send(0,8'h80,100,120);
 send(1,8'h41,100,120);
 send(1,8'h01,100,120); // Character code 1 is not a clear instruction.
 send(0,8'h01,3000,3020);
 send(0,8'h02,3000,3020);
 send(0,8'h03,3000,3020); // Home instruction's low bit is don't-care.
 $display("PASS: normal writes wait >=100 us; clear/home wait >=3 ms");$finish;
end
initial begin #150000000;$fatal(1,"timing test timeout");end
endmodule

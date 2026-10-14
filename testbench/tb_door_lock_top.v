`timescale 1ns/1ps
module tb_door_lock_top;
reg clk=0, rst=0;
always #5 clk=~clk;
reg [15:0] pressed=0;
wire [3:0] row;
reg [3:0] col;
integer r,c,unlocks=0,errors=0;
wire unlock,error,locked;
door_lock_top #(.CLK_HZ(10000)) dut(.i_clk(clk),.i_rst(rst),.i_col(col),.o_row(row),.o_unlock_pulse(unlock),.o_error_pulse(error),.o_locked(locked));
always @* begin
 col=15;
 for(integer a=0;a<4;a=a+1) for(integer b=0;b<4;b=b+1)
 if(row[a]===1'b0 && pressed[a*4+b]) col[b]=0;
end
always @(posedge clk) begin
 if(unlock) unlocks=unlocks+1;
 if(error) errors=errors+1;
end
task key(input integer bitnum); begin
 @(negedge clk); pressed=16'b1<<bitnum;
 repeat(320) @(negedge clk);
 pressed=0; repeat(320) @(negedge clk);
end endtask
task pin(input integer last); begin
 key(0);key(1);key(2);key(4);key(5);key(last);key(14);
end endtask
initial begin
 repeat(4) @(negedge clk);rst=1;
 wait(!dut.reset_active);
 key(0);key(1);key(2);key(4);key(5);key(14);
 if(dut.pin_length!=5 || dut.state!=0 || dut.fail_count!=0 || errors!=1)
 $fatal(1,"five digits must be rejected without consuming a comparison attempt");
 key(7); // Cancel.
 pin(6);
 if(unlocks!=1 || errors!=1) $fatal(1,"correct PIN failed");
 wait(dut.state==0);
 repeat(3) begin pin(5); if(!locked) wait(dut.state==0); end
 if(!locked || errors!=4) $fatal(1,"three failures did not lock");
 pin(6); if(unlocks!=1) $fatal(1,"input accepted during lockout");
 wait(!locked); repeat(2) @(negedge clk);pin(6);
 if(unlocks!=2) $fatal(1,"correct PIN after lockout failed");
 $display("PASS: top correct/wrong PIN, third-failure lockout, ignored input, recovery");$finish;
end
initial begin #10000000; $fatal(1,"timeout"); end
endmodule

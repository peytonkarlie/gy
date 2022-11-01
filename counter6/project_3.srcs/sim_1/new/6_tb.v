//模6计数器的测试文件
`timescale 1ns/1ps
module counter6_tb;
 
reg clk, rst_n, en;
wire[3:0] dout;
wire co;
 
//时钟设计周期为2ns
always
begin
	#1 clk = ~clk;
end
 
//初始化
initial
begin
	clk = 1'b0;
	rst_n = 1'b1;
	en = 1'b0;
	#2 rst_n = 1'b0;
	#2 rst_n = 1'b1; en = 1'b1;    //计数使能信号有效，且不复位
	
 
end
 
counter6 u1(.clk(clk), .rst_n(rst_n), .en(en), .dout(dout), .co(co));
 
endmodule
 
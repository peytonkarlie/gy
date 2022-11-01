`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/10/30 18:01:32
// Design Name: 
// Module Name: led_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module led_tb( );
 reg [7:0] switch;
 wire [7:0] led;
 led uut(
     .switch(switch),
     .led   (led  )
     );
     initial begin
         switch=8'h0;
         #100;
     end
     always #10 begin
            switch=($random)%256;
      end
endmodule

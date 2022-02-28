`timescale 1ns / 1ps


// pipelined interger multiplier
module int_mult (
    clk,
    A,
    B,
    RES
);
  parameter WIDTHA = 17;
  parameter WIDTHB = 17;
  parameter dm = 4;  // latency of the pipelined multiplier
  input clk;
  input [WIDTHA-1:0] A;
  input [WIDTHB-1:0] B;
  output [WIDTHA+WIDTHB-1:0] RES;

  reg [WIDTHA-1:0] rA;
  reg [WIDTHB-1:0] rB;
  wire [WIDTHA+WIDTHB-1:0] m_result;
  reg [WIDTHA+WIDTHB-1:0] M[dm-2:0];


  assign m_result = rA * rB;


  integer i;
  always @(posedge clk) begin
    rA   <= A;
    rB   <= B;
    M[0] <= m_result;
    for (i = 0; i < dm - 2; i = i + 1) M[i+1] <= M[i];
  end
  assign RES = M[dm-2];
endmodule

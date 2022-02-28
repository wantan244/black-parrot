`timescale 1ns / 1ps


// Butterfly unit and ALU
module seq (
    clk,
    in0,
    in1,
    mode,
    out0,
    out1
);
  parameter logq = 17;
  localparam seq_delay = 1;

  input clk;
  input [logq-1:0] in0;
  input [logq-1:0] in1;
  input mode;
  output reg [logq-1:0] out0;
  output reg [logq-1:0] out1;

  reg [logq-1:0] reg1, reg0;

  reg [logq-1:0] mux_a, mux_b;
  reg sa, sb;

  always @(*) begin
    // decode
    casez (mode)
      // Read from both banks or read from bank0
      1'b0: begin
        {sa, sb} = 2'b0_1;
      end
      // both from bank 1
      1'b1: begin
        {sa, sb} = 2'b1_0;
      end
    endcase

    //muxes
    mux_a = sa ? reg1 : in0;
    mux_b = sb ? reg1 : in0;

    out0  = reg0;
    out1  = mux_b;
  end

  // 3 registers
  always @(posedge clk) begin
    reg1 <= in1;
    reg0 <= mux_a;
  end

endmodule

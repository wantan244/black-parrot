`timescale 1ns / 1ps

// Polynominal adder. 
// Computes modulo addition, adding a pair of element per clock.
// Fixed latency = 1 clk. 
// Using FIFO-like ports.
module polynomial_adder #(
    parameter q = 17,
    parameter N = 8,
    parameter logq = 5,
    parameter logN = 3
) (
    input wire clk,
    input wire reset_n,

    // connection with previous module (input side)
    input wire in0_valid,
    input wire in1_valid,
    input wire [logq-1:0] poly_in0,
    input wire [logq-1:0] poly_in1,
    output wire in_ready,  // whether the module is ready to consume the input.

    // connection with next stage (output side)
    output reg             out_valid,  // if output is valid
    output reg  [logq-1:0] poly_out,
    input  wire            out_ready   // if the next stage is ready to consume the output
);

  assign in_valid = in0_valid && in1_valid;
  assign in_ready = in_valid && (out_ready || (!out_valid));

  // input -> (COMB) -> poly_out
  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      poly_out  <= 0;
      out_valid <= 0;
    end else begin
      if (in_valid && in_ready) begin
        poly_out  <= (poly_in0 + poly_in1) < q ? (poly_in0 + poly_in1) : (poly_in0 + poly_in1) - q;
        out_valid <= 1;
      end else if (out_ready) begin
        out_valid <= 0;
      end
    end
  end
endmodule

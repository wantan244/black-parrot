`timescale 1ns / 1ps


// multiply and reduce
module mul_red (
    clk,
    a,
    b,
    r,
    q,
    out
);
  parameter logq = 17;
  parameter dm = 5;  // latency of the pipelined multiplier
  localparam total_delay = 3 * dm + 1;

  input clk;
  input [logq-1:0] a;
  input [logq-1:0] b;
  input [logq-1:0] q;
  input [(logq+1)-1:0] r;
  output reg [logq-1:0] out;

  reg [(logq+1)-1:0] r_delay[dm-1:0];
  wire [(logq+1)-1:0] r_delayed;

  reg [logq-1:0] q_delay[3*dm-1:0];
  wire [logq-1:0] q_delayed1, q_delayed2;

  wire [logq*2-1:0] ab;
  reg [logq*2-1:0] ab_delay[2*dm-1:0];
  wire [logq*2-1:0] ab_delayed;

  wire [(logq*3+1)-1:0] abr;
  wire [(logq*2+1)-1:0] abrq;
  wire [(logq*2+1)-1:0] sub1;
  wire [(logq+1)-1:0] sub2;
  wire [logq-1:0] final_result;



  int_mult #(
      .WIDTHA(logq),
      .WIDTHB(logq),
      .dm(dm)
  ) mult_a_b (
      .clk(clk),
      .A  (a),
      .B  (b),
      .RES(ab)
  );
  int_mult #(
      .WIDTHA(logq * 2),
      .WIDTHB(logq + 1),
      .dm(dm)
  ) mult_ab_r (
      .clk(clk),
      .A  (ab),
      .B  (r_delayed),
      .RES(abr)
  );
  int_mult #(
      .WIDTHA(logq + 1),
      .WIDTHB(logq),
      .dm(dm)
  ) mult_abr_q (
      .clk(clk),
      .A  (abr[(logq*3+1)-1 : logq*2]),
      .B  (q_delayed1),
      .RES(abrq)
  );


  integer i;
  always @(posedge clk) begin
    //delay r_shift
    r_delay[0] <= r;
    for (i = 0; i < dm - 1; i = i + 1) r_delay[i+1] <= r_delay[i];

    //delay q
    q_delay[0] <= q;
    for (i = 0; i < 3 * dm - 1; i = i + 1) q_delay[i+1] <= q_delay[i];

    //delay ab
    ab_delay[0] <= ab;
    for (i = 0; i < 2 * dm - 1; i = i + 1) ab_delay[i+1] <= ab_delay[i];

    //register final result
    out <= final_result;
  end
  assign r_delayed = r_delay[dm-1];
  assign q_delayed1 = q_delay[2*dm-1];
  assign q_delayed2 = q_delay[3*dm-1];
  assign ab_delayed = ab_delay[2*dm-1];

  assign sub1 = ab_delayed - abrq;
  assign sub2 = sub1 - q_delayed2;
  assign final_result = (sub1 >= q_delayed2) ? sub2 : sub1;



endmodule


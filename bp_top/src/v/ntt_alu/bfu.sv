`timescale 1ns / 1ps


// Butterfly unit and ALU
module bfu (
    clk,
    u,
    v,
    w,
    mode,
    q,
    r,
    out0,
    out1
);
  parameter logq = 17;
  parameter dm = 4;  // latency of the pipelined multiplier
  localparam mul_red_delay = 3 * dm + 1;

  input clk;
  input [logq-1:0] u;
  input [logq-1:0] v;
  input [logq-1:0] w;
  input [1:0] mode;
  input [logq-1:0] q;
  input [(logq+1)-1:0] r;
  output reg [logq-1:0] out0;
  output reg [logq-1:0] out1;

  reg [logq-1:0] u_delay[mul_red_delay-1:0];
  wire [logq-1:0] u_delayed;

  reg [logq-1:0] v_delay[mul_red_delay-1:0];
  wire [logq-1:0] v_delayed;

  reg [logq-1:0] q_delay[mul_red_delay-1:0];
  wire [logq-1:0] q_delayed;

  reg [1:0] mode_delay[mul_red_delay-1:0];
  wire [1:0] mode_delayed;


  reg [logq-1:0] mul_red_b_in;
  wire [logq-1:0] mul_red_out;

  reg [(logq+1)-1:0] add_red;
  reg [(logq+1)-1:0] sub_red;

  reg [(logq+1)-1:0] out0_comb;
  reg [(logq+1)-1:0] out1_comb;

  mul_red #(
      .logq(logq),
      .dm  (dm)
  ) mul_red (
      .clk(clk),
      .a  (v),
      .b  (mul_red_b_in),
      .q  (q),
      .r  (r),
      .out(mul_red_out)
  );


  // pipeline registers
  integer i;
  always @(posedge clk) begin
    //delay u
    u_delay[0] <= u;
    for (i = 0; i < mul_red_delay - 1; i = i + 1) u_delay[i+1] <= u_delay[i];

    //delay v
    v_delay[0] <= v;
    for (i = 0; i < mul_red_delay - 1; i = i + 1) v_delay[i+1] <= v_delay[i];

    //delay q
    q_delay[0] <= q;
    for (i = 0; i < mul_red_delay - 1; i = i + 1) q_delay[i+1] <= q_delay[i];


    //delay mode
    mode_delay[0] <= mode;
    for (i = 0; i < mul_red_delay - 1; i = i + 1) mode_delay[i+1] <= mode_delay[i];
  end
  assign u_delayed = u_delay[mul_red_delay-1];
  assign v_delayed = v_delay[mul_red_delay-1];
  assign q_delayed = q_delay[mul_red_delay-1];
  assign mode_delayed = mode_delay[mul_red_delay-1];


  always @(*) begin
    // input to mul_red_b_in
    if (mode == 2'b00 || mode == 2'b01) begin
      mul_red_b_in = w;
    end else begin
      mul_red_b_in = u;
    end
  end

  // sub_red
  always @(*) begin
    sub_red = u_delayed - mul_red_out;
    if ($signed(sub_red) < 0) sub_red = sub_red + q_delayed;

    out1_comb = sub_red;
  end

  //
  always @(*) begin
    // add
    if (mode_delayed == 2'b10) begin
      add_red = u_delayed + v_delayed;
      // mult or butterfly care
    end else begin
      add_red = u_delayed + mul_red_out;
    end
    if (add_red >= q_delayed) add_red = add_red - q_delayed;


    // mult
    if (mode_delayed == 2'b11) begin
      out0_comb = mul_red_out;
    end else begin  // butterfly or add
      out0_comb = add_red;
    end
  end

  always @(posedge clk) begin
    out0 <= out0_comb;
    out1 <= out1_comb;
  end



endmodule

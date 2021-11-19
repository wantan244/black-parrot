`timescale 1ns / 1ps

module decryption_seal #(
    parameter q = 17,
    parameter N = 8,
    parameter logq = 5,
    parameter logN = 3,
    parameter N_inv = 15
) (
    input wire clk,
    input wire reset_n,
    // Indicate whether all inputs are valid in the current clock
    input wire in_valid,
    input wire [logq-1:0] cipher0_in,
    input wire [logq-1:0] cipher1_in,
    input wire [logq-1:0] secret_key_in,
    // Assert when the module can consume the current input
    output reg in_ready,
    // Assert when the output data is valid in the corrent clock
    output reg out_valid,
    output reg [logq-1:0] message_out,
    // Indicate whether the outside can consume the current output
    input wire out_ready
);

  // Polynomial multiplier
  reg mult_in0_valid;
  reg mult_in1_valid;
  reg [logq-1:0] mult_poly_in0;
  reg [logq-1:0] mult_poly_in1;
  wire mult_in_ready;
  wire mult_out_valid;
  wire [logq-1:0] mult_poly_out;
  reg mult_out_ready;

  elementwise_multiplier #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN)
  ) elem_mult (
      .clk      (clk),
      .reset_n  (reset_n),
      .in0_valid(mult_in0_valid),
      .in1_valid(mult_in1_valid),
      .poly_in0 (mult_poly_in0),
      .poly_in1 (mult_poly_in1),
      .in_ready (mult_in_ready),

      .out_valid(mult_out_valid),
      .poly_out (mult_poly_out),
      .out_ready(mult_out_ready)
  );


  // Polynomial adder
  reg adder_in0_valid;
  reg adder_in1_valid;
  reg [logq-1:0] adder_poly_in0;
  reg [logq-1:0] adder_poly_in1;
  wire adder_in_ready;
  wire adder_out_valid;
  wire [logq-1:0] adder_poly_out;
  reg adder_out_ready;
  polynomial_adder #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN)
  ) poly_adder (
      .clk      (clk),
      .reset_n  (reset_n),
      .in0_valid(adder_in0_valid),
      .in1_valid(adder_in1_valid),
      .poly_in0 (adder_poly_in0),
      .poly_in1 (adder_poly_in1),
      .in_ready (adder_in_ready),

      .out_valid(adder_out_valid),
      .poly_out (adder_poly_out),
      .out_ready(adder_out_ready)
  );


  // c0_fifo
  reg c0_wen;  // Direct connect to input
  reg [logq-1:0] c0_din;  // Direct connect to input
  reg c0_ren;
  wire [logq-1:0] c0_dout;
  wire c0_n_full;
  wire c0_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) c0_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (c0_wen),
      .data_in (c0_din),
      .r_en    (c0_ren),
      .data_out(c0_dout),
      .n_full  (c0_n_full),
      .n_empty (c0_n_empty)
  );


    // c1_fifo
  reg c1_wen;  // Direct connect to input
  reg [logq-1:0] c1_din;  // Direct connect to input
  reg c1_ren;
  wire [logq-1:0] c1_dout;
  wire c1_n_full;
  wire c1_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) c1_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (c1_wen),
      .data_in (c1_din),
      .r_en    (c1_ren),
      .data_out(c1_dout),
      .n_full  (c1_n_full),
      .n_empty (c1_n_empty)
  );


    // sk_fifo
  reg sk_wen;  // Direct connect to input
  reg [logq-1:0] sk_din;  // Direct connect to input
  reg sk_ren;
  wire [logq-1:0] sk_dout;
  wire sk_n_full;
  wire sk_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) sk_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (sk_wen),
      .data_in (sk_din),
      .r_en    (sk_ren),
      .data_out(sk_dout),
      .n_full  (sk_n_full),
      .n_empty (sk_n_empty)
  );

  //intt
  reg intt_in_valid;
  reg [logq-1:0] intt_poly_in;
  wire intt_in_ready;
  wire intt_out_valid;
  wire [logq-1:0] intt_poly_out;
  reg intt_out_ready;

  intt #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) u_intt (
      .clk     (clk),
      .reset_n (reset_n),
      .in_valid(intt_in_valid),
      .poly_in (intt_poly_in),
      .in_ready(intt_in_ready),

      .out_valid(intt_out_valid),
      .poly_out (intt_poly_out),
      .out_ready(intt_out_ready)
  );


  // Module input/output signals (FIFO width expansion)
  always @(*) begin
    // Only consume input if all fifos have vacant space
    in_ready = (c0_n_full && c1_n_full && sk_n_full);

    // c0 fifo to outside
    c0_din = cipher0_in;
    c0_wen = in_valid && in_ready;

    // c1 fifo to outside
    c1_din = cipher1_in;
    c1_wen = in_valid && in_ready;

    // c0 fifo to outside
    sk_din = secret_key_in;
    sk_wen = in_valid && in_ready;

    // multiplier to outside (c1*s)
    mult_poly_in0 = c1_dout;
    mult_in0_valid = c1_n_empty;
    c1_ren=mult_in_ready;

    mult_poly_in1 = sk_dout;
    mult_in1_valid = sk_n_empty;
    sk_ren=mult_in_ready;

    // adder input (c0 + c1*s)
    adder_poly_in0 = c0_dout;
    adder_poly_in1 = mult_poly_out;
    adder_in0_valid = c0_n_empty;
    adder_in1_valid = mult_out_valid;
    c0_ren = adder_in_ready;
    mult_out_ready = adder_in_ready;

    // adder to intt
    intt_poly_in = adder_poly_out;
    intt_in_valid = adder_out_valid;
    adder_out_ready = intt_in_ready;

    // intt to outside
    message_out = intt_poly_out;
    out_valid = intt_out_valid;
    intt_out_ready = out_ready;

  end



endmodule

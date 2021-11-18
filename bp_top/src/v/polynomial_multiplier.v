`timescale 1ns / 1ps

module polynomial_multiplier #(
    parameter q = 17,
    parameter N = 8,
    parameter logq = 5,
    parameter logN = 3,
    parameter N_inv = 15
) (
    input wire clk,
    input wire reset_n,

    input wire in0_valid,     // whether the input is valid
    input wire in1_valid,
    input wire [logq-1:0] poly_in0,
    input wire [logq-1:0] poly_in1,
    output wire in_ready,  // whether the module is ready to consume the input.

    output wire            out_valid,  // if output is valid
    output wire [logq-1:0] poly_out,
    input  wire            out_ready   // if the next stage is ready to consume the output
);

  reg [2:0] STATE;
  localparam STORE = 0;
  localparam NTT = 1;
  localparam MULT = 2;
  localparam iNTT = 3;
  localparam OUTPUT = 4;

  reg [logN-1:0] CNT;
  wire [logN-1:0] TNC;  //bit reverse of CNT

  reg [logN-2:0] STAGE;  //stages in Butterfly //bitwidth should be log(logN)
  wire [logq-1:0] VAR_a;
  wire [logq-1:0] VAR_b;
  wire [logq-1:0] VAR_c;
  wire [logN-1:0] CNT_h;
  wire [logN-1:0] k;  //index to various omega powers
  wire [logN-1:0] k_sft;  //index to various omega powers

  reg [logq-1:0] w[0:N-1];
  reg [logq-1:0] iw[0:N-1];
  reg [logq-1:0] phi[0:N-1];
  reg [logq-1:0] iphi[0:N-1];
  reg [logq-1:0] a[0:N-1];
  reg [logq-1:0] b[0:N-1];
  reg [logq-1:0] c[0:N-1];

  initial begin
    if (N == 8) begin
      $readmemh("wN8.mem", w, 0, N - 1);
      $readmemh("iwN8.mem", iw, 0, N - 1);
      $readmemh("phiN8.mem", phi, 0, N - 1);
      $readmemh("iphiN8.mem", iphi, 0, N - 1);
    end else if (N == 16) begin
      $readmemh("wN16.mem", w, 0, N - 1);
      $readmemh("iwN16.mem", iw, 0, N - 1);
      $readmemh("phiN16.mem", phi, 0, N - 1);
      $readmemh("iphiN16.mem", iphi, 0, N - 1);
    end
  end

  genvar i;
  generate
    for (i = 0; i < logN; i = i + 1) begin
      assign TNC[logN-1-i] = CNT[i];
    end
  endgenerate

  assign CNT_h = CNT ^ (1 << STAGE);
  assign VAR_a = (CNT[STAGE] == 0) ? (a[CNT_h] * w[k]) % q : 0;
  assign VAR_b = (CNT[STAGE] == 0) ? (b[CNT_h] * w[k]) % q : 0;
  assign VAR_c = (CNT[STAGE] == 0) ? (c[CNT_h] * iw[k]) % q : 0;

  assign k_sft = (STAGE == 0) ? 0 : (CNT << (logN - STAGE));
  assign k = k_sft[logN-1:1];


  assign poly_out = (c[CNT] * iphi[CNT]) % q;  //N_inv is multiplied with iphi
  assign out_valid = (STATE == OUTPUT);

  always @(posedge clk) begin
    if (STATE == NTT || STATE == iNTT) begin
      if (STAGE < logN) begin
        if (CNT < N) begin
          CNT <= CNT + 1;
          if (CNT == N - 1) begin
            STAGE <= STAGE + 1;
          end
        end
      end else if (STAGE == logN) begin
        STAGE <= 0;
        CNT   <= 0;
        STATE <= STATE + 1;
      end
    end else if (STATE == MULT && CNT < N) begin
      CNT <= CNT + 1;
      if (CNT == N - 1) begin
        CNT   <= 0;
        STATE <= STATE + 1;
      end
    end
  end

  assign in_ready = (STATE == STORE) && in0_valid && in1_valid;

  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      STATE <= 0;
      STAGE <= 0;
      CNT   <= 0;
    end else
      case (STATE)
        STORE: begin
          if (in0_valid && in1_valid) begin
            a[TNC] <= (poly_in0 * phi[CNT]) % q;
            b[TNC] <= (poly_in1 * phi[CNT]) % q;

            if (CNT < N - 1) begin
              CNT <= CNT + 1;
            end else begin
              CNT   <= 0;
              STATE <= NTT;
            end
          end
        end

        NTT: begin
          if (STAGE < logN) begin
            if (CNT[STAGE] == 0) begin
              a[CNT_h] <= (a[CNT] >= VAR_a) ? (a[CNT] - VAR_a) : (q - VAR_a + a[CNT]);
              a[CNT]   <= (a[CNT] + VAR_a < q) ? (a[CNT] + VAR_a) : (a[CNT] + VAR_a - q);
              b[CNT_h] <= (b[CNT] >= VAR_b) ? (b[CNT] - VAR_b) : (q - VAR_b + b[CNT]);
              b[CNT]   <= (b[CNT] + VAR_b < q) ? (b[CNT] + VAR_b) : (b[CNT] + VAR_b - q);
            end
          end
        end
        MULT: begin
          c[TNC] <= (a[CNT] * b[CNT]) % q;
        end
        iNTT: begin
          if (STAGE < logN) begin
            if (CNT[STAGE] == 0) begin
              c[CNT_h] <= (c[CNT] >= VAR_c) ? (c[CNT] - VAR_c) : (q - VAR_c + c[CNT]);
              c[CNT]   <= (c[CNT] + VAR_c < q) ? (c[CNT] + VAR_c) : (c[CNT] + VAR_c - q);
            end
          end
        end
        OUTPUT: begin
          if (out_ready) begin
            CNT <= CNT + 1;
            if (CNT == N - 1) begin
              CNT   <= 0;
              STATE <= STORE;
            end
          end
        end
      endcase
  end

endmodule

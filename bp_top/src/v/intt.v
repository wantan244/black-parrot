`timescale 1ns / 1ps

module intt #(
    parameter q = 17,
    parameter N = 8,
    parameter logq = 5,
    parameter logN = 3,
    parameter N_inv = 15
) (
    input wire clk,
    input wire reset_n,

    input wire in_valid,     // whether the input is valid
    input wire [logq-1:0] poly_in,
    output wire in_ready,  // whether the module is ready to consume the input.

    output wire            out_valid,  // if output is valid
    output wire [logq-1:0] poly_out,
    input  wire            out_ready   // if the next stage is ready to consume the output
);

  reg [1:0] STATE;
  localparam STORE = 0;
  localparam iNTT = 1;
  localparam OUTPUT = 2;

  reg [logN-1:0] CNT;
  wire [logN-1:0] TNC;  //bit reverse of CNT

  reg [logN-2:0] STAGE;  //stages in Butterfly //bitwidth should be log(logN)
  wire [logq-1:0] VAR_c;
  wire [logN-1:0] CNT_h;
  wire [logN-1:0] k;  //index to various omega powers
  wire [logN-1:0] k_sft;  //index to various omega powers

  reg [logq-1:0] iw[0:N-1];
  reg [logq-1:0] iphi[0:N-1];
  reg [logq-1:0] c[0:N-1];

/*  initial begin
    if (N == 8) begin
      $readmemh("iwN8.mem", iw, 0, N - 1);
      $readmemh("iphiN8.mem", iphi, 0, N - 1);
    end else if (N == 16) begin
      $readmemh("iwN16.mem", iw, 0, N - 1);
      $readmemh("iphiN16.mem", iphi, 0, N - 1);
    end else begin
      $readmemh("iw_N4096_q0.mem", iw, 0, N - 1);
      $readmemh("iphi_N4096_q0.mem", iphi, 0, N - 1);
    end
  end
*/
  genvar i;
  generate
    for (i = 0; i < logN; i = i + 1) begin
      assign TNC[logN-1-i] = CNT[i];
    end
  endgenerate

  assign CNT_h = CNT ^ (1 << STAGE);
  wire [2*logq-1:0] temp_mult0, temp_mult1;
  wire [logq:0] temp_add0;
  assign temp_mult0 = (c[CNT] * iphi[CNT]);
  assign temp_mult1 = (c[CNT_h] * iw[k]);
  assign VAR_c = (CNT[STAGE] == 0) ? temp_mult1 % q : 0;
  assign temp_add0 = c[CNT] + VAR_c;

  assign k_sft = (STAGE == 0) ? 0 : (CNT << (logN - STAGE));
  assign k = k_sft[logN-1:1];


  assign poly_out = temp_mult0 % q;  //N_inv is multiplied with iphi
  assign out_valid = (STATE == OUTPUT);

  assign in_ready = (STATE == STORE);

  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      STATE <= 0;
      STAGE <= 0;
      CNT   <= 0;
    end else
      case (STATE)
        STORE: begin
          if (in_valid) begin
            c[CNT] <= poly_in;

            if (CNT < N - 1) begin
              CNT <= CNT + 1;
            end else begin
              CNT   <= 0;
              STATE <= iNTT;
            end
          end
        end

        iNTT: begin
          if (STAGE < logN) begin
            if (CNT[STAGE] == 0) begin
              c[CNT_h] <= (c[CNT] >= VAR_c) ? (c[CNT] - VAR_c) : (c[CNT] - VAR_c) + q;
              c[CNT]   <= (temp_add0 < q) ? (temp_add0) : (temp_add0 - q);
            end
          end

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
            STATE <= OUTPUT;
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

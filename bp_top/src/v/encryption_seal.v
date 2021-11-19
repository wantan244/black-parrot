`timescale 1ns / 1ps
`define NTT_MODULE ntt

module encryption_seal #(
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
    input wire [logq-1:0] r0_in,  // u
    input wire [logq-1:0] r1_in,  // e1
    input wire [logq-1:0] me0_in,  // m + e0
    input wire [logq-1:0] public_key_a_in,  // pk1
    input wire [logq-1:0] public_key_b_in,  // pk0
    // Assert when the module can consume the current input
    output reg in_ready,
    // Assert when the output data is valid in the corrent clock
    output reg out_valid,
    output wire [logq-1:0] cipher0_out,
    output wire [logq-1:0] cipher1_out,
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
      .logN (logN),
      .N_inv(N_inv)
  ) poly_mult (
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
      .logN (logN),
      .N_inv(N_inv)
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


  wire a_ntt_in_ready;
  wire a_ntt_out_valid;
  wire [logq-1:0] a_ntt_poly_out;
  wire a_ntt_out_ready;
  `NTT_MODULE #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) a_ntt (
      .clk      (clk),
      .reset_n  (reset_n),
      .in_valid (in_valid && in_ready),
      .poly_in  (public_key_a_in),
      .in_ready (a_ntt_in_ready),
      .out_valid(a_ntt_out_valid),
      .poly_out (a_ntt_poly_out),
      .out_ready(a_ntt_out_ready)
  );

  // a_fifo
  // reg a_wen;// Direct connect to input
  // reg [logq-1:0] a_din;// Direct connect to input
  reg a_ren;
  wire [logq-1:0] a_dout;
  // wire a_n_full;
  wire a_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) a_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (a_ntt_out_valid),
      .data_in (a_ntt_poly_out),
      .r_en    (a_ren),
      .data_out(a_dout),
      .n_full  (a_ntt_out_ready),
      .n_empty (a_n_empty)
  );

  wire b_ntt_in_ready;
  wire b_ntt_out_valid;
  wire [logq-1:0] b_ntt_poly_out;
  wire b_ntt_out_ready;
  `NTT_MODULE #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) b_ntt (
      .clk      (clk),
      .reset_n  (reset_n),
      .in_valid (in_valid && in_ready),
      .poly_in  (public_key_b_in),
      .in_ready (b_ntt_in_ready),
      .out_valid(b_ntt_out_valid),
      .poly_out (b_ntt_poly_out),
      .out_ready(b_ntt_out_ready)
  );


  // b_fifo
  // reg b_wen;// Direct connect to input
  // reg [logq-1:0] b_din;// Direct connect to input
  reg b_ren;
  wire [logq-1:0] b_dout;
  // wire b_n_full;
  wire b_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) b_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (b_ntt_out_valid),
      .data_in (b_ntt_poly_out),
      .r_en    (b_ren),
      .data_out(b_dout),
      .n_full  (b_ntt_out_ready),
      .n_empty (b_n_empty)
  );


  wire r0_ntt_in_ready;
  wire r0_ntt_out_valid;
  wire [logq-1:0] r0_ntt_poly_out;
  wire r0_ntt_out_ready;
  `NTT_MODULE #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) r0_ntt (
      .clk      (clk),
      .reset_n  (reset_n),
      .in_valid (in_valid && in_ready),
      .poly_in  (r0_in),
      .in_ready (r0_ntt_in_ready),
      .out_valid(r0_ntt_out_valid),
      .poly_out (r0_ntt_poly_out),
      .out_ready(r0_ntt_out_ready)
  );

  // r0_fifo
  // reg r0_wen;// Direct connect to input
  // reg [logq-1:0] r0_din;// Direct connect to input
  reg r0_ren1;
  wire [logq-1:0] r0_dout1;
  reg r0_ren2;
  wire [logq-1:0] r0_dout2;
  // wire r0_n_full;
  wire r0_n_empty1;
  wire r0_n_empty2;

  fifo_2rp #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) r0_fifo (
      .clk      (clk),
      .reset_n  (reset_n),
      .w_en     (r0_ntt_out_valid),
      .data_in  (r0_ntt_poly_out),
      .r_en1    (r0_ren1),
      .data_out1(r0_dout1),
      .r_en2    (r0_ren2),
      .data_out2(r0_dout2),
      .n_full   (r0_ntt_out_ready),
      .n_empty1 (r0_n_empty1),
      .n_empty2 (r0_n_empty2)
  );


  wire r1_ntt_in_ready;
  wire r1_ntt_out_valid;
  wire [logq-1:0] r1_ntt_poly_out;
  wire r1_ntt_out_ready;
  `NTT_MODULE #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) r1_ntt (
      .clk      (clk),
      .reset_n  (reset_n),
      .in_valid (in_valid && in_ready),
      .poly_in  (r1_in),
      .in_ready (r1_ntt_in_ready),
      .out_valid(r1_ntt_out_valid),
      .poly_out (r1_ntt_poly_out),
      .out_ready(r1_ntt_out_ready)
  );

  // r1_fifo
  // reg r1_wen;// Direct connect to input
  // reg [logq-1:0] r1_din;// Direct connect to input
  reg r1_ren;
  wire [logq-1:0] r1_dout;
  // wire r1_n_full;
  wire r1_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) r1_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (r1_ntt_out_valid),
      .data_in (r1_ntt_poly_out),
      .r_en    (r1_ren),
      .data_out(r1_dout),
      .n_full  (r1_ntt_out_ready),
      .n_empty (r1_n_empty)
  );


  wire r2_ntt_in_ready;
  wire r2_ntt_out_valid;
  wire [logq-1:0] r2_ntt_poly_out;
  wire r2_ntt_out_ready;
  `NTT_MODULE #(
      .q    (q),
      .N    (N),
      .logq (logq),
      .logN (logN),
      .N_inv(N_inv)
  ) r2_ntt (
      .clk      (clk),
      .reset_n  (reset_n),
      .in_valid (in_valid && in_ready),
      .poly_in  (me0_in),
      .in_ready (r2_ntt_in_ready),
      .out_valid(r2_ntt_out_valid),
      .poly_out (r2_ntt_poly_out),
      .out_ready(r2_ntt_out_ready)
  );

  // r2_fifo
  // reg r2_wen;// Direct connect to input
  // reg [logq-1:0] r2_din;// Direct connect to input
  reg r2_ren;
  wire [logq-1:0] r2_dout;
  // wire r2_n_full;
  wire r2_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) r2_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (r2_ntt_out_valid),
      .data_in (r2_ntt_poly_out),
      .r_en    (r2_ren),
      .data_out(r2_dout),
      .n_full  (r2_ntt_out_ready),
      .n_empty (r2_n_empty)
  );



  // ar0_fifo
  reg ar0_wen;
  reg [logq-1:0] ar0_din;
  reg ar0_ren;
  wire [logq-1:0] ar0_dout;
  wire ar0_n_full;
  wire ar0_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) ar0_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (ar0_wen),
      .data_in (ar0_din),
      .r_en    (ar0_ren),
      .data_out(ar0_dout),
      .n_full  (ar0_n_full),
      .n_empty (ar0_n_empty)
  );


  // br0_fifo
  reg br0_wen;
  reg [logq-1:0] br0_din;
  reg br0_ren;
  wire [logq-1:0] br0_dout;
  wire br0_n_full;
  wire br0_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) br0_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (br0_wen),
      .data_in (br0_din),
      .r_en    (br0_ren),
      .data_out(br0_dout),
      .n_full  (br0_n_full),
      .n_empty (br0_n_empty)
  );


  // br0r2_fifo
  reg br0r2_wen;
  reg [logq-1:0] br0r2_din;
  // reg br0r2_ren; // connect to output
  // wire [logq-1:0] br0r2_dout; // connect to output
  wire br0r2_n_full;
  wire br0r2_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) br0r2_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (br0r2_wen),
      .data_in (br0r2_din),
      .r_en    (out_ready && out_valid),
      .data_out(cipher0_out),
      .n_full  (br0r2_n_full),
      .n_empty (br0r2_n_empty)
  );


  // ar0r1_fifo
  reg ar0r1_wen;
  reg [logq-1:0] ar0r1_din;
  // reg ar0r1_ren;// Direct connect to output
  // wire [logq-1:0] ar0r1_dout; // Direct connect to output
  wire ar0r1_n_full;
  wire ar0r1_n_empty;

  fifo #(
      .DATA_WIDTH(logq),
      .ADDR_WIDTH(logN)
  ) ar0r1_fifo (
      .clk     (clk),
      .reset_n (reset_n),
      .w_en    (ar0r1_wen),
      .data_in (ar0r1_din),
      .r_en    (out_ready && out_valid),
      .data_out(cipher1_out),
      .n_full  (ar0r1_n_full),
      .n_empty (ar0r1_n_empty)
  );


  // // Debug output
  // integer fin, fout;
  // initial begin
  //   fout = $fopen("br0r2_encryption_out.txt", "w");
  // end
  // // Write output to file.
  // always @(posedge clk) begin
  //   if (br0r2_n_full && br0r2_wen) begin
  //     $fdisplay(fout, "%h\t%d", br0r2_din, br0r2_din);
  //   end
  // end



  // Module input/output signals (FIFO width expansion)
  always @(*) begin
    // Only consume input if all fifos have vacant space
    in_ready  = (a_ntt_in_ready && b_ntt_in_ready && r0_ntt_in_ready && 
              r1_ntt_in_ready && r2_ntt_in_ready);
    // Output is valid if there are data in both output fifos
    out_valid = br0r2_n_empty && ar0r1_n_empty;
  end




  // Multiplier input/output state counter
  reg [logN-1:0] mult_in_cnt, mult_out_cnt;
  reg mult_in_state, mult_out_state;
  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      mult_in_cnt <= 0;
      mult_out_cnt <= 0;
      mult_in_state <= 0;
      mult_out_state <= 0;
    end else begin
      // Input count
      if (mult_in0_valid && mult_in1_valid && mult_in_ready) begin
        if (mult_in_cnt != N - 1) begin
          mult_in_cnt <= mult_in_cnt + 1;
        end else begin  // Current input finished
          mult_in_cnt <= 0;
          if (mult_in_state != 2 - 1) begin  // Switch to the next input
            mult_in_state <= mult_in_state + 1;
          end else begin  // Roll back to the initial input
            mult_in_state <= 0;
          end
        end
      end
      // Output count
      if (mult_out_valid && mult_out_ready) begin
        if (mult_out_cnt != N - 1) begin
          mult_out_cnt <= mult_out_cnt + 1;
        end else begin  // Current input finished
          mult_out_cnt <= 0;
          if (mult_out_state != 2 - 1) begin  // Switch to the next input
            mult_out_state <= mult_out_state + 1;
          end else begin  // Roll back to the initial input
            mult_out_state <= 0;
          end
        end
      end
    end
  end


  // Multiplier input mux
  always @(*) begin
    b_ren   = 0;
    r0_ren1 = 0;

    a_ren   = 0;
    r0_ren2 = 0;

    case (mult_in_state)
      1'b0: begin  // Compute br0 = b * r0
        mult_in0_valid = b_n_empty;
        mult_poly_in0 = b_dout;
        b_ren = mult_in_ready;

        mult_in1_valid = r0_n_empty1;
        mult_poly_in1 = r0_dout1;
        r0_ren1 = mult_in_ready;
      end

      default: begin  // Compute ar0 = a * r0 
        mult_in0_valid = a_n_empty;
        mult_poly_in0 = a_dout;
        a_ren = mult_in_ready;

        mult_in1_valid = r0_n_empty2;
        mult_poly_in1 = r0_dout2;
        r0_ren2 = mult_in_ready;
      end
    endcase
  end

  // Multiplier output mux
  always @(*) begin
    br0_din = mult_poly_out;
    ar0_din = mult_poly_out;

    br0_wen = 0;
    ar0_wen = 0;

    case (mult_out_state)
      1'b0: begin  // Compute br0 = b * r0
        br0_wen = mult_out_valid;
        mult_out_ready = br0_n_full;
      end

      default: begin  // Compute ar0 = a * r0 
        ar0_wen = mult_out_valid;
        mult_out_ready = ar0_n_full;
      end
    endcase
  end




  // Adder input/output state counter
  reg [logN-1:0] adder_in_cnt, adder_out_cnt;
  reg adder_in_state, adder_out_state;
  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      adder_in_cnt <= 0;
      adder_out_cnt <= 0;
      adder_in_state <= 0;
      adder_out_state <= 0;
    end else begin
      // Input count
      if (adder_in0_valid && adder_in1_valid && adder_in_ready) begin
        if (adder_in_cnt != N - 1) begin
          adder_in_cnt <= adder_in_cnt + 1;
        end else begin  // Current input finished
          adder_in_cnt <= 0;
          if (adder_in_state != 2 - 1) begin  // Switch to the next input
            adder_in_state <= adder_in_state + 1;
          end else begin  // Roll back to the initial input
            adder_in_state <= 0;
          end
        end
      end

      // Output count
      if (adder_out_valid && adder_out_ready) begin
        if (adder_out_cnt != N - 1) begin
          adder_out_cnt <= adder_out_cnt + 1;
        end else begin  // Current input finished
          adder_out_cnt <= 0;
          if (adder_out_state != 2 - 1) begin  // Switch to the next input
            adder_out_state <= adder_out_state + 1;
          end else begin  // Roll back to the initial input
            adder_out_state <= 0;
          end
        end
      end
    end
  end


  // Adder input mux
  always @(*) begin
    br0_ren = 0;
    r2_ren  = 0;

    ar0_ren = 0;
    r1_ren  = 0;

    case (adder_in_state)
      2'b0: begin  // Compute br0r2 = br0 + r2
        adder_in0_valid = br0_n_empty;
        adder_poly_in0 = br0_dout;
        br0_ren = adder_in_ready;

        adder_in1_valid = r2_n_empty;
        adder_poly_in1 = r2_dout;
        r2_ren = adder_in_ready;
      end

      default: begin  // Compute ar0r1 = ar0 + r1
        adder_in0_valid = ar0_n_empty;
        adder_poly_in0 = ar0_dout;
        ar0_ren = adder_in_ready;

        adder_in1_valid = r1_n_empty;
        adder_poly_in1 = r1_dout;
        r1_ren = adder_in_ready;
      end

    endcase
  end


  // Adder output mux
  always @(*) begin
    br0r2_din = adder_poly_out;
    ar0r1_din = adder_poly_out;

    br0r2_wen = 0;
    ar0r1_wen = 0;

    case (adder_out_state)
      2'b0: begin  // Compute br0r2 = br0 + r2
        br0r2_wen = adder_out_valid;
        adder_out_ready = br0r2_n_full;
      end

      default: begin  // Compute ar0r1 = ar0 + r1
        ar0r1_wen = adder_out_valid;
        adder_out_ready = ar0r1_n_full;
      end
    endcase
  end

endmodule

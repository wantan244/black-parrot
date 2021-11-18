module fifo #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4
) (
    input clk,
    input reset_n,
    input w_en,
    input [DATA_WIDTH-1:0] data_in,
    input r_en,
    output [DATA_WIDTH-1:0] data_out,
    output n_full,  // not full
    output n_empty  // not empty
);

  reg [ADDR_WIDTH:0] w_ptr, r_ptr;  //read pointer and write pointer
  wire [ADDR_WIDTH:0] depth;
  wire w_en_q, r_en_q;  // read and write enable qualified

  reg [DATA_WIDTH-1:0] data[(2**ADDR_WIDTH)-1:0];  // data storage

  wire [ADDR_WIDTH:0] EMPTY_DEPTH = {(ADDR_WIDTH + 1) {1'b0}};
  wire [ADDR_WIDTH:0] FULL_DEPTH = {1'b1, {(ADDR_WIDTH) {1'b0}}};

  assign depth = w_ptr - r_ptr;
  assign n_full = (depth != FULL_DEPTH);
  assign n_empty = (depth != EMPTY_DEPTH);

  assign w_en_q = (n_full) & w_en;
  assign r_en_q = (n_empty) & r_en;
  assign data_out = data[r_ptr[ADDR_WIDTH-1:0]];

  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      w_ptr <= EMPTY_DEPTH;
      r_ptr <= EMPTY_DEPTH;
    end else begin
      if (w_en_q) begin
        data[w_ptr[ADDR_WIDTH-1:0]] <= data_in;
        w_ptr <= w_ptr + 1;
      end
      if (r_en_q) r_ptr <= r_ptr + 1;
    end
  end

endmodule


// Fifo with 2 read pointers
module fifo_2rp #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4
) (
    input clk,
    input reset_n,
    input w_en,
    input [DATA_WIDTH-1:0] data_in,
    input r_en1,
    output [DATA_WIDTH-1:0] data_out1,
    input r_en2,
    output [DATA_WIDTH-1:0] data_out2,
    output n_full,  // not full
    output n_empty1,  // read port 1 not empty
    output n_empty2  // read port 2 not empty
);

  reg [ADDR_WIDTH:0] w_ptr, r_ptr1, r_ptr2;  //read pointer and write pointer
  wire [ADDR_WIDTH:0] depth1, depth2;
  wire w_en_q, r_en_q1, r_en_q2;  // read and write enable qualified

  reg [DATA_WIDTH-1:0] data[(2**ADDR_WIDTH)-1:0];  // data storage

  wire [ADDR_WIDTH:0] EMPTY_DEPTH = {(ADDR_WIDTH + 1) {1'b0}};
  wire [ADDR_WIDTH:0] FULL_DEPTH = {1'b1, {(ADDR_WIDTH) {1'b0}}};

  assign depth1 = w_ptr - r_ptr1;
  assign depth2 = w_ptr - r_ptr2;
  assign n_full = (depth1 != FULL_DEPTH) && (depth2 != FULL_DEPTH);
  assign n_empty1 = (depth1 != EMPTY_DEPTH);
  assign n_empty2 = (depth2 != EMPTY_DEPTH);

  assign w_en_q = n_full && w_en;
  assign r_en_q1 = n_empty1 && r_en1;
  assign r_en_q2 = n_empty2 && r_en2;
  assign data_out1 = data[r_ptr1[ADDR_WIDTH-1:0]];
  assign data_out2 = data[r_ptr2[ADDR_WIDTH-1:0]];

  always @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
      w_ptr  <= EMPTY_DEPTH;
      r_ptr1 <= EMPTY_DEPTH;
      r_ptr2 <= EMPTY_DEPTH;
    end else begin
      if (w_en_q) begin
        data[w_ptr[ADDR_WIDTH-1:0]] <= data_in;
        w_ptr <= w_ptr + 1;
      end
      if (r_en_q1) r_ptr1 <= r_ptr1 + 1;
      if (r_en_q2) r_ptr2 <= r_ptr2 + 1;
    end
  end

endmodule

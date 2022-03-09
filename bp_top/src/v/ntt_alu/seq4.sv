`timescale 1ns / 1ps


// Butterfly unit and ALU
module seq4 (
    clk,
    rst_n,
    in0_data,
    in1_data,
    in0_addr,
    in1_addr,
    in0_en,
    in1_en,
    mode,
    out0_data,
    out1_data,
    out0_addr,
    out1_addr,
    out0_valid,
    out1_valid
);
  parameter data_width = 17;
  parameter addr_width = 17;
  localparam seq_delay = 2;

  input clk;
  input rst_n;
  input [data_width-1:0] in0_data;
  input [data_width-1:0] in1_data;
  input [addr_width-1:0] in0_addr;
  input [addr_width-1:0] in1_addr;
  input in0_en;
  input in1_en;
  input mode;
  output reg [data_width-1:0] out0_data;
  output reg [data_width-1:0] out1_data;
  output reg [addr_width-1:0] out0_addr;
  output reg [addr_width-1:0] out1_addr;
  output reg out1_valid;
  output reg out0_valid;

  reg [data_width-1:0] arr_data[15:0];
  reg [addr_width-1:0] arr_addr[15:0];
  reg [15:0] arr_en;
  reg [7:0] arr_mode;
  reg [3:0] wcnt, wcnt_r, rcnt;
  reg [3:0] wp0, wp1;
  reg [3:0] rp0_data, rp1_data, rp0_addr, rp1_addr;
  reg input_en;

  reg empty;

  always @(*) begin
    empty = (wcnt_r == rcnt);
    input_en = in0_en || in1_en;

    wp0 = (wcnt << 1);
    wp1 = wp0 + 1;

    rp0_addr = (rcnt << 1);
    rp1_addr = rp0_addr + 1;

    if (arr_mode[rcnt[2:0]] == 1'b1) begin
      rp0_data = {rcnt[2], rcnt[0], 1'b0, rcnt[1]};
      rp1_data = rp0_data + 2;
    end else begin
      rp0_data = rp0_addr;
      rp1_data = rp1_addr;
    end

    out0_data  = arr_data[rp0_data];
    out1_data  = arr_data[rp1_data];
    out0_addr  = arr_addr[rp0_addr];
    out1_addr  = arr_addr[rp1_addr];
    out0_valid = (!empty) && arr_en[rp0_data];
    out1_valid = (!empty) && arr_en[rp1_data];
  end

  always @(posedge clk) begin
    if (input_en) begin
      arr_data[wp0] <= in0_data;
      arr_data[wp1] <= in1_data;
      arr_addr[wp0] <= in0_addr;
      arr_addr[wp1] <= in1_addr;
      arr_en[wp0] <= in0_en;
      arr_en[wp1] <= in1_en;
      arr_mode[wcnt[2:0]] <= mode;
    end
  end

  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      wcnt   <= 0;
      wcnt_r <= 0;
      rcnt   <= 0;
    end else begin
      if (input_en) begin
        if (wcnt[1:0] == 2'b11) begin
          wcnt_r <= wcnt_r + 4;
        end
        wcnt <= wcnt + 1;
      end

      if (!empty) begin
        rcnt <= rcnt + 1;
      end
    end
  end

endmodule

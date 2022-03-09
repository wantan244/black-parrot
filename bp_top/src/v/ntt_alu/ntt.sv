module ntt_alu 
  import bp_common_pkg::*;
   #(
    parameter max_logn = 12,
    parameter max_logq = 30,
    parameter dm = 4  // latency of the pipelined multiplier
    ) 
   (
    input clk,
    input rst_n,

    input [max_logn-1:0] cfg_logn,
    input [max_logq-1:0] cfg_q,
    input [(max_logq+1)-1:0] cfg_r,
    input [max_logq-1:0] cfg_w,
    input [max_logq-1:0] cfg_phi,
    input [max_logq-1:0] cfg_n_inv,

    output logic [max_logn-3:0] r_addr_0,
    output logic [max_logn-3:0] r_addr_1,
    output logic [2:0] r_bank_0,
    output logic [2:0] r_bank_1,
    output logic r_en_0,
    output logic r_en_1,
    input [max_logq-1:0] r_data_0,
    input [max_logq-1:0] r_data_1,

    output logic [max_logn-3:0] w_addr_0,
    output logic [max_logn-3:0] w_addr_1,
    output logic [2:0] w_bank_0,
    output logic [2:0] w_bank_1,
    output logic w_en_0,
    output logic w_en_1,
    output logic [max_logq-1:0] w_data_0,
    output logic [max_logq-1:0] w_data_1,

    input alu_op_e op,
    output logic done
);

  // total_delay = mem_read + (BFU) + seq
  localparam total_delay = 1 + (3 * dm + 2) + 4;
  localparam wait_latency = total_delay - 1;

  // Address conversion for writing NTT inputs
  function automatic [max_logn-1:0] bit_rev(input [max_logn-1:0] in,
                                              input [max_logn-1:0] logn);
    logic [max_logn-1:0] in_rev;
    in_rev = {<<{in}};
    return in_rev >> (max_logn - logn);
  endfunction

  // Address conversion for reading NTT outputs
  function automatic [max_logn-1:0] cnt2ntt_addr(input [max_logn-1:0] in,
                                                   input [max_logn-1:0] logn);
    logic [max_logn-1:0] in_rev, res;
    in_rev = bit_rev(in, logn);
    res = cnt2intt_addr(in_rev, logn);
    return res;
  endfunction

  // Address conversion for writing INTT inputs is not needed. (Just use cnt as address)
  /*.....
  .......
  .....*/

  // Address conversion for reading INTT outputs
  function automatic [max_logn-1:0] cnt2intt_addr(input [max_logn-1:0] in,
                                                    input [max_logn-1:0] logn);
    logic [max_logn-1:0] in_rev, res;
    res[1:0] = in[1:0];
    res[3:2] = {in[logn-1], in[logn-2]};
    res[max_logn-1:4] = in[max_logn-3:2];
    res = res & ((1 << logn) - 1);
    return res;
  endfunction

  // if (dm < 2) $error("dm must be greater than or equal to 2.");
  // if (n/4 < total_delay) $warning("n too small.");

  typedef enum logic [2:0] {
    STATE_IDLE          = 0,
    STATE_CONF,
    STATE_PRE_POST_PROC,
    STATE_NTT_INTT,
    STATE_MULT_ADD,
    STATE_WAIT
  } ntt_state_e;
  ntt_state_e state;
  ntt_state_e state_after_wait;
  logic [max_logn-1:0] wait_count;

  typedef enum logic {
    NTT_SUBOP_NTT_OR_ADD   = 1'b0,
    NTT_SUBOP_INTT_OR_MULT
  } ntt_subop_e;


  logic [max_logq-1:0] q;
  logic [(max_logq+1)-1:0] r;

  logic [max_logq-1:0] bfu_u, bfu_v, bfu_w, bfu_out0, bfu_out1;
  logic [1:0] bfu_mode;

  logic [max_logq-1:0] seq_in0_data, seq_in1_data;
  logic [(max_logn+1)-1:0] seq_in0_addr, seq_in1_addr;
  logic [max_logq-1:0] seq_out0_data, seq_out1_data;
  logic [(max_logn+1)-1:0] seq_out0_addr, seq_out1_addr;
  logic seq_mode, seq_in0_en, seq_in1_en, seq_out0_valid, seq_out1_valid;


  bfu #(
      .logq(max_logq),
      .dm  (dm)
  ) bfu (
      .clk (clk),
      .u   (bfu_u),
      .v   (bfu_v),
      .w   (bfu_w),
      .mode(bfu_mode),
      .q   (q),
      .r   (r),
      .out0(bfu_out0),
      .out1(bfu_out1)
  );


  seq4 #(
      .data_width(max_logq),
      .addr_width(max_logn + 1)
  ) seq4 (
      .clk       (clk),
      .rst_n     (rst_n),
      .in0_data  (seq_in0_data),
      .in1_data  (seq_in1_data),
      .in0_addr  (seq_in0_addr),
      .in1_addr  (seq_in1_addr),
      .in0_en    (seq_in0_en),
      .in1_en    (seq_in1_en),
      .mode      (seq_mode),
      .out0_data (seq_out0_data),
      .out1_data (seq_out1_data),
      .out0_addr (seq_out0_addr),
      .out1_addr (seq_out1_addr),
      .out0_valid(seq_out0_valid),
      .out1_valid(seq_out1_valid)
  );

  // control signals from pipeline registers
  always_comb begin
    if (pr_mem_out.update_w_phi || pr_mem_out.conf_w) begin  // if updating w or phi
      bfu_u = pr_mem_out.w_phi;
      bfu_v = pr_mem_out.w_phi_interval;
    end else if (pr_mem_out.pre_post_proc) begin
      bfu_u = r_data_0;
      bfu_v = pr_mem_out.w_phi;
    end else begin
      bfu_u = r_data_0;
      bfu_v = r_data_1;
    end

    bfu_w = pr_mem_out.w_phi;
    bfu_mode = pr_mem_out.bfu_mode;

    seq_in0_data = bfu_out0;
    seq_in1_data = bfu_out1;
    seq_in0_addr = {pr_bfu_out.w_addr_0, pr_bfu_out.w_bank_0};
    seq_in1_addr = {pr_bfu_out.w_addr_1, pr_bfu_out.w_bank_1};
    seq_in0_en = pr_bfu_out.w_en_0;
    seq_in1_en = pr_bfu_out.w_en_1;
    seq_mode = pr_bfu_out.seq_mode;

    w_addr_0 = seq_out0_addr[((max_logn+1)-1):3];
    w_bank_0 = seq_out0_addr[2:0];
    w_data_0 = seq_out0_data;
    w_en_0 = seq_out0_valid;
    w_addr_1 = seq_out1_addr[((max_logn+1)-1):3];
    w_bank_1 = seq_out1_addr[2:0];
    w_data_1 = seq_out1_data;
    w_en_1 = seq_out1_valid;

    done = (state == STATE_IDLE);
  end

  typedef struct packed {
    logic seq_mode;
    logic [max_logn-3:0] w_addr_0, w_addr_1;
    logic [2:0] w_bank_0, w_bank_1;
    logic w_en_0, w_en_1;
    // stores current w or phi, and the values to be multiplied 
    logic [max_logq-1:0] w_phi, w_phi_interval;
    logic [1:0] bfu_mode;
    logic update_w_phi;
    logic pre_post_proc;
    logic conf_w;
`ifndef SYNTHESIS
    ntt_state_e state;
`endif
  } ntt_stage_reg;

  // pipeline registers and output wires from different stages
  ntt_stage_reg pr[total_delay-1:0];
  ntt_stage_reg pr_in;  // input wire to the first pipeline register
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pr <= '{default: 'b0};
    end else begin
      pr[0] <= pr_in;
      for (i = 0; i < total_delay - 1; i++) begin
        pr[i+1] <= pr[i];
      end
    end
  end
  ntt_stage_reg pr_mem_out, pr_bfu_out, pr_seq_out;
  assign pr_mem_out = pr[0];
  assign pr_bfu_out = pr[(1+(3*dm+2))-1];
  assign pr_seq_out = pr[(1+(3*dm+2)+4)-1];


  logic [max_logn:0] n, logn, stage, m, jj, kk, kk_rev, kk_intt_phy;
  logic [1:0] ll;
  logic [max_logn-1:0] update_count;
  logic hold, first_hold;
  logic [max_logq-1:0] curr_w;
  logic [max_logq-1:0] w_array[max_logn-1:0];
  logic [max_logq-1:0] phi, curr_phi;
  logic [max_logq-1:0] n_inv;

  ntt_subop_e subop;



  logic poly_idx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      state_after_wait <= STATE_IDLE;
      wait_count <= 0;

    end else begin

      unique case (state)
        STATE_IDLE: begin
          unique case (op)
            OP_CONF: begin
              stage <= 0;
              jj <= 0;
              kk <= cfg_logn - 1;

              logn <= cfg_logn;
              n <= 2 ** cfg_logn;
              q = cfg_q;
              r <= cfg_r;
              w_array[cfg_logn-1] <= cfg_w;
              phi <= cfg_phi;
              n_inv <= cfg_n_inv;


              hold <= 1;
              first_hold <= 1;
              state <= STATE_CONF;
            end

            OP_NTT0: begin
              stage <= 0;
              update_count <= 1;
              m <= 2;
              jj <= 0;
              kk <= 0;
              ll <= 0;
              curr_w <= 1;
              curr_phi <= 1;
              hold <= 0;
              first_hold <= 0;

              poly_idx <= 0;
              subop <= NTT_SUBOP_NTT_OR_ADD;
              state <= STATE_PRE_POST_PROC;
            end
            OP_NTT1: begin
              stage <= 0;
              update_count <= 1;
              m <= 2;
              jj <= 0;
              kk <= 0;
              ll <= 0;
              curr_w <= 1;
              curr_phi <= 1;
              hold <= 0;
              first_hold <= 0;

              poly_idx <= 1;
              subop <= NTT_SUBOP_NTT_OR_ADD;
              state <= STATE_PRE_POST_PROC;
            end
            OP_INTT1: begin
              stage <= 0;
              update_count <= 1;
              m <= 2;
              jj <= 0;
              kk <= 0;
              ll <= 0;
              curr_w <= 1;
              curr_phi <= n_inv;
              hold <= 0;
              first_hold <= 0;

              poly_idx <= 1;
              subop <= NTT_SUBOP_INTT_OR_MULT;
              state <= STATE_NTT_INTT;
            end
            OP_ADD: begin
              kk <= 0;

              subop <= NTT_SUBOP_NTT_OR_ADD;
              state <= STATE_MULT_ADD;
            end
            OP_MULT: begin
              kk <= 0;

              subop <= NTT_SUBOP_INTT_OR_MULT;
              state <= STATE_MULT_ADD;
            end
            default: begin
            end
          endcase
        end


        STATE_CONF: begin  // pre-compute (max_logn-1) w's
          /*
          for (kk=logn-1;kk>=2;kk--){
            w_array[kk-1]=w_array[kk]*w_array[kk];
          }
          // w_array[0] is not used
          */
          if (hold) begin
            first_hold <= 0;
            if (pr_bfu_out.conf_w) begin
              hold <= 0;
              w_array[kk-1] <= bfu_out0;
              if (kk != 2) begin
                kk <= kk - 1;
              end else begin
                kk <= 0;
                state <= STATE_IDLE;
              end
            end
          end else begin
            hold <= 1;
            first_hold <= 1;
          end
        end

        STATE_PRE_POST_PROC: begin
          if (hold) begin
            first_hold <= 0;
            if (pr_bfu_out.update_w_phi) begin
              hold <= 0;
              curr_phi <= bfu_out0;
            end
          end else begin
            if (kk + 1 < n) begin
              kk <= kk + 1;
              hold <= 1;
              first_hold <= 1;
            end else begin
              kk <= 0;
              if (subop == NTT_SUBOP_NTT_OR_ADD) begin  // NTT
                state <= STATE_WAIT;
                wait_count <= wait_latency;
                state_after_wait <= STATE_NTT_INTT;
              end else begin  // INTT
                state <= STATE_WAIT;
                wait_count <= wait_latency;
                state_after_wait <= STATE_IDLE;
              end
            end
          end
        end

        STATE_NTT_INTT: begin
          if (hold) begin
            first_hold <= 0;
            if (pr_bfu_out.update_w_phi) begin
              hold   <= 0;
              curr_w <= bfu_out0;
            end
          end else begin

            if (update_count == (n >> (stage + 1))) begin
              hold <= 1;
              first_hold <= 1;
              update_count <= 1;
            end else begin
              update_count <= update_count + 1;
            end

            if (ll != 3) begin
              ll <= ll + 1;
            end else begin
              ll <= 0;
              if ((kk + (m << 2)) < n) begin
                kk <= kk + (m << 2);
              end else begin
                kk <= 0;
                if ((jj + 4) < (m << 1)) begin
                  jj <= jj + 4;
                end else begin
                  jj <= 0;

                  if ((stage + 1) < logn) begin
                    stage <= stage + 1;
                    curr_w <= 1;
                    update_count <= 1;
                    // new stage, overwrite hold condition
                    hold <= 0;
                    first_hold <= 0;
                    if (m == (n >> 2)) begin
                      m <= 2;
                    end else begin
                      m <= (m << 1);
                    end
                  end else begin
                    stage <= 0;
                    m <= 2;
                    jj <= 0;
                    kk <= 0;
                    ll <= 0;
                    update_count <= 1;
                    // new stage, overwrite hold condition
                    hold <= 0;
                    first_hold <= 0;
                    if (subop == NTT_SUBOP_NTT_OR_ADD) begin  //NTT, jump to IDLE
                      state <= STATE_WAIT;
                      wait_count <= wait_latency;
                      state_after_wait <= STATE_IDLE;
                    end else begin  // INTT, jump to post-proc
                      state <= STATE_WAIT;
                      wait_count <= wait_latency;
                      state_after_wait <= STATE_PRE_POST_PROC;
                    end
                  end
                end
              end
            end
          end
        end

        STATE_MULT_ADD: begin
          // loop variable is kk
          if (kk + 1 < n) begin
            kk <= kk + 1;
          end else begin
            kk <= 0;
            state <= STATE_WAIT;
            wait_count <= wait_latency;
            state_after_wait <= STATE_IDLE;
          end
        end

        STATE_WAIT: begin
          if (wait_count > 0) begin
            wait_count <= wait_count - 1;
          end else begin
            state <= state_after_wait;
            state_after_wait <= STATE_IDLE;
          end
        end

      endcase
    end
    // $strobe("state=%d\tstage=%d\tjj=%d\tkk=%d", state, stage, jj, kk);
  end

  // NTT/INTT address generation
  logic [max_logn-1:0] ntt_index0, ntt_index1;
  always_comb begin
    // default values
    pr_in.bfu_mode = 2'b00;
    pr_in.w_phi = 0;
    pr_in.w_phi_interval = 0;
    pr_in.update_w_phi = 0;
    pr_in.pre_post_proc = 0;
    pr_in.conf_w = 0;
    r_addr_0 = 0;
    r_bank_0 = 0;
    r_en_0 = 0;
    r_addr_1 = 0;
    r_bank_1 = 0;
    r_en_1 = 0;
    pr_in.w_addr_0 = 0;
    pr_in.w_bank_0 = 0;
    pr_in.w_en_0 = 0;
    pr_in.w_addr_1 = 0;
    pr_in.w_bank_1 = 0;
    pr_in.w_en_1 = 0;

    pr_in.seq_mode = 0;

    // debug
`ifndef SYNTHESIS
    pr_in.state = state;
`endif
    // generte butterfly index
    case (ll)
      2'b00: begin
        ntt_index0 = jj + kk;
      end
      2'b01: begin
        ntt_index0 = jj + kk + 2;
      end
      2'b10: begin
        ntt_index0 = jj + kk + (m << 1);
      end
      default: begin
        ntt_index0 = jj + kk + (m << 1) + 2;
      end
    endcase
    ntt_index1 = ntt_index0 + 1;

    // Bit-reversed kk
    kk_rev = bit_rev(kk, logn);
    kk_intt_phy = cnt2intt_addr(kk, logn);


    // generate read/write address/bank
    case (state)
      STATE_CONF: begin
        pr_in.bfu_mode = 2'b11;
        pr_in.conf_w = 1;
        pr_in.w_phi = w_array[kk];
        pr_in.w_phi_interval = w_array[kk];

        // if last butterfly in the inner loop and hold is not asserted
        if (first_hold) begin
          pr_in.conf_w = 1;
        end else begin
          pr_in.conf_w = 0;
        end
        // read/write signals are default to zero
      end

      STATE_NTT_INTT: begin
        pr_in.bfu_mode = 2'b00;
        pr_in.w_phi = curr_w;
        pr_in.w_phi_interval = w_array[stage];
        pr_in.seq_mode = 1;

        // if last butterfly in the inner loop and hold is not asserted
        if (first_hold) begin
          pr_in.update_w_phi = 1;
        end else begin
          pr_in.update_w_phi = 0;
        end

        if (hold) begin  // when waiting for w to be updated
          pr_in.bfu_mode = 2'b11;
          // read/write addr/en are default to 0
        end else begin
          // read both inputs

          r_addr_0 = ntt_index0[max_logn-1:2];
          r_bank_0 = {poly_idx, ntt_index0[1:0]};
          r_en_0 = 1;

          r_addr_1 = ntt_index1[max_logn-1:2];
          r_bank_1 = {poly_idx, ntt_index1[1:0]};
          r_en_1 = 1;

          pr_in.w_addr_0 = r_addr_0;
          pr_in.w_bank_0 = r_bank_0;
          pr_in.w_en_0 = 1;

          pr_in.w_addr_1 = r_addr_1;
          pr_in.w_bank_1 = r_bank_1;
          pr_in.w_en_1 = 1;
        end
      end


      STATE_PRE_POST_PROC: begin
        pr_in.pre_post_proc = 1;
        pr_in.bfu_mode = 2'b11;
        pr_in.w_phi = curr_phi;
        pr_in.w_phi_interval = phi;
        pr_in.seq_mode = 0;

        // if last butterfly in the inner loop and hold is not asserted
        if (first_hold) begin
          pr_in.update_w_phi = 1;
        end else begin
          pr_in.update_w_phi = 0;
        end

        if (hold) begin  // when waiting for w to be updated
          // read/write addr/en are default to 0

        end else begin
          // loop variable is kk
          // read from only one bank
          // w/r port 1 not used

          if (subop == NTT_SUBOP_NTT_OR_ADD) begin  // pre-process for ntt
            r_addr_0 = kk_rev[max_logn-1:2];
            r_bank_0 = {poly_idx, kk_rev[1:0]};
          end else begin  // post-process for intt
            r_addr_0 = kk_intt_phy[max_logn-1:2];
            r_bank_0 = {poly_idx, kk_intt_phy[1:0]};
          end
          r_en_0 = 1;

          pr_in.w_addr_0 = r_addr_0;
          pr_in.w_bank_0 = r_bank_0;
          pr_in.w_en_0 = 1;
        end

      end

      STATE_MULT_ADD: begin
        if (subop == NTT_SUBOP_NTT_OR_ADD) begin
          pr_in.bfu_mode = 2'b10;  // ADD
        end else begin
          pr_in.bfu_mode = 2'b11;  // MULT
        end

        // loop variable is kk_rev
        // read the same bank from both poly, write back to poly 1
        // w/r port 1 not used
        pr_in.seq_mode = 0;

        r_addr_0 = kk[max_logn-1:2];
        r_bank_0 = {1'b0, kk[1:0]};
        r_en_0 = 1;

        r_addr_1 = kk[max_logn-1:2];
        r_bank_1 = {1'b1, kk[1:0]};
        r_en_1 = 1;

        pr_in.w_addr_0 = r_addr_1;
        pr_in.w_bank_0 = r_bank_1;
        pr_in.w_en_0 = 1;
      end
    endcase
  end

endmodule

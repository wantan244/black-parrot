module ntt_alu
  import bp_common_pkg::*;
  #(parameter max_logn = 12,
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

    output logic [max_logn-2:0] r_addr_0,
    output logic [max_logn-2:0] r_addr_1,
    output logic [1:0] r_bank_0,
    output logic [1:0] r_bank_1,
    output logic r_en_0,
    output logic r_en_1,
    input [max_logq-1:0] r_data_0,
    input [max_logq-1:0] r_data_1,

    output logic [max_logn-2:0] w_addr_0,
    output logic [max_logn-2:0] w_addr_1,
    output logic [1:0] w_bank_0,
    output logic [1:0] w_bank_1,
    output logic w_en_0,
    output logic w_en_1,
    output logic [max_logq-1:0] w_data_0,
    output logic [max_logq-1:0] w_data_1,

    input alu_op_e op,
    output logic done
);

  // total_delay = mem_read + (BFU) + seq1
  localparam total_delay = 1 + (3 * dm + 2) + 1;

  // Address conversion for writing
  function automatic [max_logn-1:0] bit_rev(input [max_logn-1:0] in,
                                              input [max_logn-1:0] logn);
    logic [max_logn-1:0] in_rev;
    in_rev = {<<{in}};
    return in_rev >> (max_logn - logn);
  endfunction

  // Address conversion for reading
  function automatic [max_logn-1:0] cnt2phyaddr(input [max_logn-1:0] in,
                                                  input [max_logn-1:0] logn);
    // output = ({in_rev[logn-2:0], in_rev[logn-1]})
    logic [max_logn-1:0] in_rev, res, all_ones;
    all_ones = '1;
    in_rev = bit_rev(in, logn);
    res = {in_rev[max_logn-2:0], in_rev[logn-1]};
    res = res & (all_ones >> (max_logn - logn));
    return res;
  endfunction

  // if (dm < 2) $error("dm must be greater than or equal to 2.");
  // if (n/4 < total_delay) $warning("n too small.");

  typedef enum logic [2:0] {
    STATE_IDLE          = 0,
    STATE_CONF,
    STATE_PRE_POST_PROC,
    STATE_NTT_INTT,
    STATE_MULT_ADD
  } ntt_state_e;
  ntt_state_e state;

  typedef enum logic {
    NTT_SUBOP_NTT_OR_ADD   = 1'b0,
    NTT_SUBOP_INTT_OR_MULT
  } ntt_subop_e;


  logic [max_logq-1:0] q;
  logic [(max_logq+1)-1:0] r;

  logic [max_logq-1:0] bfu_u, bfu_v, bfu_w, bfu_out0, bfu_out1;
  logic [1:0] bfu_mode;

  logic [max_logq-1:0] seq1_in0, seq1_in1, seq1_out0, seq1_out1;
  logic seq1_mode;


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

  seq #(
      .logq(max_logq)
  ) seq1 (
      .clk (clk),
      .in0 (seq1_in0),
      .in1 (seq1_in1),
      .mode(seq1_mode),
      .out0(seq1_out0),
      .out1(seq1_out1)
  );


  // control signals from pipeline registers
  always_comb begin
    if (pr_mem_out.update_w_phi) begin  // if updating w or phi
      bfu_u = pr_mem_out.w_phi;
      bfu_v = pr_mem_out.w_phi_interval;
    end else if (pr_mem_out.pre_post_proc) begin
      bfu_u = r_data_0;
      bfu_v = pr_mem_out.w_phi;
    end else if (pr_mem_out.conf_w) begin
      bfu_u = pr_mem_out.w_phi;
      bfu_v = pr_mem_out.w_phi_interval;
    end else begin
      bfu_u = r_data_0;
      bfu_v = r_data_1;
    end

    bfu_w = pr_mem_out.w_phi;
    bfu_mode = pr_mem_out.bfu_mode;

    seq1_in0 = bfu_out0;
    seq1_in1 = bfu_out1;
    seq1_mode = pr_bfu_out.seq1_mode;

    // output ports
    w_addr_0 = pr_seq1_out.w_addr_0;
    w_addr_1 = pr_seq1_out.w_addr_1;
    w_bank_0 = pr_seq1_out.w_bank_0;
    w_bank_1 = pr_seq1_out.w_bank_1;
    w_en_0 = pr_seq1_out.w_en_0;
    w_en_1 = pr_seq1_out.w_en_1;

    w_data_0 = seq1_out0;
    w_data_1 = seq1_out1;

    done = (state == STATE_IDLE);
  end

  typedef struct packed {
    logic seq1_mode;
    logic [max_logn-2:0] w_addr_0, w_addr_1;
    logic [1:0] w_bank_0, w_bank_1;
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
  ntt_stage_reg pr_mem_out, pr_bfu_out, pr_seq1_out;
  assign pr_mem_out  = pr[0];
  assign pr_bfu_out  = pr[(1+(3*dm+2))-1];
  assign pr_seq1_out = pr[(1+(3*dm+2)+1)-1];


  logic [max_logn:0] n, logn, stage, m, jj, kk, kk_rev, kk_phy;
  logic hold, first_hold;
  logic seq_flag;
  logic [max_logq-1:0] curr_w;
  logic [max_logq-1:0] w_array[max_logn-1:0];
  logic [max_logq-1:0] phi, curr_phi;
  logic [max_logq-1:0] n_inv;

  ntt_subop_e subop;



  logic poly_idx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;

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
              m <= 2;
              jj <= 0;
              kk <= 0;
              curr_w <= 1;
              curr_phi <= 1;
              hold <= 0;
              first_hold <= 0;
              seq_flag <= 0;

              poly_idx <= 0;
              subop <= NTT_SUBOP_NTT_OR_ADD;
              state <= STATE_PRE_POST_PROC;
            end
            OP_NTT1: begin
              stage <= 0;
              m <= 2;
              jj <= 0;
              kk <= 0;
              curr_w <= 1;
              curr_phi <= 1;
              hold <= 0;
              first_hold <= 0;
              seq_flag <= 0;

              poly_idx <= 1;
              subop <= NTT_SUBOP_NTT_OR_ADD;
              state <= STATE_PRE_POST_PROC;
            end
            OP_INTT0: begin
              stage <= 0;
              m <= 2;
              jj <= 0;
              kk <= 0;
              curr_w <= 1;
              curr_phi <= n_inv;
              hold <= 0;
              first_hold <= 0;
              seq_flag <= 0;

              poly_idx <= 0;
              subop <= NTT_SUBOP_INTT_OR_MULT;
              state <= STATE_NTT_INTT;
            end
            OP_INTT1: begin
              stage <= 0;
              m <= 2;
              jj <= 0;
              kk <= 0;
              curr_w <= 1;
              curr_phi <= n_inv;
              hold <= 0;
              first_hold <= 0;
              seq_flag <= 0;

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
                state <= STATE_NTT_INTT;
              end else begin  // INTT
                state <= STATE_IDLE;
              end
            end
          end
        end

        STATE_NTT_INTT: begin

          /*
    for (stage=0, m=n;stage<max_logn;stage++, m=m/2)
    {
      w=1;
      w_interval=w_pre[stage];
      for (jj=0;jj<n;jj+=m)
      {
        for (kk=0;kk<m/2;kk++)
        {
          idx0=kk+jj;
          idx1=kk+jj+m/2;

          a[idx0]= a[idx0]+w*a[idx1];
          a[idx1]= a[idx0]-w*a[idx1];
        }
        w=w*w_interval;
      }
    }
*/
          if (hold) begin
            first_hold <= 0;
            if (pr_bfu_out.update_w_phi) begin
              hold   <= 0;
              curr_w <= bfu_out0;
            end
          end else begin
            if (m != n) begin
              seq_flag <= !seq_flag;
            end else begin
              seq_flag <= 0;
            end

            if ((kk + (m >> 1)) < (n >> 1)) begin
              kk <= kk + (m >> 1);
            end else begin
              hold <= 1;
              first_hold <= 1;
              kk <= 0;
              if (jj + 1 < (m >> 1)) begin
                jj <= jj + 1;
              end else begin
                jj <= 0;
                // new iteration of j loop, overwrite hold condition
                hold <= 0;
                first_hold <= 0;

                if (stage + 1 < logn) begin
                  stage <= stage + 1;
                  m <= (m << 1);
                  curr_w <= 1;
                end else begin
                  stage <= 0;
                  m <= 2;
                  if (subop == NTT_SUBOP_NTT_OR_ADD) begin  //NTT, jump to IDLE
                    state <= STATE_IDLE;
                  end else begin  // INTT, jump to post-proc
                    state <= STATE_PRE_POST_PROC;
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
            state <= STATE_IDLE;
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

    // pr_in.seq0_mode = 0;
    pr_in.seq1_mode = 0;

    // debug
`ifndef SYNTHESIS
    pr_in.state = state;
`endif
    // generte butterfly index
    ntt_index0 = ((kk + jj) << 1);
    ntt_index1 = ((kk + jj) << 1) + 1;

    // Bit-reversed kk
    kk_rev = bit_rev(kk, logn);
    kk_phy = cnt2phyaddr(kk, logn);

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

        // if last butterfly in the inner loop and hold is not asserted
        if (first_hold) begin
          pr_in.update_w_phi = 1;
        end else begin
          pr_in.update_w_phi = 0;
        end

        if (hold) begin  // when waiting for w to be updated
          pr_in.seq1_mode = seq_flag;
          pr_in.bfu_mode  = 2'b11;
          // read/write addr/en are default to 0
        end else begin
          // read both inputs
          pr_in.seq1_mode = seq_flag;

          r_addr_0 = ntt_index0[max_logn-1:1];
          r_bank_0 = {poly_idx, ntt_index0[0]};
          r_en_0 = 1;

          r_addr_1 = ntt_index1[max_logn-1:1];
          r_bank_1 = {poly_idx, ntt_index1[0]};
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

        // if last butterfly in the inner loop and hold is not asserted
        if (first_hold) begin
          pr_in.update_w_phi = 1;
        end else begin
          pr_in.update_w_phi = 0;
        end

        if (hold) begin  // when waiting for w to be updated
          pr_in.seq1_mode = 0;
          // read/write addr/en are default to 0

        end else begin
          // loop variable is kk
          // read from only one bank
          // w/r port 1 not used
          pr_in.seq1_mode = 0;

          if (subop == NTT_SUBOP_NTT_OR_ADD) begin  // pre-process
            r_addr_0 = kk_rev[max_logn-1:1];
            r_bank_0 = {poly_idx, kk_rev[0]};
          end else begin  // post_proc
            r_addr_0 = kk_phy[max_logn-1:1];
            r_bank_0 = {poly_idx, kk_phy[0]};
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
        pr_in.seq1_mode = 0;

        r_addr_0 = kk_rev[max_logn-1:1];
        r_bank_0 = {1'b0, kk_rev[0]};
        r_en_0 = 1;

        r_addr_1 = kk_rev[max_logn-1:1];
        r_bank_1 = {1'b1, kk_rev[0]};
        r_en_1 = 1;

        pr_in.w_addr_0 = r_addr_1;
        pr_in.w_bank_0 = r_bank_1;
        pr_in.w_en_0 = 1;
      end
    endcase
  end

endmodule

`ifndef BP_COMMON_ACCELERATOR_PKGDEF_SVH
`define BP_COMMON_ACCELERATOR_PKGDEF_SVH

  //vector-dot-product accelerator CSR indexes
  localparam inputa_ptr_csr_idx_gp = 20'h0_0000;
  localparam inputb_ptr_csr_idx_gp = 20'h0_0008; 
  localparam input_len_csr_idx_gp  = 20'h0_0010;
  localparam start_cmd_csr_idx_gp  = 20'h0_0018;
  localparam res_status_csr_idx_gp = 20'h0_0020;
  localparam res_ptr_csr_idx_gp    = 20'h0_0028;
  localparam res_len_csr_idx_gp    = 20'h0_0030;
  localparam operation_csr_idx_gp  = 20'h0_0038;


  //loopback accelerator CSR indexes
  localparam accel_wr_cnt_csr_idx_gp = 20'h0_0000;

  //HE encryption accelerator CSR indexes
  localparam dma_spm_sel_csr_idx_gp = 20'h0_0000;
  localparam dma_address_csr_idx_gp = 20'h0_0008; 
  localparam dma_length_csr_idx_gp  = 20'h0_0010;
  localparam dma_start_csr_idx_gp  = 20'h0_0018;
  localparam encryption_start_csr_idx_gp  = 20'h0_0020;
  localparam dma_done_signal_csr_idx_gp = 20'h0_0028;
  localparam encryption_done_signal_csr_idx_gp = 20'h0_0030;

  //HE unified ENC-DEC accelerator  
  localparam cfg_start_csr_idx_gp = 20'h0_0000;
  localparam q_csr_idx_gp = 20'h0_0008;
  localparam n_csr_idx_gp = 20'h0_0010;
  localparam enc_dec_csr_idx_gp = 20'h0_0018;
  localparam a1_ptr_csr_idx_gp = 20'h0_0020;
  localparam b1_ptr_csr_idx_gp = 20'h0_0028;
  localparam c1_ptr_csr_idx_gp = 20'h0_0030;
  localparam wb1_ptr_csr_idx_gp = 20'h0_0038;
  localparam a2_ptr_csr_idx_gp = 20'h0_0040;
  localparam b2_ptr_csr_idx_gp = 20'h0_0048;
  localparam c2_ptr_csr_idx_gp = 20'h0_0050;
  localparam wb2_ptr_csr_idx_gp = 20'h0_0058;
  localparam cfg_done_csr_idx_gp = 20'h0_0060;
  localparam res_stat_csr_idx_gp = 20'h0_0068;

  localparam alu_cfg_r_csr_idx_gp = 20'h0_0070;
  localparam alu_cfg_w_csr_idx_gp = 20'h0_0078;
  localparam alu_cfg_phi_csr_idx_gp = 20'h0_0080;
  localparam alu_cfg_n_inv_csr_idx_gp = 20'h0_0088;

  typedef enum logic [2:0] {
                            OP_NOOP,
                            OP_CONF,
                            OP_NTT0,   // R/W bank 0 and 1
                            OP_NTT1,   // R/W bank 2 and 3
                            OP_MULT,   // Read all banks, write to bank 2 and 3
                            OP_ADD,    // Read all banks, write to bank 2 and 3
//                            OP_INTT0,  // R/W bank 0 and 1
                            OP_INTT1   // R/W bank 2 and 3
                            } alu_op_e;

`endif

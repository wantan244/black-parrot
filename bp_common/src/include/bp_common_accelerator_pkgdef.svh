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

`endif

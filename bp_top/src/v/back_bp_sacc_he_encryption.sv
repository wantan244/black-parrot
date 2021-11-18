`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_sacc_loopback
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_bedrock_mem_if_widths(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p, cce)
   , localparam cfg_bus_width_lp= `bp_cfg_bus_width(hio_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p)
   )
  (input                                        clk_i
   , input                                      reset_i

   , input [lce_id_width_p-1:0]                 lce_id_i

   , input [cce_mem_header_width_lp-1:0]        io_cmd_header_i
   , input [cce_block_width_p-1:0]              io_cmd_data_i
   , input                                      io_cmd_v_i
   , output logic                               io_cmd_ready_o

   , output logic [cce_mem_header_width_lp-1:0] io_resp_header_o
   , output logic [cce_block_width_p-1:0]       io_resp_data_o
   , output logic                               io_resp_v_o
   , input                                      io_resp_yumi_i

   , output logic [cce_mem_header_width_lp-1:0] io_cmd_header_o
   , output logic [cce_block_width_p-1:0]       io_cmd_data_o
   , output logic                               io_cmd_v_o
   , input                                      io_cmd_yumi_i

   , input [cce_mem_header_width_lp-1:0]        io_resp_header_i
   , input [cce_block_width_p-1:0]              io_resp_data_i
   , input                                      io_resp_v_i
   , output logic                               io_resp_ready_o
   );

  // CCE-IO interface is used for uncached requests-read/write memory mapped CSR
  `declare_bp_bedrock_mem_if(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p, cce);
  `declare_bp_memory_map(paddr_width_p, daddr_width_p);
  `bp_cast_o(bp_bedrock_cce_mem_header_s, io_cmd_header);
  `bp_cast_i(bp_bedrock_cce_mem_header_s, io_resp_header);
  `bp_cast_i(bp_bedrock_cce_mem_header_s, io_cmd_header);
  `bp_cast_o(bp_bedrock_cce_mem_header_s, io_resp_header);

  assign io_cmd_ready_o = 1'b1;
  assign io_resp_ready_o = 1'b1;
  assign io_cmd_v_o = 1'b0;

  logic [63:0] spm_data_lo, spm_data_li, csr_data;
  logic [paddr_width_p-1:0]  resp_addr;

  logic [vaddr_width_p-1:0] spm_addr; 
  logic spm_read_v_li, spm_write_v_li, spm_v_lo, resp_v_lo;

  bp_bedrock_cce_mem_payload_s  resp_payload;
  bp_bedrock_msg_size_e         resp_size;
  bp_bedrock_mem_type_e         resp_msg;
  bp_local_addr_s           local_addr_li;
  bp_global_addr_s          global_addr_li;

  assign global_addr_li = io_cmd_header_cast_i.addr;
  assign local_addr_li = io_cmd_header_cast_i.addr;

  assign io_resp_header_cast_o = '{msg_type       : resp_msg
                                   ,addr          : resp_addr
                                   ,payload       : resp_payload
                                   ,subop         : e_bedrock_store
                                   ,size          : resp_size
                                   };
  assign io_resp_data_o = spm_v_lo ? spm_data_lo : csr_data;

  assign io_resp_v_o = spm_v_lo | resp_v_lo;
  always_ff @(posedge clk_i) begin
    spm_v_lo <= u_spm_read_v_li | e1_spm_read_v_li | e0_m_spm_read_v_li;

    if (reset_i) begin
      spm_v_lo <= '0;
      resp_v_lo <= 0;
      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      eo_m_spm_write_v_li <= '0;

    end
    else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == '0))
    begin
      resp_size    <= io_cmd_header_cast_i.size;
      resp_payload <= io_cmd_header_cast_i.payload;
      resp_addr    <= io_cmd_header_cast_i.addr;
      resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);

      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      eo_m_spm_write_v_li <= '0;

      resp_v_lo <= 1;
      unique
      case (local_addr_li.addr)
        dma_done_signal_csr_idx_gp : csr_data <= encryption_done;
        encryption_done_signal_csr_idx_gp : csr_data <= encryption_done;
        default : begin end
      endcase
    end 
    else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == '0))
    begin
      resp_size    <= io_cmd_header_cast_i.size;
      resp_payload <= io_cmd_header_cast_i.payload;
      resp_addr    <= io_cmd_header_cast_i.addr;
      resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);

      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      eo_m_spm_write_v_li <= '0;

      resp_v_lo <= 1;
      unique
      case (local_addr_li.addr)
        dma_spm_sel_csr_idx_gp : dma_spm_sel <= io_cmd_data_i;
        dma_address_csr_idx_gp : dma_address <= io_cmd_data_i;
        dma_length_csr_idx_gp  : dma_length  <= io_cmd_data_i;
        dma_start_csr_idx_gp   : dma_start   <= io_cmd_data_i;
        default : begin end
      endcase
    end

    else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == 1))
    begin
      resp_size    <= io_cmd_header_cast_i.size;
      resp_payload <= io_cmd_header_cast_i.payload;
      resp_addr    <= io_cmd_header_cast_i.addr;
      resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
      unique
      case (spm_sel)
         64'd0 : 
           begin
              u_spm_write_v_li <= '1;
              e1_spm_write_v_li <= '0;
              eo_m_spm_write_v_li <= '0;
           end;
        64'd1 : 
           begin
              u_spm_write_v_li <= '0;
              e1_spm_write_v_li <= '1;
              eo_m_spm_write_v_li <= '0;
           end;
        64'd0 : 
           begin
              u_spm_write_v_li <= '0;
              e1_spm_write_v_li <= '0;
              eo_m_spm_write_v_li <= '1;
           end;
        default : begin end
      endcase
      resp_v_lo <= 1;
      spm_data_li  <= io_cmd_data_i;
      spm_addr <= io_cmd_header_cast_i.addr;
    end
    else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == 1))
    begin
      resp_size    <= io_cmd_header_cast_i.size;
      resp_payload <= io_cmd_header_cast_i.payload;
      resp_addr    <= io_cmd_header_cast_i.addr;
      resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
      spm_read_v_li  <= '1;
      u_spm_write_v_li <= '0;
      e1_spm_write_v_li <= '0;
      eo_m_spm_write_v_li <= '0;
      resp_v_lo <= 0;
      spm_addr <= io_cmd_header_cast_i.addr;
    end
    else
    begin
      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      eo_m_spm_write_v_li <= '0;

      resp_v_lo <= 0;
      end
  end


  //SPM
  wire [`BSG_SAFE_CLOG2(20)-1:0] spm_addr_li = spm_addr >> 3;

  //SPM 
  bsg_mem_1rw_sync
    #(.width_p(32), .els_p(4096))
    u_sample
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(spm_data_li)
      ,.addr_i(spm_addr_li)
      ,.v_i(u_spm_read_v_li | u_spm_write_v_li)
      ,.w_i(u_spm_write_v_li)
      ,.data_o(spm_data_lo)
      );


     bsg_mem_1rw_sync
    #(.width_p(32), .els_p(4096))
    e1_sample
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(spm_data_li)
      ,.addr_i(spm_addr_li)
      ,.v_i(e1_spm_read_v_li | e1_spm_write_v_li)
      ,.w_i(e1_spm_write_v_li)
      ,.data_o(spm_data_lo)
      );


     bsg_mem_1rw_sync
    #(.width_p(32), .els_p(4096))
    m_e0_sample
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(spm_data_li)
      ,.addr_i(spm_addr_li)
      ,.v_i(m_e0_spm_read_v_li | m_e0_spm_write_v_li)
      ,.w_i(m_e0_spm_write_v_li)
      ,.data_o(spm_data_lo)
      );



   typedef enum logic [3:0]{
    RESET
   , WAIT_START
   , FETCH
   }

   always_comb begin
      state_n = state_r;
      case (state_r)
        RESET: begin
           state_n = reset_i ? RESET : WAIT_START;
           dma_done = 0;
           io_cmd_v_o = 1'b0;
        end
        CMD_WAIT: begin
           state_n = dma_start ? FETCH : (encryption_start ? ENCRYPTION : CMD_WAIT);
           dma_done = 0;
        end
        FETCH: begin
           state_n = (dma_counter == (dma_length-1)) ? CMD_WAIT : WAIT_DMA;
           
        end
        WAIT_DMA: begin
           state_n = io_resp_v_i ? FETCH : WAIT_DMA;
           
        end
        ENCRYPTION: begin
           io_cmd_v_o = 1'b0;
        end
      endcase 
   end // always_comb

   
   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         state_r <= RESET;
      end
      else begin
         state_r <= state_n;
      end
   end
   
     
   endmodule


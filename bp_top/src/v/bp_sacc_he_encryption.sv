`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_sacc_he_encryption
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

  logic [31:0] u_spm_data_lo, u_spm_data_lo_en, spm_data_li, csr_data;
  logic [paddr_width_p-1:0]  resp_addr;

  logic [63:0] dma_address, dma_spm_sel, dma_length, dma_start, dma_done_signal, encryption_done_signal, dma_counter;
   
  logic [vaddr_width_p-1:0] spm_addr; 
  logic u_spm_read_v_li, u_spm_write_v_li, u_spm_v_lo, resp_v_lo, spm_v_lo;
  logic e1_spm_read_v_li, e1_spm_write_v_li, e1_spm_v_lo, e1_resp_v_lo;
  logic e0_m_spm_read_v_li, e0_m_spm_write_v_li, e0_m_spm_v_lo, e0_m_resp_v_lo;
  logic dma_done, encryption_done, encryption_start, dma_end; 
       
  bp_bedrock_cce_mem_payload_s  resp_payload, cmd_payload;
  bp_bedrock_msg_size_e         resp_size;
  bp_bedrock_mem_type_e         resp_msg;
  bp_local_addr_s           local_addr_li;
  bp_global_addr_s          global_addr_li;

  assign cmd_payload.lce_id = lce_id_i;
  assign cmd_payload.uncached = 1;

  //unused fields
  assign cmd_payload.state = '0;
  assign cmd_payload.way_id = '0;
  assign cmd_payload.did = '0;
  assign cmd_payload.prefetch = '0;
  assign cmd_payload.speculative = '0;
   
  assign global_addr_li = io_cmd_header_cast_i.addr;
  assign local_addr_li = io_cmd_header_cast_i.addr;

  assign io_resp_header_cast_o = '{msg_type       : resp_msg
                                   ,addr          : resp_addr
                                   ,payload       : resp_payload
                                   ,subop         : e_bedrock_store
                                   ,size          : resp_size
                                   };
   
  assign io_resp_data_o = spm_v_lo ? u_spm_data_lo : csr_data;
  assign io_resp_v_o = spm_v_lo | resp_v_lo;


   typedef enum logic [3:0]{
    RESET
   ,CMD_WAIT
   ,FETCH
   ,WAIT_DMA
   ,ENCRYPTION
   } state_e;
   state_e state_r, state_n;

   always_ff @(posedge clk_i) begin
      dma_end <= dma_done ? 1 : dma_end;
      if(reset_i) begin
         state_r <= RESET;
         dma_done <= 0;
         dma_end <= 0;
      end
      else begin
         state_r <= state_n;
         dma_done <= (dma_counter == (dma_length-1));
      end
   end
   

   always_comb begin
      state_n = state_r;
      case (state_r)
        RESET: begin
           state_n = reset_i ? RESET : CMD_WAIT;
           encryption_done = 0;
           io_cmd_v_o = 1'b0;
           io_cmd_header_cast_o <= '0;
        end
        CMD_WAIT: begin
           state_n = (dma_start && ~dma_end) ? FETCH : (encryption_start ? ENCRYPTION : CMD_WAIT);
           encryption_done = 0;
           io_cmd_v_o = dma_done && ~dma_end;
           io_cmd_header_cast_o.size <= e_bedrock_msg_size_8;
           io_cmd_header_cast_o.payload <= cmd_payload;
           io_cmd_header_cast_o.addr <= 40'h30_0000;
           io_cmd_header_cast_o.subop <= e_bedrock_store;
           io_cmd_header_cast_o.msg_type.mem <= e_bedrock_mem_uc_wr;
           io_cmd_data_o <= '1;
           /*io_cmd_v_o = 1'b0;
           io_cmd_header_cast_o <= '0;*/
        end
        FETCH: begin
           state_n = (dma_counter == (dma_length-1)) ? CMD_WAIT : WAIT_DMA;
           encryption_done = 0;
           io_cmd_v_o = 1'b1;
           io_cmd_header_cast_o.size <= e_bedrock_msg_size_4;
           io_cmd_header_cast_o.payload <= cmd_payload;
           io_cmd_header_cast_o.addr <= dma_address + (dma_counter*4);
           io_cmd_header_cast_o.subop <= e_bedrock_store;
           io_cmd_header_cast_o.msg_type.mem <= e_bedrock_mem_uc_wr;
        end
        WAIT_DMA: begin
           state_n = io_resp_v_i ? FETCH : WAIT_DMA;
           encryption_done = 0;
           io_cmd_v_o = 1'b0;
           io_cmd_header_cast_o <= '0;
        end
        ENCRYPTION: begin
           io_cmd_v_o = 1'b0;
           io_cmd_header_cast_o <= '0;
           encryption_done = 1;
        end
      endcase 
   end // always_comb

  
  always_ff @(posedge clk_i) begin
    spm_v_lo <= u_spm_read_v_li | e1_spm_read_v_li | e0_m_spm_read_v_li;

    if (reset_i) begin
       
      resp_v_lo <= 0;
      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      e0_m_spm_write_v_li <= '0;

      dma_spm_sel <= 0;
      dma_address <= 0;
      dma_length <= 0;
      dma_start <= 0;
      encryption_start <= 0;

      dma_counter <= 0;

      spm_v_lo <= 0; 
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
      e0_m_spm_write_v_li <= '0;

      resp_v_lo <= 1;
      unique
      case (local_addr_li.addr)
        dma_done_signal_csr_idx_gp : csr_data <= dma_done | dma_end;
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
      e0_m_spm_write_v_li <= '0;

      resp_v_lo <= 1;
      unique
      case (local_addr_li.addr)
        dma_spm_sel_csr_idx_gp       : dma_spm_sel <= io_cmd_data_i;
        dma_address_csr_idx_gp       : dma_address <= io_cmd_data_i;
        dma_length_csr_idx_gp        : dma_length  <= io_cmd_data_i;
        dma_start_csr_idx_gp         : dma_start   <= io_cmd_data_i;
        encryption_start_csr_idx_gp  : encryption_start <= 1;
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
      case (dma_spm_sel)
         64'd0 : 
           begin
              u_spm_write_v_li <= '1;
              e1_spm_write_v_li <= '0;
              e0_m_spm_write_v_li <= '0;
           end
        64'd1 : 
           begin
              u_spm_write_v_li <= '0;
              e1_spm_write_v_li <= '1;
              e0_m_spm_write_v_li <= '0;
           end
        64'd0 : 
           begin
              u_spm_write_v_li <= '0;
              e1_spm_write_v_li <= '0;
              e0_m_spm_write_v_li <= '1;
           end
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
      u_spm_write_v_li <= '0;
      e1_spm_write_v_li <= '0;
      e0_m_spm_write_v_li <= '0;

       unique
      case (dma_spm_sel)
         64'd0 : 
           begin
              u_spm_read_v_li <= '1;
              e1_spm_read_v_li <= '0;
              e0_m_spm_read_v_li <= '0;
           end
        64'd1 : 
           begin
              u_spm_read_v_li <= '0;
              e1_spm_read_v_li <= '1;
              e0_m_spm_read_v_li <= '0;
           end
        64'd0 : 
           begin
              u_spm_read_v_li <= '0;
              e1_spm_read_v_li <= '0;
              e0_m_spm_read_v_li <= '1;
           end
        default : begin end
      endcase
      resp_v_lo <= 0;
      spm_addr <= io_cmd_header_cast_i.addr;
    end
    else if (io_resp_v_i /*&& (io_resp_header_cast_i.msg_type == e_bedrock_mem_uc_rd)*/)
    begin
       dma_counter <= (state_n >= WAIT_DMA) ? '0 : dma_counter + 1;
    end
    else begin
      u_spm_read_v_li  <= '0;
      u_spm_write_v_li <= '0;

      e1_spm_read_v_li  <= '0;
      e1_spm_write_v_li <= '0;

      e0_m_spm_read_v_li  <= '0;
      e0_m_spm_write_v_li <= '0;

      resp_v_lo <= 0;
      end
  end

   wire [29:0] cipher0_in;
   assign cipher0_in = io_cmd_data_i;
   wire [29:0] cipher1_in;
   assign cipher1_in = io_cmd_data_i;
   logic [29:0] secret_key_in;
   assign secret_key_in = io_cmd_data_i;
   logic [29:0] message_out;
   assign u_spm_data_lo = message_out;
   wire in_ready, out_valid, out_ready, in_valid;
   assign in_valid = io_cmd_v_i;
   

decryption_seal #(
    .q  (1053818881),
    .N  (4096),
    .logq (30),
    .logN (12),
    .N_inv (15)
) decryption(
    .clk(clk_i),
    .reset_n(reset_i),
    // Indicate whether all inputs are valid in the current clock
    .in_valid(in_valid),
    .cipher0_in(cipher0_in),
    .cipher1_in(cipher1_in),
    .secret_key_in(secret_key_in),
    // Assert when the module can consume the current input
    .in_ready(in_ready),
    // Assert when the output data is valid in the corrent clock
    .out_valid(out_valid),
    .message_out(message_out),
    // Indicate whether the outside can consume the current output
    .out_ready(out_ready)
);

   wire [29:0] r0_in;
   assign r0_in= io_cmd_data_i;
   wire [29:0] r1_in;
   assign r1_in= io_cmd_data_i;
   wire [29:0] me0_in;
   assign me0_in= io_cmd_data_i;
   wire [29:0] public_key_a_in;
   assign public_key_a_in= io_cmd_data_i;
   wire [29:0] public_key_b_in;
   assign public_key_b_in= io_cmd_data_i;
   wire  out_valid_en, out_ready_en;
   logic [29:0] cipher0_out;
   assign u_spm_data_lo_en= cipher0_out;
   logic [29:0] cipher1_out;

  encryption_seal #(
  .q (1053818881)
  ,.N (4096)
  ,.logq (30)
  ,.logN (12)
  ,.N_inv (15)
 ) encryption (
   .clk(clk_i),
   .reset_n(reset_i),
   // Indicate whether all inputs are valid in the current clock
   .in_valid(in_valid),
   .r0_in(r0_in),  // u
   .r1_in(r1_in),  // e1
   .me0_in(me0_in),  // m + e0
   .public_key_a_in(public_key_a_in),  // pk1
   .public_key_b_in(public_key_b_in),  // pk0
   // Assert when the module can consume the current input
   .in_ready(in_ready),
   // Assert when the output data is valid in the corrent clock
   .out_valid(out_valid_en),
   .cipher0_out(cipher0_out),
   .cipher1_out(cipher1_out),
   // Indicate whether the outside can consume the current output
   .out_ready(out_ready_en)
 );
   
      
  //SPM
/*  wire [`BSG_SAFE_CLOG2(4096)-1:0] spm_addr_li = spm_addr >> 3;

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
*/

     
   endmodule


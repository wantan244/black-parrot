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

   logic [paddr_width_p-1:0]  resp_addr;
 
   assign io_resp_header_cast_o = '{msg_type       : resp_msg
                                   ,addr          : resp_addr
                                   ,payload       : resp_payload
                                   ,subop         : e_bedrock_store
                                   ,size          : resp_size
                                   };
   
   logic [63:0]               csr_data;
   logic                      resp_v_lo;
   
   assign io_resp_data_o = csr_data;
   assign io_resp_v_o = resp_v_lo;
///////////////////////////////////DMA_FSM///////////////////////////////////////////
   logic                      dma_start, dma_done;
   logic [63:0]               dma_address, dma_cntr;
   
   typedef enum logic [2:0]{
                            RESET_DMA
                            , WAIT_START
                            , FETCH
                            , WAIT_DMA
                            , DONE_DMA
                            } state_dma;
   state_dma state_dma_r, state_dma_n;

   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         state_dma_r <= RESET_DMA;
         dma_cntr <= '0;
      end
      else begin
         state_dma_r <= state_dma_n;
         dma_done <= (n == dma_cntr);
         dma_cntr <= state_dma_n >= WAIT_DMA ? '0 : (io_resp_v_i ? dma_cntr + 1: dma_cntr);
         
      end
   end

   always_comb begin
      state_dma_n = state_dma_r;
      case (state_dma_r)
        RESET_DMA:
          begin
             state_dma_n = reset_i ?  WAIT_START : RESET_DMA;
             done_dma = 0;
             io_cmd_v_o = 0;
             io_cmd_header_cast_o = '0;
             
          end
        WAIT_START:
          begin
             state_dma_n = start_dma ? FETCH : WAIT_START;
             done_dma = 0;
             io_cmd_v_o = 0;
             io_cmd_header_cast_o = '0;
             
          end
        FETCH:
          begin
             state_dma_n = (n-1 == dma_cntr) ?  DONE_DMA : WAIT_DMA;
             io_cmd_v_o = 1;
             done_dma = 0;
             io_cmd_header_cast_o.size = e_bedrock_msg_size_4;
             io_cmd_header_cast_o.payload = cmd_payload;
             io_cmd_header_cast_o.addr = dma_address + (dma_cntr*4) ;
             io_cmd_header_cast_o ;
             
          end
        WAIT_DMA:
          begin
             state_dma_n = io_resp_v_i ? FETCH : WAIT_DMA;
             done_dma = 0;
             io_cmd_v_o = 0;
             io_cmd_header_cast_o = '0;
             
          end
        DONE_DMA:
          begin
             state_dma_n = RESET_DMA;
             done_dma = 1;
             io_cmd_v_o = 0;
             io_cmd_header_cast_o = '0;
             
          end
      endcase 
   end // always_comb

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////EN_DECRYPTION FSM///////////////////////////////
   ////cfg registers
   logic [31:0] q, n, a_ptr, b_ptr, c_ptr;
   logic        cfg_start, cfg_done, enc_dec, res_stat;

   logic        ntt_done;
   
   typedef enum logic [3:0]{
                            RESET
                            , IDLE
                            , CFG
                            , LOAD_A //full_buffer_count = 1
                            , NTT_A  //takes one cycle, full_buffer_count = 1
                            , LOAD_B //parallel with NTT_A, wait here until NTT_A is done, full_buffer_count = 2
                            , NTT_B  //full_buffer_count = 2
                            , MULT   //takes one cycle, call point_wise mul, writeback the resutls to A, full_buffer_count = 2
                            , LOAD_C //load c regardless of MULT state
                            , ADD
                            , DONE
                            } state_e;
   state_e state_r, state_n;

   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         state_r <= RESET;
      end
      else begin
         state_r <= state_n;
      
      
      if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == '0))
        begin
           resp_size    <= io_cmd_header_cast_i.size;
           resp_payload <= io_cmd_header_cast_i.payload;
           resp_addr    <= io_cmd_header_cast_i.addr;
           resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
           resp_v_lo <= 1;
           unique
             case (local_addr_li.addr)
               q_csr_idx_gp           : q <= io_cmd_data_i;
               n_csr_idx_gp           : n <= io_cmd_data_i;
               enc_dec_csr_idx_gp     : enc_dec <= io_cmd_data_i;
               a_ptr_csr_idx_gp       : a_ptr  <= io_cmd_data_i;
               b_ptr_csr_idx_gp       : b_ptr  <= io_cmd_data_i;
               c_ptr_csr_idx_gp       : c_ptr  <= io_cmd_data_i;
               cfg_start_csr_idx_gp   : cfg_start  <= io_cmd_data_i;
               cfg_done_csr_idx_gp    : cfg_done  <= io_cmd_data_i;
               default : begin end
             endcase
        end // if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == '0))
      else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == '0))
        begin
           resp_size    <= io_cmd_header_cast_i.size;
           resp_payload <= io_cmd_header_cast_i.payload;
           resp_addr    <= io_cmd_header_cast_i.addr;
           resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
           resp_v_lo <= 1;
           unique
             case (local_addr_li.addr)
               q_csr_idx_gp           : csr_data <= q;
               n_csr_idx_gp           : csr_data <= n;
               enc_dec_csr_idx_gp     : csr_data <= enc_dec;
               a_ptr_csr_idx_gp       : csr_data <= a_ptr;
               b_ptr_csr_idx_gp       : csr_data <= b_ptr;
               c_ptr_csr_idx_gp       : csr_data <= c_ptr;
               cfg_start_csr_idx_gp   : csr_data <= cfg_start;
               cfg_done_csr_idx_gp    : csr_data <= cfg_done;
               res_stat_csr_idx_gp    : csr_data <= res_stat;
               default : begin end
             endcase
        end // if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == '0))
      else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == 1))
        begin
           resp_size    <= io_cmd_header_cast_i.size;
           resp_payload <= io_cmd_header_cast_i.payload;
           resp_addr    <= io_cmd_header_cast_i.addr;
           resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
           resp_v_lo    <= 1;
        end // if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == 1))
      else if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == 1))
        begin
           resp_size    <= io_cmd_header_cast_i.size;
           resp_payload <= io_cmd_header_cast_i.payload;
           resp_addr    <= io_cmd_header_cast_i.addr;
           resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
           resp_v_lo    <= 0;
        end // if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_rd) & (global_addr_li.hio == 1))
      else
        begin
           resp_v_lo <= 0;      
        end 
         
      end // else: !if(reset_i)
   end
   

   always_comb begin
      state_n = state_r;
      case (state_r)
        RESET:
          begin
             state_n = reset_i ? IDLE : RESET;
             start_dma = 0;
             dma_address = 0;
             
          end
        IDLE:
          begin
             state_n = cfg_start ? CFG : IDLE;
             start_dma = 0;
             dma_address = 0;
             
          end
        CFG:
          begin
             state_n = cfg_done ? LOAD_A : CFG;
             start_dma = 0;
             dma_address =0 ;
             
          end
        LOAD_A:
          begin
             state_n = done_dma ? NTT_A : LOAD_A;
             start_dma = 1;
             dma_address = a_ptr;
 
          end
        NTT_A:
          begin
             state_n = ntt_done ? LOAD_B : NTT_A;
             start_dma = 0;
             dma_address = 0;
             
          end
        LOAD_B:
          begin
             state_n = done_dma ? NTT_B : LOAD_B;
             start_dma = 1;
             dma_address = b_ptr;
             
          end
        NTT_B:
          begin
             state_n = ntt_done ? LOAD_B : DONE;
             start_dma = 0;
             dma_address = 0;
             
          end
        DONE:
          begin
             state_n = RESET;
             start_dma = 0;
             dma_address = 0;
             
          end
      endcase 
   end // always_comb
/////////////////////////////////////////////////////////////////////////////////////

   wire [`BSG_SAFE_CLOG2(n)-1:0] w_addr_a = (start_dma && state_r == LOAD_A) ? dma_addr : ntt_addr_a;
   wire                          w_en_a = (start_dma && state_r == LOAD_A) ? io_resp_v_i : ntt_w_en_a;
   wire [29:0]                   w_data_a = (start_dma && state_r == LOAD_A) ? io_resp_data_i : ntt_w_data_a;
                          
   
   bsg_mem_1rw_sync
     #(.width_p(30), .els_p(n))
   buff_A
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(w_data_a)
      ,.addr_i(r_en_a ? r_addr_a : w_addr_a)
      ,.v_i(w_en_a && r_en_a)
      ,.w_i(w_en_a)
      ,.data_o(r_data_a)
      );

   wire [`BSG_SAFE_CLOG2(n)-1:0] w_addr_b = (start_dma && state_r == LOAD_B) ? dma_addr : ntt_addr_b;
   wire                          w_en_b = (start_dma && state_r == LOAD_B) ? io_resp_v_i : ntt_w_en_b;
   wire [29:0]                   w_data_b = (start_dma && state_r == LOAD_B) ? io_resp_data_i : ntt_w_data_b;

   bsg_mem_1rw_sync
     #(.width_p(30), .els_p(n))
   buff_B
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(w_data_b)
      ,.addr_i(r_en_b ? r_addr_b : w_addr_b)
      ,.v_i(w_en_b && r_en_b)
      ,.w_i(w_en_b)
      ,.data_o(r_data_b)
      );

   //NTT, MUL, ADD submodules 
   //NTT includes address generators, sequencers, BFU
/*   NTT
     #(.q(q) , .n(n))
   ntt_mod 
     (//inputs
      .clk(clk)
      ,.reset(reset)
      ,.start(start)
      ,.r_data_1(r_data_1)
      ,.r_data_2(r_data_2)

      //outputs
      ,.r_en_1(r_en_1)
      ,.r_en_2(r_en_2)
      ,.r_addr_1(r_addr_1)
      ,.r_addr_2(r_addr_2)
      ,.w_addr_1(w_addr_1)
      ,.w_addr_2(w_addr_2)
      ,.w_en_1(w_en_1)
      ,.w_en_2(w_en_2)
      ,.done(done)
      )
  */     
   endmodule


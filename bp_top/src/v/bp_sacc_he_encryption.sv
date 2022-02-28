`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_sacc_he_encryption
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_bedrock_mem_if_widths(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p)
   , localparam cfg_bus_width_lp= `bp_cfg_bus_width(hio_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p)
   , localparam max_he_n_p = 4096
   , localparam max_he_q_p = 30
   , localparam log_max_he_n_p = `BSG_SAFE_CLOG2(max_he_n_p)
   )
  (input                                        clk_i
   , input                                      reset_i

   , input [lce_id_width_p-1:0]                 lce_id_i

   //, input [cce_mem_header_width_lp-1:0]        io_cmd_header_i
   , input [mem_header_width_lp-1:0]            io_cmd_header_i 
   , input [cce_block_width_p-1:0]              io_cmd_data_i
   , input                                      io_cmd_v_i
   , output logic                               io_cmd_ready_o

   //, output logic [cce_mem_header_width_lp-1:0] io_resp_header_o
   , output logic [mem_header_width_lp-1:0] io_resp_header_o
   , output logic [cce_block_width_p-1:0]       io_resp_data_o
   , output logic                               io_resp_v_o
   , input                                      io_resp_yumi_i

   //, output logic [cce_mem_header_width_lp-1:0] io_cmd_header_o
   , output logic [mem_header_width_lp-1:0] io_cmd_header_o 
   , output logic [cce_block_width_p-1:0]       io_cmd_data_o
   , output logic                               io_cmd_v_o
   , input                                      io_cmd_yumi_i

   //, input [cce_mem_header_width_lp-1:0]        io_resp_header_i
   , input [mem_header_width_lp-1:0]        io_resp_header_i
   , input [cce_block_width_p-1:0]              io_resp_data_i
   , input                                      io_resp_v_i
   , output logic                               io_resp_ready_o
   );
   
   // CCE-IO interface is used for uncached requests-read/write memory mapped CSR
   //`declare_bp_bedrock_mem_if(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p, cce);
   `declare_bp_bedrock_mem_if(paddr_width_p, did_width_p, lce_id_width_p, lce_assoc_p);

   `declare_bp_memory_map(paddr_width_p, daddr_width_p);
   
   /*`declare_bp_memory_map(paddr_width_p, daddr_width_p);
   `bp_cast_o(bp_bedrock_cce_mem_header_s, io_cmd_header);
   `bp_cast_i(bp_bedrock_cce_mem_header_s, io_resp_header);
   `bp_cast_i(bp_bedrock_cce_mem_header_s, io_cmd_header);
   `bp_cast_o(bp_bedrock_cce_mem_header_s, io_resp_header);
*/
   
   `bp_cast_o(bp_bedrock_mem_header_s, io_cmd_header);
   `bp_cast_i(bp_bedrock_mem_header_s, io_resp_header);
   `bp_cast_i(bp_bedrock_mem_header_s, io_cmd_header);
   `bp_cast_o(bp_bedrock_mem_header_s, io_resp_header);

   assign io_cmd_ready_o = 1'b1;
   assign io_resp_ready_o = 1'b1;
       
   bp_bedrock_mem_payload_s  resp_payload, cmd_payload;
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
   /////////////////////////////////////////////////////////////////////////////////////   
   ///////////////////////////////////DMA_FSM///////////////////////////////////////////
   logic                        dma_start, dma_load_store, dma_r_en, dma_io_cmd_v_o;
   logic [63:0]                 dma_addr, dma_cntr, dma_len;
   //bp_bedrock_cce_mem_header_s  dma_io_cmd_header_cast_o;
   bp_bedrock_mem_header_s dma_io_cmd_header_cast_o;
   
   logic [cce_block_width_p-1:0] dma_io_cmd_data_o;
   
   typedef enum logic [2:0]{
                            RESET_DMA
                            , FETCH
                            , WAIT_DMA
                            , DONE_DMA
                            } state_dma;
   state_dma dma_state_r, dma_state_n;

   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         dma_state_r <= RESET_DMA;
         dma_cntr <= '0;
         
      end
      else begin
         dma_state_r <= dma_state_n;
         dma_cntr <= (dma_state_n > WAIT_DMA || dma_state_r == RESET_DMA) ? '0 : (io_resp_v_i ? dma_cntr + 1: dma_cntr);
      end
   end

   always_comb begin
      dma_state_n = dma_state_r;
      case (dma_state_r)
        RESET_DMA:
          begin
             dma_state_n = dma_start ?  FETCH : RESET_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             dma_r_en = dma_start;
             
          end
        FETCH:
          begin
             dma_state_n = (dma_len == dma_cntr) ?  DONE_DMA : WAIT_DMA;
             dma_io_cmd_v_o = ~(dma_len == dma_cntr);
             dma_io_cmd_header_cast_o.size = e_bedrock_msg_size_4; // we fetch 64 bit and store 32 bit in each bank (0,1 / 2,3)
             dma_io_cmd_header_cast_o.payload = cmd_payload;
             dma_io_cmd_header_cast_o.addr = dma_addr + (dma_cntr*4) ;
             dma_io_cmd_header_cast_o.msg_type.mem <= dma_load_store ? e_bedrock_mem_uc_wr : e_bedrock_mem_uc_rd;
             dma_r_en = 0;
             
             
          end
        WAIT_DMA:
          begin
             dma_state_n = io_resp_v_i ? FETCH : WAIT_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             dma_r_en= io_resp_v_i && dma_load_store;
             
          end
        DONE_DMA:
          begin
             dma_state_n = RESET_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             dma_r_en = 0;
             
          end
      endcase 
   end // always_comb

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////EN_DECRYPTION FSM///////////////////////////////
   ////cfg registers
   logic [31:0] a1_ptr, b1_ptr, c1_ptr, wb1_ptr, a2_ptr, b2_ptr, c2_ptr, wb2_ptr;
   logic [log_max_he_n_p:0] n;
   logic [max_he_q_p-1:0]   alu_cfg_q;
   logic [max_he_q_p:0]     alu_cfg_r; // r is (max_he_q_p+1) bits
   logic [max_he_q_p-1:0]   alu_cfg_w;
   logic [max_he_q_p-1:0]   alu_cfg_phi;
   logic [max_he_q_p-1:0]   alu_cfg_n_inv;
   
   alu_op_e alu_op;
   
   logic        cfg_start, cfg_done, enc_dec, res_stat;
   logic        alu_done, prev_alu_done, he_io_cmd_v_o, c0_c1;
   //bp_bedrock_cce_mem_header_s  he_io_cmd_header_cast_o;
   bp_bedrock_mem_header_s he_io_cmd_header_cast_o;
   
   logic [cce_block_width_p-1:0] he_io_cmd_data_o;
   logic [63:0]  w_bit_rev_dma_cntr, r_bit_rev_dma_cntr, prev_r_bit_rev_dma_cntr; 
  
   typedef enum logic [4:0]{
                            RESET
                            , HE_CFG
                            , ALU_CFG
                            , LOAD_A
                            , WAIT_ALU_CFG
                            , NTT_A  
                            , LOAD_B //parallel with NTT_A, wait here until NTT_A is done, full_buffer_count = 2
                            , NTT_B
                            , WAIT_NTT_A
                            , MULT   //takes one cycle, call point_wise mul and jump to the next state, writeback the resutls to A, fill_buffer_count = 2
                            , LOAD_C //load c regardless of MULT state, you wont overwire the required inputs of mul, gauranteed
                            , NTT_C
                            , ADD
                            , INTT
                            , WB_RES
                            , DONE
                            , INTR_D
                            } state_e;
   state_e state_r, state_n;

   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         state_r <= RESET;
         cfg_start <= 0;
         cfg_done <= 0;
         c0_c1 <= 0;
         prev_r_bit_rev_dma_cntr <= 0;
         prev_alu_done <= 0;
         resp_v_lo <= 0;
         
      end
      else begin
         state_r <= state_n;
         c0_c1 <= (state_n == DONE) ? ~c0_c1 : c0_c1;
         prev_r_bit_rev_dma_cntr <= r_bit_rev_dma_cntr;
         prev_alu_done <= alu_done;
         
      if (io_cmd_v_i & (io_cmd_header_cast_i.msg_type == e_bedrock_mem_uc_wr) & (global_addr_li.hio == '0))
        begin
           resp_size    <= io_cmd_header_cast_i.size;
           resp_payload <= io_cmd_header_cast_i.payload;
           resp_addr    <= io_cmd_header_cast_i.addr;
           resp_msg     <= bp_bedrock_mem_type_e'(io_cmd_header_cast_i.msg_type);
           resp_v_lo <= 1;
           unique
             case (local_addr_li.addr)
               q_csr_idx_gp           : alu_cfg_q <= io_cmd_data_i;
               n_csr_idx_gp           : n <= io_cmd_data_i;
               enc_dec_csr_idx_gp     : enc_dec <= io_cmd_data_i;
               a1_ptr_csr_idx_gp      : a1_ptr  <= io_cmd_data_i;
               b1_ptr_csr_idx_gp      : b1_ptr  <= io_cmd_data_i;
               c1_ptr_csr_idx_gp      : c1_ptr  <= io_cmd_data_i;
               wb1_ptr_csr_idx_gp     : wb1_ptr  <= io_cmd_data_i;
               a2_ptr_csr_idx_gp      : a2_ptr  <= io_cmd_data_i;
               b2_ptr_csr_idx_gp      : b2_ptr  <= io_cmd_data_i;
               c2_ptr_csr_idx_gp      : c2_ptr  <= io_cmd_data_i;
               wb2_ptr_csr_idx_gp     : wb2_ptr  <= io_cmd_data_i;
               cfg_start_csr_idx_gp   : cfg_start  <= io_cmd_data_i;
               cfg_done_csr_idx_gp    : cfg_done  <= io_cmd_data_i;

               alu_cfg_r_csr_idx_gp     : alu_cfg_r <= io_cmd_data_i;  
               alu_cfg_w_csr_idx_gp     : alu_cfg_w <= io_cmd_data_i;
               alu_cfg_phi_csr_idx_gp   : alu_cfg_phi <= io_cmd_data_i;
               alu_cfg_n_inv_csr_idx_gp : alu_cfg_n_inv <= io_cmd_data_i;
               
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
               q_csr_idx_gp           : csr_data <= alu_cfg_q;
               n_csr_idx_gp           : csr_data <= n;
               enc_dec_csr_idx_gp     : csr_data <= enc_dec;
               a1_ptr_csr_idx_gp      : csr_data <= a1_ptr;
               b1_ptr_csr_idx_gp      : csr_data <= b1_ptr;
               c1_ptr_csr_idx_gp      : csr_data <= c1_ptr;
               wb1_ptr_csr_idx_gp     : csr_data <= wb1_ptr;
               a2_ptr_csr_idx_gp      : csr_data <= a2_ptr;
               b2_ptr_csr_idx_gp      : csr_data <= b2_ptr;
               c2_ptr_csr_idx_gp      : csr_data <= c2_ptr;
               wb2_ptr_csr_idx_gp     : csr_data <= wb2_ptr;
               cfg_start_csr_idx_gp   : csr_data <= cfg_start;
               cfg_done_csr_idx_gp    : csr_data <= cfg_done;
               res_stat_csr_idx_gp    : csr_data <= res_stat;

               alu_cfg_r_csr_idx_gp     : csr_data <= alu_cfg_r;
               alu_cfg_w_csr_idx_gp     : csr_data <= alu_cfg_w;
               alu_cfg_phi_csr_idx_gp   : csr_data <= alu_cfg_phi;
               alu_cfg_n_inv_csr_idx_gp : csr_data <= alu_cfg_n_inv;
               

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
           cfg_start <= 0;
           cfg_done <= 0;
        end 
         
      end // else: !if(reset_i)
   end
   

   always_comb begin
      state_n = state_r;
      case (state_r)
        RESET:
          begin
             state_n = cfg_start ? HE_CFG : RESET;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
             
          end
        HE_CFG:
          begin
             //we first need to config the he with right parameters and then config the alu
             state_n = cfg_done ? ALU_CFG : HE_CFG;
             //////transfer/ntt ==> state_n = cfg_done ? ALU_CFG : HE_CFG;
             
             dma_start = 0;
             dma_addr =0 ;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
              
          end
       ALU_CFG:
         begin
            //precomputing the values inside alu
            //start the config and jump to load a in parallel
             state_n = LOAD_A;
             dma_start = 0;
             dma_addr =0 ;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_CONF;
       
          end
        LOAD_A:
          begin
             //check if the alu config is done before starting any alu operations
             state_n = (dma_state_r == DONE_DMA) ? (enc_dec ? ( alu_done ? LOAD_B : WAIT_ALU_CFG) : (alu_done ? NTT_A : WAIT_ALU_CFG)) : LOAD_A;
             //////transfer/ntt ==> state_n = (dma_state_r == DONE_DMA) ? (alu_done ? LOAD_B : WAIT_ALU_CFG) : LOAD_A;
             
             dma_start = 1;
             dma_addr = c0_c1 ? a2_ptr : a1_ptr;
             //to_do: we can fetch 64-512 bit and take 2-16 cycles to write back into the corresponsing input bank
             dma_len = n; //n >> 1; if we need to fetch n/2*64 bit data and write into 2 banks
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
             
          end 
        WAIT_ALU_CFG:
          begin
             state_n = alu_done ? (enc_dec ? LOAD_B : NTT_A) : WAIT_ALU_CFG;
             //////transfer/ntt ==> state_n = alu_done ? LOAD_B : WAIT_ALU_CFG;
             
             dma_start = 0;
             dma_addr =0 ;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
   
          end
        NTT_A:
          begin
             //start ntt and jump to load b, then check if ntt is done before performing ntt b
             state_n = LOAD_B;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NTT0;
             
          end
        LOAD_B:
          begin
             //check if ntt a is done before calling alu for mull or ntt b
             state_n = (dma_state_r == DONE_DMA) ? (alu_done ? (enc_dec ? MULT : NTT_B) : WAIT_NTT_A) : LOAD_B;
             //////transfer/ntt ==> state_n = (dma_state_r == DONE_DMA) ? LOAD_C : LOAD_B;
             
             dma_start = 1;
             dma_addr = c0_c1 ? b2_ptr : b1_ptr;
             dma_len = n;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
             
          end 
        WAIT_NTT_A:
          begin
             state_n = alu_done ? NTT_B : WAIT_NTT_A;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
          end
        NTT_B:
          begin
             state_n = (alu_done && ~prev_alu_done) ? MULT : NTT_B;
             //to test all the data/computation results return back in bank0-1 
             //state_n = (alu_done && ~prev_alu_done) ? WB_RES : NTT_B;
             
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = prev_alu_done ? OP_NTT1 : OP_NOOP;
             
          end
        MULT:
          begin
             //to_do: we can overlap mult with load_c
             //since load is slower, we won't overwrite the inputs
             state_n = (alu_done && ~prev_alu_done) ? LOAD_C : MULT;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = prev_alu_done ? OP_MULT : OP_NOOP;
             
          end
        LOAD_C:
          begin
             state_n = (dma_state_r == DONE_DMA) ? (enc_dec ? ADD : NTT_C) : LOAD_C;
             //////transfer/ntt ==> state_n = (dma_state_r == DONE_DMA) ? NTT_C : LOAD_C ;
             
             dma_start = 1;
             dma_addr = c0_c1 ? c2_ptr : c1_ptr;
             dma_len = n;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
             
          end        
        NTT_C:
          begin
             state_n = (alu_done && ~prev_alu_done) ? ADD : NTT_C;
             //////transfer/ntt ==> state_n =  (alu_done && ~prev_alu_done) ? WB_RES : NTT_C;
             
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = prev_alu_done ? OP_NTT0 : OP_NOOP;
             
          end
        ADD:
          begin
             state_n = (alu_done  && ~prev_alu_done) ? (enc_dec ? INTT : WB_RES) : ADD;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = prev_alu_done ? OP_ADD : OP_NOOP;
             
          end
          INTT:
          begin
             state_n = (alu_done && ~prev_alu_done) ? WB_RES : INTT;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = prev_alu_done ? OP_INTT1 : OP_NOOP;
              
          end
        WB_RES:
          begin
             state_n = (dma_state_r == DONE_DMA) ? DONE : WB_RES;
             
             dma_start = 1;
             dma_addr = c0_c1 ? wb2_ptr : wb1_ptr;
             //to_do: we can write back 2 elements (64 bit) at a time (outputs are read from different banks) 
             dma_len = n;
             dma_load_store = 1;
             he_io_cmd_v_o = '0;
             he_io_cmd_header_cast_o = '0;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
              
          end 
        DONE:
          begin
             state_n = (c0_c1 && ~enc_dec) ? LOAD_A : INTR_D;
             //to test all the data/computation results return back in bank0-1 
             ///////////state_n = INTR_D;
             
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             //activate interrupt
             he_io_cmd_v_o = ~c0_c1 || enc_dec;
             
             //to test all the data/computation results return back in bank0-1 
             ///////////he_io_cmd_v_o = c0_c1 || enc_dec;
            
             he_io_cmd_header_cast_o.size = e_bedrock_msg_size_8;
             he_io_cmd_header_cast_o.payload = cmd_payload;
             he_io_cmd_header_cast_o.addr = 40'h30_0000;
             he_io_cmd_header_cast_o.subop = e_bedrock_store;
             he_io_cmd_header_cast_o.msg_type.mem = e_bedrock_mem_uc_wr;
             he_io_cmd_data_o = '1;
             alu_op = OP_NOOP;
             
          end // case: DONE
        INTR_D:
          begin
             state_n = io_resp_v_i ? RESET : INTR_D;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             dma_load_store = 0;
             //deactivate interrupt
             he_io_cmd_v_o = io_resp_v_i;
             he_io_cmd_header_cast_o.size = e_bedrock_msg_size_8;
             he_io_cmd_header_cast_o.payload = cmd_payload;
             he_io_cmd_header_cast_o.addr = 40'h30_0000;
             he_io_cmd_header_cast_o.subop = e_bedrock_store;
             he_io_cmd_header_cast_o.msg_type.mem = e_bedrock_mem_uc_wr;
             he_io_cmd_data_o = '0;
             alu_op = OP_NOOP;
             
          end 
      endcase 
   end 

   assign io_cmd_v_o = he_io_cmd_v_o | dma_io_cmd_v_o;
   assign io_cmd_header_cast_o = he_io_cmd_v_o ? he_io_cmd_header_cast_o : dma_io_cmd_header_cast_o;
   assign io_cmd_data_o = he_io_cmd_v_o ? he_io_cmd_data_o : dma_io_cmd_data_o; 
   /////////////////////////////////////////////////////////////////////////////////////
   //ALU module includes ntt, add, mul, address generators, sequencers, BFU
   logic [log_max_he_n_p-2:0] alu_r_addr_0;
   logic [log_max_he_n_p-2:0] alu_r_addr_1;
   logic [1:0]                             alu_r_bank_0, alu_r_bank_0_delay;
   logic [1:0]                             alu_r_bank_1, alu_r_bank_1_delay;
   logic                                   alu_r_en_0;
   logic                                   alu_r_en_1;
   logic [max_he_q_p-1:0]                  alu_r_data_0;
   logic [max_he_q_p-1:0]                  alu_r_data_1;

   logic [log_max_he_n_p-2:0] alu_w_addr_0;
   logic [log_max_he_n_p-2:0] alu_w_addr_1;
   logic [1:0]                             alu_w_bank_0;
   logic [1:0]                             alu_w_bank_1;
   logic                                   alu_w_en_0;
   logic                                   alu_w_en_1;
   logic [max_he_q_p-1:0]                  alu_w_data_0;
   logic [max_he_q_p-1:0]                  alu_w_data_1;

  

   ntt_alu #(.max_logn(log_max_he_n_p),
             .max_logq(max_he_q_p)
             ) 
   alu (.clk(clk_i),
        .rst_n(~reset_i),
                
        .cfg_logn(`BSG_SAFE_CLOG2(n)),
        .cfg_q(alu_cfg_q),
        .cfg_r(alu_cfg_r),
        .cfg_w(alu_cfg_w),
        .cfg_phi(alu_cfg_phi),
        .cfg_n_inv(alu_cfg_n_inv),
        
        .r_addr_0(alu_r_addr_0),
        .r_addr_1(alu_r_addr_1),
        .r_bank_0(alu_r_bank_0),
        .r_bank_1(alu_r_bank_1),
        .r_en_0(alu_r_en_0),
        .r_en_1(alu_r_en_1),
        .r_data_0(alu_r_data_0),
        .r_data_1(alu_r_data_1),
                
        .w_addr_0(alu_w_addr_0),
        .w_addr_1(alu_w_addr_1),
        .w_bank_0(alu_w_bank_0),
        .w_bank_1(alu_w_bank_1),
        .w_en_0(alu_w_en_0),
        .w_en_1(alu_w_en_1),
        .w_data_0(alu_w_data_0),
        .w_data_1(alu_w_data_1),
                
        .op(alu_op),
        .done(alu_done)
        );

   //////////////////////////////////ADDR CONV//////////////////////////////////////////
   // First layer: Address conversion for writing
   function automatic [log_max_he_n_p-1:0] bit_rev(input [log_max_he_n_p-1:0] in,
                                                   input [log_max_he_n_p-1:0] logn);
      
      logic [log_max_he_n_p-1:0] in_rev;
      in_rev = {<<{in}};
      return in_rev >> (log_max_he_n_p - logn);
  
   endfunction

  // Address conversion for reading
  function automatic [log_max_he_n_p-1:0] cnt2ntt_addr(input [log_max_he_n_p-1:0] in,
                                                       input [log_max_he_n_p-1:0] logn);
    // output = ({in_rev[logn-2:0], in_rev[logn-1]})
    logic [log_max_he_n_p-1:0] in_rev, res, all_ones;
    all_ones = '1;
    in_rev = bit_rev(in, logn);
    res = {in_rev[log_max_he_n_p-2:0], in_rev[logn-1]};
    res = res & (all_ones >> (log_max_he_n_p - logn));
    return res;
  endfunction 

   // Address conversion for reading INTT outputs
   function automatic [log_max_he_n_p-1:0] cnt2intt_addr(input [log_max_he_n_p-1:0] in,
                                                         input [log_max_he_n_p-1:0] logn);
      logic [log_max_he_n_p-1:0]                                                    in_rev, res, all_ones;
      all_ones = '1;
      res = {in[log_max_he_n_p-2:0], in[logn-1]};
      res = res & (all_ones >> (log_max_he_n_p - logn));
      return res;
   endfunction
   //////////////////////////////////BUFFERS////////////////////////////////////////////
   // instantiate 4 banks 
   logic [3:0]                       alu_w_v_i, alu_r_v_i;
   logic [log_max_he_n_p-2:0]        alu_w_addr_i[3:0];
   logic [log_max_he_n_p-2:0]        alu_r_addr_i[3:0];
   logic [max_he_q_p-1:0]            alu_w_data_i[3:0];

      // Delay read bank# for 1 cycle
   always_ff @(posedge clk_i) begin
      alu_r_bank_0_delay <= alu_r_bank_0;
      alu_r_bank_1_delay <= alu_r_bank_1;
   end

   integer ii;
   always_comb begin
      // Instantiate read/write muxes for 4 memory banks. Unroll the loops when needed
      for (ii = 0; ii < 4; ii = ii + 1) begin : gen_mem_input_mux
         // Read port addr/en input
         unique if (alu_r_en_0 && alu_r_bank_0 == ii) begin
            alu_r_v_i[ii] = 'b1;
            alu_r_addr_i[ii] = alu_r_addr_0;
         end else if (alu_r_en_1 && alu_r_bank_1 == ii) begin
            alu_r_v_i[ii] = 'b1;
            alu_r_addr_i[ii] = alu_r_addr_1;
         end else begin
            alu_r_v_i[ii] = 'b0;
            alu_r_addr_i[ii] = 'b0;
         end

         // Write port addr/en/data input
         unique if (alu_w_en_0 && alu_w_bank_0 == ii) begin
            alu_w_v_i[ii] = 'b1;
            alu_w_addr_i[ii] = alu_w_addr_0;
            alu_w_data_i[ii] = alu_w_data_0;
         end else if (alu_w_en_1 && alu_w_bank_1 == ii) begin
            alu_w_v_i[ii] = 'b1;
            alu_w_addr_i[ii] = alu_w_addr_1;
            alu_w_data_i[ii] = alu_w_data_1;
         end else begin
            alu_w_v_i[ii] = 'b0;
            alu_w_addr_i[ii] = 'b0;
            alu_w_data_i[ii] = 'b0;
         end
      end
   end // always_comb

   logic [3:0]                           bank_w_v_i, bank_r_v_i;
   logic [log_max_he_n_p-2:0]            bank_w_addr_i[3:0];
   logic [log_max_he_n_p-2:0]            bank_r_addr_i[3:0];
   logic [max_he_q_p-1:0]                bank_w_data_i[3:0];
   logic [max_he_q_p-1:0]                bank_r_data_o[3:0];

   //((A * B ) + C) 
   //((bank0-1 * bank2-3) + bank0-1)
   //((bank2-3) + bank0-1)
   //((bank2-3))

   //decryption ==> INTT results in bank2-3

   //writes to different banks but the same index in the banks
   assign w_bit_rev_dma_cntr = enc_dec ? dma_cntr : bit_rev (dma_cntr, log_max_he_n_p);
   assign r_bit_rev_dma_cntr = enc_dec ?
                               cnt2intt_addr (dma_state_r == RESET_DMA ? dma_cntr : dma_cntr+1, log_max_he_n_p)
                               : 
                               cnt2ntt_addr  (dma_state_r == RESET_DMA ? dma_cntr : dma_cntr+1, log_max_he_n_p);
   
   assign bank_w_v_i[0] = (state_r == LOAD_A || state_r == LOAD_C) ? io_resp_v_i && ~w_bit_rev_dma_cntr[0] : alu_w_v_i[0];
   assign bank_w_v_i[1] = (state_r == LOAD_A || state_r == LOAD_C) ? io_resp_v_i && w_bit_rev_dma_cntr[0] : alu_w_v_i[1];
   assign bank_w_v_i[2] = (state_r == LOAD_B) ? io_resp_v_i && ~w_bit_rev_dma_cntr[0] : alu_w_v_i[2];
   assign bank_w_v_i[3] = (state_r == LOAD_B) ? io_resp_v_i && w_bit_rev_dma_cntr[0] : alu_w_v_i[3];

   assign bank_r_v_i[0] = alu_r_v_i[0];
   assign bank_r_v_i[1] = alu_r_v_i[1];
   assign bank_r_v_i[2] = (state_r == WB_RES) ? dma_r_en && ~r_bit_rev_dma_cntr[0] : alu_r_v_i[2];
   assign bank_r_v_i[3] = (state_r == WB_RES) ? dma_r_en && r_bit_rev_dma_cntr[0] : alu_r_v_i[3];

   //to test all the data/computation results return back in bank0-1
   /*assign bank_r_v_i[0] = (state_r == WB_RES) ? dma_r_en && ~r_bit_rev_dma_cntr[0] : alu_r_v_i[0];
   assign bank_r_v_i[1] = (state_r == WB_RES) ? dma_r_en && r_bit_rev_dma_cntr[0] : alu_r_v_i[1];
   assign bank_r_v_i[2] = alu_r_v_i[2];
   assign bank_r_v_i[3] = alu_r_v_i[3];*/

   assign bank_w_data_i[0] = (state_r == LOAD_A || state_r == LOAD_C) ? io_resp_data_i : alu_w_data_i[0];
   assign bank_w_data_i[1] = (state_r == LOAD_A || state_r == LOAD_C) ? io_resp_data_i : alu_w_data_i[1];
   assign bank_w_data_i[2] = (state_r == LOAD_B) ? io_resp_data_i : alu_w_data_i[2];
   assign bank_w_data_i[3] = (state_r == LOAD_B) ? io_resp_data_i : alu_w_data_i[3];

   assign bank_w_addr_i[0] = (state_r == LOAD_A || state_r == LOAD_C) ? w_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_w_addr_i[0];
   assign bank_w_addr_i[1] = (state_r == LOAD_A || state_r == LOAD_C) ? w_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_w_addr_i[1];
   assign bank_w_addr_i[2] = (state_r == LOAD_B) ? w_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_w_addr_i[2];
   assign bank_w_addr_i[3] = (state_r == LOAD_B) ? w_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_w_addr_i[3];

   assign bank_r_addr_i[0] = alu_r_addr_i[0];
   assign bank_r_addr_i[1] = alu_r_addr_i[1];   
   assign bank_r_addr_i[2] = (state_r == WB_RES) ? r_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_r_addr_i[2];
   assign bank_r_addr_i[3] = (state_r == WB_RES) ? r_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_r_addr_i[3];

   //to test all the data/computation results return back in bank0-1
   /*assign bank_r_addr_i[0] = (state_r == WB_RES) ? r_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_r_addr_i[0];
   assign bank_r_addr_i[1] = (state_r == WB_RES) ? r_bit_rev_dma_cntr[log_max_he_n_p:1] : alu_r_addr_i[1];   
   assign bank_r_addr_i[2] = alu_r_addr_i[2];
   assign bank_r_addr_i[3] = alu_r_addr_i[3];
   */
   genvar gi;
   // Instantiate 4 memory banks
   for (gi = 0; gi < 4; gi = gi + 1) begin : gen_mem
      bsg_mem_1r1w_sync #(.width_p(max_he_q_p),
                          .els_p  (max_he_n_p>>1)
                          ) mem_bank (
                                  clk_i,
                                  reset_i,
                                  bank_w_v_i[gi],
                                  bank_w_addr_i[gi],
                                  bank_w_data_i[gi],
                                  bank_r_v_i[gi],
                                  bank_r_addr_i[gi],
                                  bank_r_data_o[gi]
                                  );
   end // block: gen_mem
   
   //this is used if we load/store 64bit data at a time
   //assign dma_io_cmd_data_o = {2'b00,bank_r_data_o[3],2'b00,bank_r_data_o[2]};
   assign dma_io_cmd_data_o = prev_r_bit_rev_dma_cntr[0] ? bank_r_data_o[3] : bank_r_data_o[2];

   //to test all the data/computation results return back in bank0-1
   //assign dma_io_cmd_data_o = prev_r_bit_rev_dma_cntr[0] ? bank_r_data_o[1] : bank_r_data_o[0];
   
   assign alu_r_data_0 = bank_r_data_o[alu_r_bank_0_delay];
   assign alu_r_data_1 = bank_r_data_o[alu_r_bank_1_delay];
   
   endmodule






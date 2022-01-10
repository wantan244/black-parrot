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
   /////////////////////////////////////////////////////////////////////////////////////   
   ///////////////////////////////////DMA_FSM///////////////////////////////////////////
   logic                        dma_start, dma_done, dma_io_cmd_v_o;
   logic [63:0]                 dma_addr, dma_cntr, dma_len;
   bp_bedrock_cce_mem_header_s  dma_io_cmd_header_cast_o;
   logic [cce_block_width_p-1:0] dma_io_cmd_data_o;
   
   typedef enum logic [2:0]{
                            RESET_DMA
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
         dma_done <= (dma_len-1 == dma_cntr);
         dma_cntr <= state_dma_n > WAIT_DMA ? '0 : (io_resp_v_i ? dma_cntr + 1: dma_cntr);
      end
   end

   always_comb begin
      state_dma_n = state_dma_r;
      case (state_dma_r)
        RESET_DMA:
          begin
             state_dma_n = dma_start ?  FETCH : RESET_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             
          end
        FETCH:
          begin
             state_dma_n = (dma_len-1 == dma_cntr) ?  DONE_DMA : WAIT_DMA;
             dma_io_cmd_v_o = 1;
             dma_io_cmd_header_cast_o.size = e_bedrock_msg_size_4;
             dma_io_cmd_header_cast_o.payload = cmd_payload;
             dma_io_cmd_header_cast_o.addr = dma_addr + (dma_cntr*4) ;
             dma_io_cmd_header_cast_o.msg_type.mem <= e_bedrock_mem_uc_rd;
             
             
          end
        WAIT_DMA:
          begin
             state_dma_n = io_resp_v_i ? FETCH : WAIT_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             
          end
        DONE_DMA:
          begin
             state_dma_n = RESET_DMA;
             dma_io_cmd_v_o = 0;
             dma_io_cmd_header_cast_o = '0;
             
          end
      endcase 
   end // always_comb

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////EN_DECRYPTION FSM///////////////////////////////
   ////cfg registers
   logic [31:0] q, n, a_ptr, b_ptr, c_ptr;
   logic        cfg_start, cfg_done, enc_dec, res_stat;
   logic        ntt_done, ntt_io_cmd_v_o, add_done, mult_done;
   bp_bedrock_cce_mem_header_s  ntt_io_cmd_header_cast_o;
   logic [cce_block_width_p-1:0] ntt_io_cmd_data_o;
  
   typedef enum logic [3:0]{
                            RESET
                            , CFG
                            , LOAD_A //full_buffer_count = 1
                            , NTT_A  //takes one cycle, full_buffer_count = 1
                            , LOAD_B //parallel with NTT_A, wait here until NTT_A is done, full_buffer_count = 2
                            , NTT_B  //full_buffer_count = 2
                            , MULT   //takes one cycle, call point_wise mul, writeback the resutls to A, full_buffer_count = 2
                            , LOAD_C //load c regardless of MULT state
                            , ADD
                            , WB_RES
                            , DONE
                            } state_e;
   state_e state_r, state_n;

   always_ff @(posedge clk_i) begin
      if(reset_i) begin
         state_r <= RESET;
         cfg_start <= 0;
         cfg_done <= 0;
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
             state_n = cfg_start ? CFG : RESET;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        CFG:
          begin
             state_n = cfg_done ? LOAD_A : CFG;
             dma_start = 0;
             dma_addr =0 ;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        LOAD_A:
          begin
             state_n = dma_done ? NTT_A : LOAD_A;
             dma_start = 1;
             dma_addr = a_ptr;
             dma_len = n;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        NTT_A:
          begin
             state_n = ntt_done ? LOAD_B : NTT_A;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        LOAD_B:
          begin
             state_n = dma_done ? NTT_B : LOAD_B;
             dma_start = 1;
             dma_addr = b_ptr;
             dma_len = n;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        NTT_B:
          begin
             state_n = ntt_done ? MULT : NTT_B;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        MULT:
          begin
             state_n = mult_done ? LOAD_C : MULT;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        LOAD_C:
          begin
             state_n = dma_done ? ADD : LOAD_C;
             dma_start = 1;
             dma_addr = c_ptr;
             dma_len = n;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        ADD:
          begin
             state_n = add_done ? WB_RES : ADD;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        WB_RES:
          begin
             state_n = DONE;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '0;
             ntt_io_cmd_header_cast_o = '0;
             ntt_io_cmd_data_o = '0;
             
          end
        DONE:
          begin
             state_n = RESET;
             dma_start = 0;
             dma_addr = 0;
             dma_len = 0;
             ntt_io_cmd_v_o = '1;
             ntt_io_cmd_header_cast_o.size = e_bedrock_msg_size_8;
             ntt_io_cmd_header_cast_o.payload = cmd_payload;
             ntt_io_cmd_header_cast_o.addr = 40'h30_0000;
             ntt_io_cmd_header_cast_o.subop = e_bedrock_store;
             ntt_io_cmd_header_cast_o.msg_type.mem = e_bedrock_mem_uc_wr;
             ntt_io_cmd_data_o = '1;
             
          end
      endcase 
   end // always_comb

   assign io_cmd_v_o = ntt_io_cmd_v_o | dma_io_cmd_v_o;
   assign io_cmd_header_cast_o = ntt_io_cmd_v_o ? ntt_io_cmd_header_cast_o : dma_io_cmd_header_cast_o;
   assign io_cmd_data_o = ntt_io_cmd_v_o ? ntt_io_cmd_data_o : dma_io_cmd_data_o; 
   /////////////////////////////////////////////////////////////////////////////////////
   //NTT, MUL, ADD submodules 
   //NTT includes address generators, sequencers, BFU
   logic ntt_r_en_a, ntt_r_en_b, ntt_start, ntt_w_en_a, ntt_w_en_b;
   logic [29:0] ntt_r_data_a, ntt_r_data_b, ntt_w_data_a, ntt_w_data_b;
   logic [63:0] ntt_r_addr_a, ntt_r_addr_b, ntt_w_addr_a, ntt_w_addr_b;

   assign ntt_done = 1;
   
/*   NTT
     #(.q(q) , .n(n))
   ntt_mod 
     (//inputs
      .clk(clk)
      ,.reset(reset)
      ,.start(ntt_start)
      ,.r_data_1(ntt_r_data_a)
      ,.r_data_2(ntt_r_data_b)

      //outputs
      ,.r_en_1(ntt_r_en_a)
      ,.r_en_2(ntt_r_en_b)
      ,.r_addr_1(ntt_r_addr_a)
      ,.r_addr_2(ntt_r_addr_b)
      ,.w_en_1(ntt_w_en_a)
      ,.w_en_2(ntt_w_en_b)
      ,.w_addr_1(ntt_w_addr_a)
      ,.w_addr_2(ntt_w_addr_b)
      ,.w_data_1(ntt_w_data_a)
      ,.w_data_2(ntt_w_data_b)
      ,.done(ntt_done)
      )
  */

   assign mult_done = 1;
   assign add_done = 1;
   
   //////////////////////////////////BUFFERS////////////////////////////////////////////
   wire [14:0] w_addr_a;//max(n) == 2^15
   wire                          w_en_a = (dma_start && state_r == LOAD_A) ? io_resp_v_i : ntt_w_en_a;
   wire [29:0]                   w_data_a = (dma_start && state_r == LOAD_A) ? io_resp_data_i : ntt_w_data_a;
                          
   assign w_addr_a = (dma_start && state_r == LOAD_A) ? dma_addr : ntt_w_addr_a;
   
   bsg_mem_1rw_sync
     #(.width_p(30), .els_p(1024)) //parameters should be a constant
   buff_A
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(w_data_a)
      ,.addr_i(ntt_r_en_a ? ntt_r_addr_a : w_addr_a)
      ,.v_i(w_en_a && ntt_r_en_a)
      ,.w_i(w_en_a)
      ,.data_o(ntt_r_data_a)
      );

   wire [14:0] w_addr_b;
   wire                          w_en_b = (dma_start && state_r == LOAD_B) ? io_resp_v_i : ntt_w_en_b;
   wire [29:0]                   w_data_b = (dma_start && state_r == LOAD_B) ? io_resp_data_i : ntt_w_data_b;

   assign w_addr_b =  (dma_start && state_r == LOAD_B) ? dma_addr : ntt_w_addr_b;
     
   bsg_mem_1rw_sync
     #(.width_p(30), .els_p(1024))
   buff_B
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.data_i(w_data_b)
      ,.addr_i(ntt_r_en_b ? ntt_r_addr_b : w_addr_b)
      ,.v_i(w_en_b && ntt_r_en_b)
      ,.w_i(w_en_b)
      ,.data_o(ntt_r_data_b)
      );
///////////////////////////////////////////////////////////////////////////////////// 
   endmodule


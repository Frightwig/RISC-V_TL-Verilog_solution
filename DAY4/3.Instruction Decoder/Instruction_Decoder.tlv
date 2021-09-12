\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/RISC-V_MYTH_Workshop
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/RISC-V_MYTH_Workshop/c1719d5b338896577b79ee76c2f443ca2a76e14f/tlv_lib/risc-v_shell_lib.tlv'])

\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
\TLV

   // /====================\
   // | Sum 1 to 9 Program |
   // \====================/
   //
   // Program for MYTH Workshop to test RV32I
   // Add 1,2,3,...,9 (in that order).
   //
   // Regs:
   //  r10 (a0): In: 0, Out: final sum
   //  r12 (a2): 10
   //  r13 (a3): 1..10
   //  r14 (a4): Sum
   // 
   // External to function:
   m4_asm(ADD, r10, r0, r0)             // Initialize r10 (a0) to 0.
   // Function:
   m4_asm(ADD, r14, r10, r0)            // Initialize sum register a4 with 0x0
   m4_asm(ADDI, r12, r10, 1010)         // Store count of 10 in register a2.
   m4_asm(ADD, r13, r10, r0)            // Initialize intermediate sum register a3 with 0
   // Loop:
   m4_asm(ADD, r14, r13, r14)           // Incremental addition
   m4_asm(ADDI, r13, r13, 1)            // Increment intermediate register by 1
   m4_asm(BLT, r13, r12, 1111111111000) // If a3 is less than a2, branch to label named <loop>
   m4_asm(ADD, r10, r14, r0)            // Store final result to register a0 so that it can be read by main program
   
   // Optional:
   // m4_asm(JAL, r7, 00000000000000000000) // Done. Jump to itself (infinite loop). (Up to 20-bit signed immediate plus implicit 0 bit (unlike JALR) provides byte address; last immediate bit should also be 0)
   m4_define_hier(['M4_IMEM'], M4_NUM_INSTRS)

   |cpu
      @0
         $reset = *reset;
               
         //程序计数器模块PC，每执行一次指令，地址加四，以执行下一指令。
         $pc[31:0] = >>1$reset ? 32'd0 :
                                 >>1$pc + 32'd4;
             
             
      //指令寄存器。根据pc的值，从指令寄存器取指令                        
      @1
         $imem_rd_en = !$reset;
         $imem_rd_addr[M4_IMEM_INDEX_CNT-1:0] = $pc[M4_IMEM_INDEX_CNT+1:2];  //pc每加4,第【2】位加一，地址加一
         $instr[31:0] = $imem_rd_data[31:0];        //读取指令
         
         
      //指令译码模块                        
      @1
         //指令类型译码，根据指令的【6:2】位，判断指令的类型
         $is_i_instr = $instr[6:2] ==? 5'b0000X ||            //I-type，加载与立即数运算
                       $instr[6:2] ==? 5'b001X0 ||
                       $instr[6:2] ==? 5'b11001;
         $is_r_instr = $instr[6:2] ==? 5'b011X0 ||           //R-type，算术指令
                       $instr[6:2] ==? 5'b01100 ||
                       $instr[6:2] ==? 5'b10100;
         $is_u_instr = $instr[6:2] ==? 5'b0X101;            //U-type，高位立即数运算
         $is_j_instr = $instr[6:2] ==? 5'b11011;            //UJ-type，无条件跳转
         $is_s_instr = $instr[6:2] ==? 5'b0100X;            //S-type,存储
         $is_b_instr = $instr[6:2] ==? 5'b11000;            //SB-type，条件分支指令
         
         //根据指令类型，决定立即数。(R-type用不到立即数)
         $imm[31:0] = $is_i_instr ? {{21{$instr[31]}},$instr[30:20]} :
                      $is_s_instr ? {{21{$instr[31]}},$instr[30:25],$instr[11:7]} :
                      $is_b_instr ? {{19{$instr[31]}},$instr[7],$instr[30:25],$instr[11:8],1'b0} :
                      $is_u_instr ? {$instr[31:12],12'b0} :
                      $is_j_instr ? {{12{$instr[31]}},$instr[19:12],$instr[20],$instr[30:21],1'b0} :
                      32'd0 ;              //指令用不到立即数时，全部置为0
         
         //RISC-V指令域译码，根据指令类型决定
         $opcode[6:0] = $instr[6:0];       //7位操作码
         $rs1_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
         ?$rs1_valid
            $rs1[4:0] = $instr[19:15];     //rs1,所用第一个寄存器源的编号
         $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
         ?$rs2_valid
            $rs2[4:0] = $instr[24:20];     //rs2,所用第二个寄存器源的编号
         $rd_valid = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr;
         ?$rd_valid
            $rd[4:0] = $instr[11:7];      //rd,目标寄存器的编号
         $funct3_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
         ?$funct3_valid
            $funct3[2:0] = $instr[14:12];      //funct3,3bits功能位，额外操作码
         $funct7_valid = $is_r_instr;
         ?$funct7_valid
            $funct7[6:0] = $instr[31:25];      //funct7,7bits功能位，额外操作码
            
         //根据操作码及funct3，产生八条基本指令。
         $dec_bits[10:0] = {$funct7[5],$funct3,$opcode};
         $is_beq = $dec_bits ==? 11'bx_000_1100011;       //相等跳转指令
         $is_bne = $dec_bits ==? 11'bx_001_1100011;       //不相等跳转指令
         $is_blt = $dec_bits ==? 11'bx_100_1100011;       //小于跳转指令（有符号）
         $is_bge = $dec_bits ==? 11'bx_101_1100011;       //大于等于跳转指令（有符号）
         $is_bltu = $dec_bits ==? 11'bx_110_1100011;      //小于跳转指令（无符号）
         $is_bgeu = $dec_bits ==? 11'bx_111_1100011;      //大于等于跳转指令（无符号）
         $is_addi = $dec_bits ==? 11'bx_000_0010011;      //立即数相加指令
         $is_add = $dec_bits ==? 11'b0_000_0110011;       //寄存器数相加指令
         

   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
   

   |cpu
      m4+imem(@1)    // 提供的指令寄存器实例化

   m4+cpu_viz(@4)    // 提供的可视化
\SV
   endmodule

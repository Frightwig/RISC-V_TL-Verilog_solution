\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/RISC-V_MYTH_Workshop
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/RISC-V_MYTH_Workshop/c1719d5b338896577b79ee76c2f443ca2a76e14f/tlv_lib/risc-v_shell_lib.tlv'])

\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
\TLV
   //Register File Bypass & Squashing
   //使用VALID，每三周期实现一次，会造成低效--每个指令都要等到三周期，不能实现周期流水
   //使用Register File Bypass解决读写危害：若ALU结果还未存入RF-WR,后面就要用此数据（数据依赖），则直接先将此结果给下一周期的ALU使用，不必等其放入RF
   //分支VALID,若一个分支跳转前两个周期内，已有一个分支跳转，则此处不进行跳转。防止LOOP冲突。
   //PC依旧每clk加一，但解决了问题。
   
   // /====================\
   // | Sum 1 to 9 Program |  
   // \====================/
   //
   // Program for MYTH Workshop to test RV32I
   // Add 1,2,3,...,9 (in that order).利用编写的RISC-V实现1-9的累加
   //
   // Regs:
   //  r10 (a0): In: 0, Out: final sum    最终结果从a4再放入a0
   //  r12 (a2): 10        a2为10与a3比较，a3加到10就不加了。
   //  r13 (a3): 1..10    a3每次加一，从1-10变化
   //  r14 (a4): Sum      a4每次和加一后的a3相加
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
                     >>3$valid_taken_br ? >>3$br_tgt_pc :            //分割成多周期，读取三周期后的分支信号
                                    >>1$pc + 32'd4;                  //若没有分支信号，一周期后加4.


      //Instruction Memory指令存储器。根据pc的值，从指令寄存器取指令                        
      @1
         $imem_rd_en = !$reset;
         $imem_rd_addr[M4_IMEM_INDEX_CNT-1:0] = $pc[M4_IMEM_INDEX_CNT+1:2];  //pc每加4,第【2】位加一，地址加一
         $instr[31:0] = $imem_rd_data[31:0];        //读取指令
         
         
         //Instruction Decoder。指令译码模块                        
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


      //Register File Read。读寄存器堆，根据指令将寄存器堆里的数据放入ALU运算。   
      @2
         $rf_rd_en1 = $rs1_valid;         //第一源寄存器读使能
         $rf_rd_index1[4:0] = $rs1;       //第一源寄存器索引
         $rf_rd_en2 = $rs2_valid;         //第二源寄存器读使能
         $rf_rd_index2[4:0] = $rs2;       //第二源寄存器索引
         
         $src1_value[31:0] = >>1$rf_wr_en && (>>1$rf_wr_index == $rf_rd_index1) ? >>1$result : 
                                                                                  $rf_rd_data1;   //上一指令需要存储数据且地址当前指令读的地址一样，则将上一指令结果直接调用
         $src2_value[31:0] = >>1$rf_wr_en && (>>1$rf_wr_index == $rf_rd_index2) ? >>1$result : 
                                                                                  $rf_rd_data2;   //上一指令需要存储数据且地址当前指令读的地址一样，则将上一指令结果直接调用
         
         //根据指令中的立即数决定跳转的地址,此时已经可以得出地址。但还不能确定是否跳转。
         $br_tgt_pc[31:0] = $pc + $imm;


      //ALU，逻辑运算单元，（初步只设计相加功能）
      @3
         $result[31:0] = $is_addi ? $src1_value + $imm :       //立即数相加指令，将指令中的立即数与寄存器堆中数据相加
                         $is_add  ? $src1_value + $src2_value :   //相加指令，将寄存器堆的两个数相加。
                         32'b0;
         
         
         //Register File Write。写寄存器堆将运算结果放入。   
         $rf_wr_en = $rd_valid && $rd != 5'b0;    //0号寄存器始终为0。
         $rf_wr_index[4:0] = $rd;         //写寄存索引，
         $rf_wr_data[31:0] = $result;     //写数据
         
         
         //Branch,分支指令
         //根据指令来判断分支跳转的条件。
         $taken_br = $is_beq ? ($src1_value == $src2_value) :      //读出两数相等则跳转
                     $is_bne ? ($src1_value != $src2_value) :      //读出两数不等则跳转
                     $is_blt ? ($src1_value < $src2_value) ^ ($src1_value[31] != $src2_value[31]) :       //一号源小于二号源跳转
                     $is_bge ? ($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31]) :      //一号院大于等于二号源跳转
                     $is_bltu ? ($src1_value < $src2_value) :      //一号源小于二号源跳转（无符号）
                     $is_bgeu ? ($src1_value >= $src2_value) :     //一号源大于等于二号源跳转（无符号）
                                1'b0;
         
         $valid = ! (>>1$valid_taken_br || >>2$valid_taken_br);      //确保分支跳转时，前两个周期都没有发生分支跳转，此跳转才有效
         $valid_taken_br = $valid && $taken_br;       //达到产生分支跳转条件，且当前为有效时，才发生分支跳转。
         
         


   // 仿真条件限制.
   *passed = |cpu/xreg[10]>>5$value == (1+2+3+4+5+6+7+8+9) ;//testbench，xreg[10]的结果延迟五周期和45比较，若正确结束仿真
   *failed = 1'b0;
   

   |cpu
      m4+imem(@1)    // 提供的指令存储器实例化
      m4+rf(@2, @3)  // 提供的读寄存器堆实例化，在@2读，@3写
   m4+cpu_viz(@4)    // 提供的可视化,@4延迟至4周期再输出
\SV
   endmodule

\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/RISC-V_MYTH_Workshop  
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/RISC-V_MYTH_Workshop/c1719d5b338896577b79ee76c2f443ca2a76e14f/tlv_lib/risc-v_shell_lib.tlv'])

\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
\TLV
   //RISC-V-FINAL
   //检测：利用汇编指令，令其实现从1-9的累加，结果放入数据存储器中，再读取至r17，进行比较检验是否成功。完成后跳转进行循环。
   
   // /====================\
   // | Sum 1 to 9 Program |  
   // \====================/
   // Add 1,2,3,...,9 (in that order).利用编写的RISC-V实现1-9的累加
   //
   // Regs:
   //  r10 (a0): In: 0, Out: final sum    最终结果从a4再放入a0
   //  r12 (a2): 10        a2为10与a3比较，a3加到10就不加了。
   //  r13 (a3): 1..10    a3每次加一，从1-10变化
   //  r14 (a4): Sum      a4每次和加一后的a3相加
   //  r17 (a5):对计算结果进行存取之后的结果，进行最终比较
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
   m4_asm(SW, r0, r10, 10000)           //将r10的计算结果放入datamemory中。datamemory的地址为r0+10000
   m4_asm(LW, r17, r0, 10000)           //将datamemory的值读入r17寄存器中。datamemory的地址为r0+10000
   // Optional:
   m4_asm(JAL, r7, 00000000000000000000) //完成后程序跳转到开始进行循环，地址为立即数，且将其存放在r7中
   m4_define_hier(['M4_IMEM'], M4_NUM_INSTRS)

   |cpu
      //@0时刻，（1）读取复位信号，（2）控制计数器选择指令地址
      @0
         $reset = *reset;
         
         //程序计数器模块PC，每执行一次指令，地址加四，以执行下一指令。
         $pc[31:0] = >>1$reset ? 32'd0 :
                     >>3$valid_taken_br ? >>3$br_tgt_pc :             //分割成多周期，读取三周期后的分支信号
                     >>3$valid_load ? >>3$pc + 32'd4:                 //加载数据，则跳转至3周期前的指令位置，以免产生数据依赖
                     >>3$valid_jump && >>3$is_jal ? >>3$br_tgt_pc :   //跳转
                     >>3$valid_jump && >>3$is_jalr ? >>3$jalr_tgt_pc ://跳转到寄存器指定的指令
                                      >>1$pc + 32'd4;                 //若没有分支信号，一周期后加4.


      //@1时刻，（1）从指令存储器取指令  （2）对指令进行译码得出各个所需用的数据                   
      @1
         //根据pc地址从，指令存储器取出指令
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
            


      //@2 （1）得出确定的指令信号 （2）从读寄存器堆中取数 （3）产生分支和跳转的地址   
      @2
         //根据操作码及funct3，产生RISC-V全部基础指令（除FENCE, ECALL, EBREAK）。
         $dec_bits[10:0] = {$funct7[5],$funct3,$opcode};
         $is_beq = $dec_bits ==? 11'bx_000_1100011;       //相等跳转指令
         $is_bne = $dec_bits ==? 11'bx_001_1100011;       //不相等跳转指令
         $is_blt = $dec_bits ==? 11'bx_100_1100011;       //小于跳转指令（有符号）
         $is_bge = $dec_bits ==? 11'bx_101_1100011;       //大于等于跳转指令（有符号）
         $is_bltu = $dec_bits ==? 11'bx_110_1100011;      //小于跳转指令（无符号）
         $is_bgeu = $dec_bits ==? 11'bx_111_1100011;      //大于等于跳转指令（无符号）
         $is_addi = $dec_bits ==? 11'bx_000_0010011;      //立即数相加指令
         $is_add = $dec_bits ==? 11'b0_000_0110011;       //寄存器数相加指令
         $is_lui = $dec_bits ==? 11'bx_xxx_0110111;       //高16位立即数存放指令
         $is_auipc = $dec_bits ==? 11'bx_xxx_0010111;     //pc高位加立即数指令
         $is_jal = $dec_bits ==? 11'bx_xxx_1101111;       //跳转与连接指令
         $is_jalr = $dec_bits ==? 11'bx_000_1100111;      //跳转与连接寄存器指令
         $is_lb = $dec_bits ==? 11'bx_000_0000011;        //加载字节指令
         $is_lh = $dec_bits ==? 11'bx_001_0000011;        //加载半字指令
         $is_lw = $dec_bits ==? 11'bx_010_0000011;        //加载字指令
         $is_lbu = $dec_bits ==? 11'bx_100_0000011;       //加载无符号字节指令
         $is_lhu = $dec_bits ==? 11'bx_101_0000011;       //加载无符号半字指令
         $is_sb = $dec_bits ==? 11'bx_000_0100011;        //存储字节指令
         $is_sh = $dec_bits ==? 11'bx_001_0100011;        //存储半字指令
         $is_sw = $dec_bits ==? 11'bx_010_0100011;        //存储字指令
         $is_slti = $dec_bits ==? 11'bx_010_0010011;      //立即数比较指令
         $is_sltiu = $dec_bits ==? 11'bx_011_0010011;     //立即数比较（无符号）指令
         $is_xori = $dec_bits ==? 11'bx_100_0010011;      //立即数异或指令
         $is_ori = $dec_bits ==? 11'bx_110_0010011;       //立即数或指令
         $is_andi = $dec_bits ==? 11'bx_111_0010011;      //立即数与指令
         $is_slli = $dec_bits ==? 11'b0_001_0010011;      //逻辑左移立即数指令
         $is_srli = $dec_bits ==? 11'b0_101_0010011;      //逻辑右移立即数指令
         $is_srai = $dec_bits ==? 11'b1_101_0010011;      //立即数算术右移指令
         $is_sub = $dec_bits ==? 11'b1_000_0110011;       //相减指令
         $is_sll = $dec_bits ==? 11'b0_001_0110011;       //逻辑左移指令
         $is_slt = $dec_bits ==? 11'b0_010_0110011;       //比较指令
         $is_sltu = $dec_bits ==? 11'b0_011_0110011;      //比较（无符号）指令
         $is_xor = $dec_bits ==? 11'b0_100_0110011;       //异或指令
         $is_srl = $dec_bits ==? 11'b0_101_0110011;       //逻辑右移指令
         $is_sra = $dec_bits ==? 11'b1_101_0110011;       //算术右移指令
         $is_or = $dec_bits ==? 11'b0_110_0110011;        //或指令
         $is_and = $dec_bits ==? 11'b0_111_0110011;       //与指令
         $is_load = $is_lb || $is_lh || $is_lw ||$is_lbu ||$is_lhu;          //根据这两指令产生是否加载信号
         
         //读寄存器堆命令
         $rf_rd_en1 = $rs1_valid;         //第一源寄存器读使能
         $rf_rd_index1[4:0] = $rs1;       //第一源寄存器索引
         $rf_rd_en2 = $rs2_valid;         //第二源寄存器读使能
         $rf_rd_index2[4:0] = $rs2;       //第二源寄存器索引
         $src1_value[31:0] = >>1$rf_wr_en && (>>1$rf_wr_index == $rf_rd_index1) ? >>1$result :
                                                                                  $rf_rd_data1;   //上一指令需要存储数据且地址当前指令读的地址一样，则将上一指令结果直接调用
         $src2_value[31:0] = >>1$rf_wr_en && (>>1$rf_wr_index == $rf_rd_index2) ? >>1$result :
                                                                                  $rf_rd_data2;   //上一指令需要存储数据且地址当前指令读的地址一样，则将上一指令结果直接调用
         
         //产生分支和跳转地址
         $br_tgt_pc[31:0] = $pc + $imm;            //根据指令中的立即数决定分支和跳转的地址,此时已经可以得出地址。但还不能确定是否跳转
         $jalr_tgt_pc[31:0] = $src1_value + $imm;  //jalr指令，根据rs1的值来决定跳转地址


      //@3 （1）ALU计算出结果（2）向写寄存堆放入结果（3）产生分支、加载、跳转的有效信号
      @3
         $is_jump = $is_jal || $is_jalr;                               //根据这两指令产生是否跳转信号
         
         //ALU产生运算结果
         $sltu_rslt[31:0] = $src1_value < $src2_value;                //判断位，源一比源二小结果置一，不然为0
         $sltiu_rslt[31:0] = $src1_value < $imm;                      //判断位，源一比立即数小结果置一，不然为0
         $result[31:0] = ($is_addi || $is_load || $is_s_instr) ? $src1_value + $imm :             //立即数相加指令,以及读写指令中datamemory地址的生成。
                         $is_andi  ? $src1_value & $imm :             //立即数相与
                         $is_ori   ? $src1_value | $imm :             //立即数相或
                         $is_xori  ? $src1_value ^ $imm :             //立即数异或
                         $is_addi  ? $src1_value + $imm :             //立即数相加指令，将指令中的立即数与寄存器堆中数据相加
                         $is_slli  ? $src1_value << $imm[5:0] :       //寄存器读取的数左移立即数位
                         $is_srli  ? $src1_value >> $imm[5:0] :       //寄存器读取的数右移立即数位
                         $is_and   ? $src1_value & $src2_value:       //寄存器数相与
                         $is_or    ? $src1_value | $src2_value:       //寄存器数相或
                         $is_xor   ? $src1_value ^ $src2_value:       //寄存器数异或
                         $is_add   ? $src1_value + $src2_value :      //寄存器数相加。
                         $is_sub   ? $src1_value - $src2_value:       //寄存器数相减
                         $is_sll   ? $src1_value << $src2_value[4:0]: //寄存器读取的数左移
                         $is_srl   ? $src1_value >> $src2_value[4:0]: //寄存器读取的数右移
                         $is_sltu  ? $sltu_rslt:                      //无符号比较大小，小于置位
                         $is_sltiu ? $sltiu_rslt:                     //无符号数比较立即数大小，小于置位
                         $is_lui   ? {$imm[31:12],12'b0}:             //读取立即数高20位，低位置0
                         $is_auipc ? $pc + $imm:                      //立即数加当前地址
                         $is_jal   ? $pc + 32'd4:                     //地址加四
                         $is_jalr  ? $pc + 32'd4:                     //地址加四
                         $is_srai  ? {{32{$src1_value[31]}},$src1_value} >> $imm[4:0] :       //立即数算术右移，补充的为原本数的最高位
                         $is_slt   ? ($src1_value[31] == $src_value[31]) ? $sltu_rslt : {31'b0,$src1_value[31]} :  //有符号小于置位
                         $is_slti  ? ($src1_value[31] == $src_value[31]) ? $sltiu_rslt : {31'b0,$src1_value[31]} : //有符号立即数小于置位
                         $is_sra   ? {{32{$src1_value[31]}},$src1_value} >> $src2_value[4:0] :     //算术右移
                         32'b0;
         
         //Register File Write。写寄存器堆将运算结果放入。   
         $rf_wr_en = ($rd_valid && ($rd != 5'b0) && $valid) || >>2$valid_load;    //0号寄存器始终为0。且只有load或分支信号执行完成后，才可重新写入数据至寄存器堆。或者两时刻前出现有效的加载信号，可以写
         $rf_wr_index[4:0] = >>2$valid_load ? >>2$rd : $rd;                       //若产生了加载信号，所用的rd索引号是两周期前的，免得被冲掉
         $rf_wr_data[31:0] = >>2$valid_load ? >>2$ld_data : $result;              //@5时刻，datamemory才把数据传进来
         
         //Branch,分支指令
         //根据指令来判断分支跳转的条件。
         $taken_br = $is_beq ? ($src1_value == $src2_value) :      //读出两数相等则跳转
                     $is_bne ? ($src1_value != $src2_value) :      //读出两数不等则跳转
                     $is_blt ? ($src1_value < $src2_value) ^ ($src1_value[31] != $src2_value[31]) :       //一号源小于二号源跳转
                     $is_bge ? ($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31]) :      //一号院大于等于二号源跳转
                     $is_bltu ? ($src1_value < $src2_value) :      //一号源小于二号源跳转（无符号）
                     $is_bgeu ? ($src1_value >= $src2_value) :     //一号源大于等于二号源跳转（无符号）
                                1'b0;
         
         //有效信号，每三个周期内只能有一个跳转或加载、jump指令发生，避免依赖。
         $valid = !(>>1$valid_load || >>2$valid_load || >>1$valid_taken_br || >>2$valid_taken_br || >>1$valid_jump || >>2$valid_jump);
         $valid_taken_br = $valid && $taken_br;       //达到产生分支跳转条件，且当前为有效时，才发生分支跳转。
         $valid_load = $valid && $is_load;            //产生加载指令，且在有效条件时，才执行。 
         $valid_jump = $valid && $is_jump;            //jump有效


      //@4 访存，向datamemory发出命令及给出地址
      //从datamemory 中load 数据时，用rs1+IMM作为datamemory数据的地址。rd作为目标寄存器数
      //向datamemory store数据时，rs2作为源寄存器，rs1+ imm作为存入datamemory的地址。
      @4
         $dmem_wr_en = $is_s_instr && $valid ;      //存储器写使能。只有发生store指令，且处在有效阶段时才向datamemory写
         $dmem_rd_en = $is_load ;                   //存储器读使能
         $dmem_addr[3:0] = $result[5:2];            //存储器地址
         $dmem_wr_data[31:0] = $src2_value;         //将src2的值作为store的值

      //@5 load数据的值
      @5
         $ld_data[31:0] = $dmem_rd_data;           //接收来自datamemory的值
         
         
   // 仿真条件限制.
   *passed = |cpu/xreg[17]>>5$value == (1+2+3+4+5+6+7+8+9) ;//testbench，xreg[10]的结果延迟五周期和45比较，若正确结束仿真
   *failed = 1'b0;
   

   |cpu
      m4+imem(@1)    // 提供的指令存储器实例化
      m4+rf(@2, @3)  // 提供的读寄存器堆实例化，在@2读，@3写
      m4+dmem(@4)    // 提供的datamemory实例化，在@4时刻工作
   m4+cpu_viz(@4)    // 提供的可视化,@4延迟至4周期再输出
\SV
   endmodule

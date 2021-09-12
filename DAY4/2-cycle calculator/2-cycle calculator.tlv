\m4_TLV_version 1d: tl-x.org
\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)

\TLV
   // 2-cycle calculator
   //第一个周期计算出四种基本结果，在第二个周期作选择
   |calc
      @0
         $reset = *reset;     //0时刻接收复位信号
         
      @1                     //在第一个周期完成加减乘除四种基本运算
         $val1 [31:0] = >>2$out [31:0];     //输出结果延迟两个clk后，作为新的运算输入
         $val2 [31:0] = $rand2[3:0];       //避免大数
         
         $sum [31:0]  = $val1 + $val2;
         $diff[31:0] = $val1 - $val2;
         $prod[31:0] = $val1 * $val2;
         $quot[31:0] = $val1 / $val2;
         
         $valid = $reset ? 1'b0 : >>1$valid + 1'b1;  //valid为一位计数器0，1变化，确保第二个周期选择信号
         
      @2                   //在第二个周期根据操作指令做出选择
         $out[31:0] = $reset || !$valid ? 32'b0:
                                 $op[0] ? $sum:
                                 $op[1] ? $diff:
                                 $op[2] ? $prod:
                                          $quot;
  
   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule

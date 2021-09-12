\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
\TLV
   
   |cpu
      @0
         $reset = *reset;
         
         //程序计数器模块，每执行一次指令，地址加四，以执行下一指令。
         $pc[31:0] = >>1$reset ? 32'd0 : 
                                             >>1$pc + 32'd4;


   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule

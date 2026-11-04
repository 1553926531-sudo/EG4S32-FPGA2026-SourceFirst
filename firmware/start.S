.section .text.start
.globl _start
_start:
 .option push
 .option norelax
 la gp, __global_pointer$
 .option pop
 li sp, 0x13000
 la a0, __data_start
 la a1, __data_load
 la a2, __data_end
1:
 bgeu a0, a2, 2f
 lw t0, 0(a1)
 sw t0, 0(a0)
 addi a0, a0, 4
 addi a1, a1, 4
 j 1b
2:
 la a0, __bss_start
 la a2, __bss_end
3:
 bgeu a0, a2, 4f
 sw zero, 0(a0)
 addi a0, a0, 4
 j 3b
4:
 call main
5:
 j 5b

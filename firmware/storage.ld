OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
 ROM (rx) : ORIGIN = 0, LENGTH = 12K
 RAM (rw) : ORIGIN = 0x10000, LENGTH = 12K
}
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
 .data : { __data_start = .; *(.sdata*) *(.data*) . = ALIGN(4); __data_end = .; } > RAM AT> ROM
 __data_load = LOADADDR(.data);
 __global_pointer$ = 0x10800;
 .bss (NOLOAD) : { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
 ASSERT(__bss_end <= 0x12800, "Working data leaves less than 2048 bytes for stack")
 /DISCARD/ : { *(.comment) *(.eh_frame*) *(.riscv.attributes) }
}

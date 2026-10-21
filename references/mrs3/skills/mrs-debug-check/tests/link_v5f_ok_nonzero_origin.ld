/* CH32H417WEU 单核工程 V5F 链接脚本（调试前检查应 PASS：FLASH 480K<960K、RAM 448K<896K；但 ORIGIN≠0 触发规则3 询问） */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x40000000, LENGTH = 480K
    RAM (xrw) : ORIGIN = 0x38000000, LENGTH = 448K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) } >FLASH
    .rodata : { *(.rodata) *(.rodata*) } >FLASH
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
    /DISCARD/ : { *(.comment) }
}

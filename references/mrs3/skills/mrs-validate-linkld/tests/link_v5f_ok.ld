/* CH32H417WEU 双核工程 V5F 链接脚本（模板，校验应 PASS） */
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
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
    /DISCARD/ : { *(.comment) }
}

/* CH32V203CCT 单核链接脚本（FLASH 多区域合计超上限，校验应 FAIL）
   注意：FLASH 128K 与 FLASH2 160K 单独看都不超过 256K，
   但合计 288K 超过 CH32V203CCT 最大 flash 256K，必须报 ERROR */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 128K
    FLASH2 (rx) : ORIGIN = 0x00020000, LENGTH = 160K
    RAM (xrw) : ORIGIN = 0x20000000, LENGTH = 16K
    RAM2 (xrw) : ORIGIN = 0x20004000, LENGTH = 8K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) } >FLASH
    .rodata : { *(.rodata) *(.rodata*) } >FLASH2
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
    .ram2 : { *(.ram2) } >RAM2
}

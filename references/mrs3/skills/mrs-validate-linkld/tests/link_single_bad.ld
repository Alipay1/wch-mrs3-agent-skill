/* CH32V203CCT 链接脚本（RAM ORIGIN 错误、FLASH/RAM 超限、缺堆定义，校验应 FAIL） */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 512K
    RAM (xrw) : ORIGIN = 0x20001000, LENGTH = 64K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Stack_Size = 0x400;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) } >FLASH
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
    .debug : { *(.debug) } >RAM
}

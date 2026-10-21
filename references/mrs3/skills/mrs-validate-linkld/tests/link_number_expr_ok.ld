/* CH32H417WEU 双核工程 V5F 链接脚本（运算符两侧为数字时原样保留，不检查不计算，校验应 PASS） */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x40000000, LENGTH = 480K
    RAM (xrw) : ORIGIN = 0x38000000, LENGTH = 448K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

/* 以下表达式运算符两侧均为数字字面量：不检查空格、不计算最终值、原样保留 */
_FREQ = 64K*2;
_BASE = 0x1000+0x2000;
_SIZE = 1M/2;
_DELTA = 0x8000-0x1000;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) } >FLASH
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
}

/* CH32H417WEU 双核工程 V5F 链接脚本（LENGTH 为表达式，校验应 PASS）
   LENGTH = 0x3FC00  -> 十进制 261120 字节（255K）
   LENGTH = 448K - 256 -> 十进制 458496 字节（447.75K）
   均由脚本内置计算器统一转成十进制后与芯片上限（flash 960K / sram 896K）比较 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x40000000, LENGTH = 0x3FC00
    RAM (xrw) : ORIGIN = 0x38000000, LENGTH = 448K - 256
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

/* 以下表达式运算符两侧均为数字字面量：不检查空格、不计算最终值、原样保留 */
_FREQ = 64K*2;
_BASE = 0x1000+0x2000;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) } >FLASH
    .rodata : { *(.rodata) *(.rodata*) } >FLASH
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
}

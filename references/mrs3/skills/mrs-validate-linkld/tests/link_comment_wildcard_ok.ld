/* CH32H417WEU 双核工程 V5F 链接脚本（注释/通配符不应被空格检查误报）
 * 本行是注释续行：_estack=ORIGIN(RAM)+LENGTH(RAM); 这里面的运算符不应检查
 * 注释里还有 ORIGIN=0x40000000, LENGTH=480K 也不应检查
 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x40000000, LENGTH = 480K /* 行尾注释 ORIGIN=0x, LENGTH=0x 不检查 */
    RAM (xrw) : ORIGIN = 0x38000000, LENGTH = 448K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

SECTIONS
{
    .isr_vector : { . = ALIGN(4); KEEP(*(.isr_vector)) } >FLASH
    .text : { *(.text) *(.text*) *(.text.*) } >FLASH
    .rodata : { *(.rodata) *(.rodata*) } >FLASH
    _sidata = LOADADDR(.data);
    .data : { . = ALIGN(4); _sdata = .; *(.data) *(.data*); _edata = .; } >RAM AT> FLASH
    .bss : { . = ALIGN(4); _sbss = .; *(.bss) *(.bss*); _ebss = .; } >RAM
    /DISCARD/ : { *(.comment) }
}

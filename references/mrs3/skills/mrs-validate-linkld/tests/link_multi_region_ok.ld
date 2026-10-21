/* CH32V203CCT 单核链接脚本（FLASH/RAM 多区域多行，合计不超上限，校验应 PASS）
   注意：FLASH 与 FLASH2、RAM 与 RAM2 的 LENGTH 必须全部相加后
   再与 mcu_isa.json 中 CH32V203CCT 的上限（flash 256K / sram 32K）比较 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 128K
    FLASH2 (rx) : ORIGIN = 0x00020000, LENGTH = 96K
    RAM (xrw) : ORIGIN = 0x20000000, LENGTH = 16K
    RAM2 (xrw) : ORIGIN = 0x20004000, LENGTH = 8K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;
__global_pointer$ = . + 0x800;

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

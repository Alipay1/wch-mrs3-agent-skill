/* CH32V203CCT 单核工程：FLASH 合计 256K（FLASH2 多区域 64K+192K）= 芯片上限 256K → 规则1 小于等于 → PASS；
   RAM 32K = 上限 32K → PASS；ORIGIN=0 不触发规则3。 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    FLASH2 (rx) : ORIGIN = 0x00010000, LENGTH = 192K
    RAM (xrw) : ORIGIN = 0x20000000, LENGTH = 32K
}
SECTIONS
{
    .text : { *(.text) } >FLASH
    .data : { *(.data) } >RAM
}

/* CH32V203CCT 单核工程（FLASH ORIGIN=0，正常模板；FLASH 256K = 芯片上限 256K → 规则1 小于等于 → PASS；
   本文件用于验证 ORIGIN=0 不触发规则3，且容量等于上限时按"小于等于"规则判 PASS。 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 256K
    RAM (xrw) : ORIGIN = 0x20000000, LENGTH = 20K
}
SECTIONS
{
    .text : { *(.text) } >FLASH
    .data : { *(.data) } >RAM
}

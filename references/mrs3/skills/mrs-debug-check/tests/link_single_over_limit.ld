/* CH32V203CCT 单核工程：FLASH 300K > 芯片上限 256K → 规则1 FAIL；RAM 20K < 32K → PASS；ORIGIN=0 不触发规则3。 */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 300K
    RAM (xrw) : ORIGIN = 0x20000000, LENGTH = 20K
}
SECTIONS
{
    .text : { *(.text) } >FLASH
    .data : { *(.data) } >RAM
}

/*
 * Educational linker script for NebulaOS x86_64 boot stubs.
 *
 * This is NOT currently used by the Limine → stock Linux boot flow.
 * It exists to keep the OSDev architecture modular and future-ready.
 *
 * Target: x86_64-elf (ELF64) objects.
 */

OUTPUT_FORMAT(elf64-x86-64)
ENTRY(boot_stage0_entry)

SECTIONS
{
  . = 0x0000000000000000;

  /* Text */
  .text : {
    *(.text .text.*)
  }

  /* Read-only data */
  .rodata : {
    *(.rodata .rodata.*)
  }

  /* Data */
  .data : {
    *(.data .data.*)
  }

  /* BSS */
  .bss : {
    *(.bss .bss.*)
    *(COMMON)
  }
}


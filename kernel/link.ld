/* Minimal freestanding x86_64 linker script (ELF) */
ENTRY(_start)

SECTIONS
{
  . = 1M;

  .text : {
    *(.text*)
  }

  .rodata : {
    *(.rodata*)
  }

  .data : {
    *(.data*)
  }

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  }

  /DISCARD/ : {
    *(.comment)
    *(.eh_frame)
  }
}


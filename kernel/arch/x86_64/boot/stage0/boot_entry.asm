; NebulaOS x86_64 boot stage0 entry (NASM)
; Coexists with Limine chainloading. This code is not wired into the
; current runtime path; it is compiled as a future-ready low-level module.

BITS 64
GLOBAL boot_stage0_entry
boot_stage0_entry:
    cli

    ; Minimal CPU state marker (placeholder)
    ; In a future custom kernel, this will be used to route into stage1.

    hlt
    jmp boot_stage0_entry


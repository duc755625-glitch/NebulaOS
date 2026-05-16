; Educational stage1 entrypoint.
; Not currently wired into Limine.

BITS 64
GLOBAL boot_stage1_entry

boot_stage1_entry:
    cli
    ; Placeholder: later can set up GDT/IDT, switch stacks, etc.
.hang:
    hlt
    jmp .hang


; Educational x86_64 CPU helpers.
; Not currently wired into the live boot chain.

BITS 64

GLOBAL cpu_halt
GLOBAL cpu_pause

cpu_pause:
    pause
    ret

cpu_halt:
    cli
.hlt:
    hlt
    jmp .hlt


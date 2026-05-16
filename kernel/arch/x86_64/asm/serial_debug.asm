; Educational serial debug stubs for NebulaOS.
; Optional; not currently wired into the live Limine → Linux boot.
;
; Uses COM1 (0x3F8).

BITS 64

GLOBAL serial_write_char
GLOBAL serial_init

serial_init:
    ; Basic COM1 init: 115200-8N1-ish defaults.
    ; divisor for 115200 with 115200 clock assumption is 1.
    mov dx, 0x3F8
    mov al, 0x00
    out dx, al

    mov al, 0x80
    out dx, al

    ; divisor low
    mov dx, 0x3F8
    mov al, 0x01
    out dx, al

    ; divisor high
    mov dx, 0x3F9
    mov al, 0x00
    out dx, al

    ; 8 bits, no parity, 1 stop
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al

    ; enable FIFO
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al

    ; modem control
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al

    ret

; serial_write_char(char in AL)
serial_write_char:
    push rdx

    mov dx, 0x3F8
.wait:
    in al, dx
    ; LSR: bit 5 == THR empty
    test al, 0x20
    jz .wait

    pop rdx
    mov dx, 0x3F8
    out dx, al

    ret


#include <stdint.h>
#include <stddef.h>

// VGA text mode (80x25)
static volatile uint16_t *const vga = (volatile uint16_t *)0xB8000;
static uint8_t *const vga_attr = (uint8_t *)0;

static size_t cursor_row = 0;
static size_t cursor_col = 0;
static uint8_t attr = 0x0F; // white on black

static inline void outb(uint16_t port, uint8_t val)
{
    __asm__ __volatile__("outb %0, %1" : : "a"(val), "Nd"(port));
}
static inline uint8_t inb(uint16_t port)
{
    uint8_t ret;
    __asm__ __volatile__("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

// Serial (COM1)
static int serial_initialized = 0;
static int serial_ready()
{
    return serial_initialized;
}

static void serial_init()
{
    // 0x3F8 COM1
    uint16_t base = 0x3F8;

    outb(base + 1, 0x00); // Disable interrupts
    outb(base + 3, 0x80); // Enable DLAB
    outb(base + 0, 0x03); // Divisor lo (38400)
    outb(base + 1, 0x00); // Divisor hi
    outb(base + 3, 0x03); // 8 bits, no parity, one stop bit
    outb(base + 2, 0xC7); // Enable FIFO, clear, with 14-byte threshold
    outb(base + 4, 0x0B); // IRQ enabled, RTS/DSR set
    (void)inb(base + 5);

    serial_initialized = 1;
}

static void serial_putc(char c)
{
    if (!serial_ready())
        serial_init();
    uint16_t base = 0x3F8;
    // Wait for transmit holding register empty
    while ((inb(base + 5) & 0x20) == 0)
    {
        __asm__ __volatile__("pause");
    }
    outb(base + 0, (uint8_t)c);
}

static void vga_putc(char c)
{
    if (c == '\n')
    {
        cursor_row++;
        cursor_col = 0;
    }
    else if (c == '\r')
    {
        cursor_col = 0;
    }
    else
    {
        const size_t i = cursor_row * 80 + cursor_col;
        vga[i] = (uint16_t)(attr << 8) | (uint8_t)c;
        cursor_col++;
        if (cursor_col >= 80)
        {
            cursor_col = 0;
            cursor_row++;
        }
    }

    if (cursor_row >= 25)
    {
        // scroll up by one line
        for (size_t r = 1; r < 25; r++)
        {
            for (size_t cc = 0; cc < 80; cc++)
            {
                vga[(r - 1) * 80 + cc] = vga[r * 80 + cc];
            }
        }
        // clear last line
        for (size_t cc = 0; cc < 80; cc++)
        {
            vga[(24) * 80 + cc] = (uint16_t)(attr << 8) | ' ';
        }
        cursor_row = 24;
    }
}

void console_putc(char c)
{
    serial_putc(c);
    vga_putc(c);
}

void console_write(const char *s)
{
    for (; *s; s++)
        console_putc(*s);
}

void console_write_hex(uint64_t x)
{
    static const char *hex = "0123456789ABCDEF";
    for (int i = 60; i >= 0; i -= 4)
    {
        console_putc(hex[(x >> i) & 0xF]);
    }
}

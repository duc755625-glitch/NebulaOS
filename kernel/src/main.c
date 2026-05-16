#include <stdint.h>
#include <stddef.h>

void console_write(const char *s);
void console_write_hex(uint64_t x);

// Minimal Limine request/response structs (subset)
// We intentionally keep this minimal to bootstrap.

// Limine boot protocol: request alignment/section usually required.
// The Limine loader will locate these symbols by exact names.

// We use a kernel entry point provided by Limine.

// The Limine binary expects a global struct named `limine_entry`.
// For simplicity, we implement a Limine-compatible entry and use
// common revision/struct patterns.

struct limine_memmap
{
    uint64_t addr;
    uint64_t len;
};

struct limine_tag
{
    uint64_t type;
    uint64_t size;
    void *data;
};

// Limine provides a handoff structure at runtime; for a minimal milestone
// we just print a banner.

// Limine uses the symbol `limine_kernel_entry` as entry point on x86_64.
// We'll export `_start` instead and rely on Limine to jump here.

__attribute__((noreturn)) void _start(void)
{
    console_write("NebulaOS: minimal kernel booted\n");
    console_write("Serial+Screen console active.\n");
    console_write("UEFI+Limine pipeline reaching stage 1.\n");

    console_write("Kernel loop...\n");
    for (;;)
    {
        __asm__ __volatile__("hlt");
    }
}

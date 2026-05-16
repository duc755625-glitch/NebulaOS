// Minimal UEFI PE32+ app.
// Milestone goal: boot in QEMU UEFI and print a line.
// Next milestone will load boot/kernel.elf, exit boot services, and jump.

#include <stdint.h>

typedef uint64_t EFI_STATUS;
typedef void *EFI_HANDLE;

// Minimal typedefs
typedef unsigned short CHAR16;

// Minimal console output protocol
typedef EFI_STATUS (*EFI_OUT_STRING)(void *This, const CHAR16 *String);

typedef struct
{
    void *Reset;
    EFI_OUT_STRING OutputString;
} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;

// Minimal boot services table (unused in milestone)
typedef struct EFI_BOOT_SERVICES EFI_BOOT_SERVICES;

// Minimal system table
typedef struct EFI_SYSTEM_TABLE
{
    void *Hdr;
    void *ConIn;
    void *ConOut;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOutProtocol;
    EFI_BOOT_SERVICES *BootServices;
} EFI_SYSTEM_TABLE;

// Standard UEFI entry point
// gnu-efi expects EFIAPI/EfiMain naming; we declare with default C ABI.
EFI_STATUS EfiMain(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
{
    (void)ImageHandle;

    if (SystemTable && SystemTable->ConOutProtocol && SystemTable->ConOutProtocol->OutputString)
    {
        static const CHAR16 msg[] = {
            'N', 'e', 'b', 'u', 'l', 'a', 'O', 'S', ' ', 'B', 'o', 'o', 't', 'i', 'n', 'g', '.', '.', '.', '\r', '\n', 0};
        // OutputString signature: (This, String)
        SystemTable->ConOutProtocol->OutputString(SystemTable->ConOutProtocol, msg);
    }

    // Milestone: return success. Real loader integration comes next.
    return 0;
}

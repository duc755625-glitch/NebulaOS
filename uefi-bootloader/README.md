Minimal UEFI bootloader scaffold (no GRUB, no Limine).

Directory:
- nebulaos/uefi-bootloader/src/main.c
- nebulaos/uefi-bootloader/linker.ld
- nebulaos/uefi-bootloader/build.sh

Milestone steps:
1) Build BOOTX64.EFI using a working gnu-efi toolchain.
2) Replace placeholder BOOTX64.EFI in `nebulaos/scripts/build-iso.sh` with the built artifact.

This scaffold currently only prints a banner and returns success.
Next milestone will implement loading `boot/kernel.elf` and jumping to it, then exiting BootServices.


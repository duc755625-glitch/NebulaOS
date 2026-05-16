#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEBULA_DIR="$ROOT_DIR/nebulaos"
OUT_DIR="$NEBULA_DIR/out"
ISO_DIR="$OUT_DIR/iso"
BUILD_DIR="$OUT_DIR/build"

KERNEL_OUT="$NEBULA_DIR/build/kernel"
INITRD_OUT="$OUT_DIR/initramfs"

mkdir -p "$OUT_DIR" "$ISO_DIR" "$BUILD_DIR"

# Stage 0: deps
"$NEBULA_DIR/scripts/check-deps.sh"

echo "[NebulaOS] Stage 0a: build educational NASM boot stubs (non-runtime)" >&2
make -C "$NEBULA_DIR/kernel/arch/x86_64/boot" all >/dev/null 2>&1 || true

echo "[NebulaOS] Stage 1: build NebulaOS kernel bundle (Ubuntu 6.6 LTS mainline)..." >&2
chmod +x "$NEBULA_DIR/scripts/build-kernel-bundle.sh" || true
"$NEBULA_DIR/scripts/build-kernel-bundle.sh"

echo "[NebulaOS] Stage 2: build offline NebulaOS rootfs image..." >&2
chmod +x "$NEBULA_DIR/scripts/build-rootfs-image.sh" || true
"$NEBULA_DIR/scripts/build-rootfs-image.sh"

echo "[NebulaOS] Stage 3: build NebulaOS initramfs..." >&2
chmod +x "$NEBULA_DIR/initramfs/build-initramfs.sh" || true
"$NEBULA_DIR/initramfs/build-initramfs.sh"

ROOTFS_IMAGE="$OUT_DIR/rootfs/rootfs.squashfs"
KERNEL_VMLINUZ="$KERNEL_OUT/vmlinuz"
KERNEL_MODULES_DIR="$KERNEL_OUT/modules"
KERNEL_FIRMWARE_DIR="$KERNEL_OUT/firmware"
INITRAMFS_CPIO="$INITRD_OUT/initramfs.cpio"

if [ ! -f "$KERNEL_VMLINUZ" ]; then
  echo "Kernel vmlinuz missing: $KERNEL_VMLINUZ" >&2
  exit 1
fi
if [ ! -f "$ROOTFS_IMAGE" ]; then
  echo "Rootfs image missing: $ROOTFS_IMAGE" >&2
  exit 1
fi
if [ ! -f "$INITRAMFS_CPIO" ]; then
  echo "Initramfs cpio missing: $INITRAMFS_CPIO" >&2
  exit 1
fi

echo "[NebulaOS] Stage 3: assemble UEFI-only ISO..." >&2
ISO_WORK="$BUILD_DIR/iso_work"
rm -rf "$ISO_WORK"
mkdir -p "$ISO_WORK/efi/boot" "$ISO_WORK/kernel" "$ISO_WORK/initramfs" "$ISO_WORK/rootfs"

# Create a minimal boot entry using Limine.
# For Limine linux protocol, we place:
#   /kernel/vmlinuz
#   /kernel/modules/**
#   /kernel/firmware/**
#   /initramfs/initramfs.cpio
#   /rootfs/rootfs.squashfs
# and put limine.conf where Limine for EFI will find it:
#   <BOOTX64.EFI dir>/limine.conf  => /efi/boot/limine.conf

cp -f "$NEBULA_DIR/limine.cfg" "$ISO_WORK/efi/boot/limine.conf"

cp -f "$KERNEL_VMLINUZ" "$ISO_WORK/kernel/vmlinuz"
if [ -d "$KERNEL_MODULES_DIR" ]; then
  cp -a "$KERNEL_MODULES_DIR" "$ISO_WORK/kernel/"
fi
if [ -d "$KERNEL_FIRMWARE_DIR" ]; then
  cp -a "$KERNEL_FIRMWARE_DIR" "$ISO_WORK/kernel/"
fi

cp "$INITRAMFS_CPIO" "$ISO_WORK/initramfs/initramfs.cpio"
cp "$ROOTFS_IMAGE" "$ISO_WORK/rootfs/rootfs.squashfs"

# Build Limine UEFI bootloader (real BOOTX64.EFI) and place it at EFI/BOOT.
# This is required for UEFI boot in QEMU/VMware/VirtualBox.

LININE_DIR="$NEBULA_DIR/boot/limine/limine"

echo "[NebulaOS] Stage 3a: building Limine UEFI x86_64..." >&2
# Build limine-uefi-x86-64 (produces BOOTX64.EFI)
make -C "$LININE_DIR" limine-uefi-x86-64

# Locate produced BOOTX64.EFI
# Limine installs to its build output directory; we search within limine/ for BOOTX64.EFI.
BOOTX64_SRC="$(find "$LININE_DIR" -name BOOTX64.EFI -print -quit)"
if [ -z "$BOOTX64_SRC" ] || [ ! -f "$BOOTX64_SRC" ]; then
  echo "[NebulaOS] ERROR: Could not locate built BOOTX64.EFI under $LININE_DIR" >&2
  exit 1
fi

echo "[NebulaOS] Limine BOOTX64.EFI: $BOOTX64_SRC" >&2

cp -f "$BOOTX64_SRC" "$ISO_WORK/efi/boot/BOOTX64.EFI"
chmod +w "$ISO_WORK/efi/boot/BOOTX64.EFI"


# Create ISO with FAT EFI System partition
ISO_PATH="$ISO_DIR/NebulaOS.iso"

# Use xorriso to generate ISO9660 + El Torito EFI boot
# Note: true bootable UEFI requires a real BOOTX64.EFI binary.
# This milestone ensures filesystem layout + pipeline works.

xorriso -as mkisofs \
  -iso-level 3 -R -J \
  -V "NebulaOS" \
  -o "$ISO_PATH" \
  -eltorito-alt-boot \
  -e efi/boot/BOOTX64.EFI \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$ISO_WORK" >/dev/null

echo "[NebulaOS] ISO generated: $ISO_PATH" >&2

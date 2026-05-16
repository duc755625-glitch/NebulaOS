#!/usr/bin/env bash
set -euo pipefail

# UEFI-only minimal milestone dependencies.
# GRUB utilities are intentionally NOT required.

REQ=(
  gcc
  g++
  make
  nasm
  xorriso

# (ASM scaffolding) educational OSDev stubs require ld/objcopy as well

  cpio
  rsync

  # kernel assets
  wget
  tar
  dpkg-deb
  ar
  sha256sum
  apt-get

  # rootfs build (no debootstrap; we build from a prebuilt rootfs tarball)
  mksquashfs
  xz
  wget
  curl
  proot
)

missing=()
for cmd in "${REQ[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if [ "${#missing[@]}" -ne 0 ]; then
  echo "Missing required commands/tools:" >&2
  printf ' - %s\n' "${missing[@]}" >&2
  echo
  echo "Install guidance (MSYS2/MINGW64):" >&2
  echo "  pacman -S --noconfirm --needed gcc make nasm xorriso cpio rsync" >&2
  exit 1
fi

echo "All required commands are present."

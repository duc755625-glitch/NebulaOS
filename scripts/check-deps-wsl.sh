#!/usr/bin/env bash
set -euo pipefail

REQ=(
  gcc
  g++
  make
  cmake
  nasm
  xorriso
  grub-mkstandalone
  grub-mkimage
  grub-install
  grub-probe
  xz
  cpio
  rsync
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
  echo "On Ubuntu/Debian/WSL, install with:" >&2
  echo "sudo apt-get update" >&2
  echo "sudo apt-get install -y build-essential cmake nasm xorriso grub-pc-bin grub-efi-amd64-bin grub-common xz-utils cpio rsync" >&2
  exit 1
fi

echo "All required commands are present." 


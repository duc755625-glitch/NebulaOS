#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISO_PATH="$ROOT_DIR/nebulaos/out/iso/NebulaOS.iso"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS.fd}"

if [ ! -f "$ISO_PATH" ]; then
  echo "Missing ISO: $ISO_PATH" >&2
  exit 1
fi

if [ ! -f "$OVMF_CODE" ] || [ ! -f "$OVMF_VARS" ]; then
  echo "OVMF not found. Set OVMF_CODE/OVMF_VARS env vars." >&2
  exit 1
fi

# Start QEMU paused with GDB stub
exec "$QEMU_BIN" \
  -m 2048 \
  -smp 2 \
  -machine q35 \
  -cpu qemu64 \
  -drive if=pflash,format=raw,readonly,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -cdrom "$ISO_PATH" \
  -boot menu=on \
  -serial stdio \
  -S -gdb tcp::1234 \
  -display gtk


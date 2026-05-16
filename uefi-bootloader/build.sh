#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BL_DIR="$ROOT_DIR/uefi-bootloader"
OUT_DIR="$ROOT_DIR/../out/uefi"
mkdir -p "$OUT_DIR"

# Expect gnu-efi toolchain.
# You may need to install gnu-efi + pkg-config paths for your environment.

CC="${CC:-x86_64-w64-mingw32-gcc}"
LD="${LD:-x86_64-w64-mingw32-ld}"

GNU_EFI_ROOT="${GNU_EFI_ROOT:-/usr/lib}" 

# Allow override.
CFLAGS=(
  -Os
  -ffreestanding
  -fno-stack-protector
  -fno-builtin
  -nostdlib
  -mno-red-zone
)

SRC="$BL_DIR/src/main.c"
LINK_LD="$BL_DIR/linker.ld"

OBJ="$OUT_DIR/boot.o"

# gnu-efi headers/libs are typically under system; adapt if needed.
# We compile without uefi headers for minimal milestone if headers are present.

"$CC" -c "$SRC" -o "$OBJ" \
  -I${GNU_EFI_ROOT}/include 2>/dev/null || "$CC" -c "$SRC" -o "$OBJ"

# Link as PE32+
"$LD" -T "$LINK_LD" "$OBJ" -o "$OUT_DIR/BOOTX64.EFI" \
  -L${GNU_EFI_ROOT}/lib 2>/dev/null || "$LD" -T "$LINK_LD" "$OBJ" -o "$OUT_DIR/BOOTX64.EFI"

echo "UEFI bootloader built: $OUT_DIR/BOOTX64.EFI"


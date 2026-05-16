#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/../out/initramfs"
WORK="$OUT_DIR/work"

mkdir -p "$OUT_DIR" "$WORK"/bin "$WORK"/dev "$WORK"/proc "$WORK"/sys "$WORK"/sbin "$WORK"/newroot

# Ensure we have a static BusyBox inside the initramfs so we get:
#  - pivot_root/switch_root
#  - mount/ip/ln/cp/ls/sh utilities
#
# This is build-time only. ISO boot does not download anything.
BB_BIN=""
if [ -f /bin/busybox ]; then
  :
fi

if command -v busybox-static >/dev/null 2>&1; then
  BB_BIN="$(command -v busybox-static)"
elif command -v busybox >/dev/null 2>&1; then
  # If host has busybox but it's not static, we'll still try to use it.
  BB_BIN="$(command -v busybox)"
fi

if [ -z "$BB_BIN" ]; then
  echo "[NebulaOS] initramfs: busybox(-static) not found. Attempting to install busybox-static..." >&2
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y busybox-static >/dev/null
    if command -v busybox-static >/dev/null 2>&1; then
      BB_BIN="$(command -v busybox-static)"
    elif [ -f /bin/busybox ]; then
      BB_BIN="/bin/busybox"
    fi
  fi
fi

if [ -z "$BB_BIN" ] || [ ! -f "$BB_BIN" ]; then
  echo "[NebulaOS] ERROR: Could not locate a busybox binary to embed into initramfs." >&2
  exit 1
fi

echo "[NebulaOS] initramfs: embedding busybox from: $BB_BIN" >&2

# Copy init + busybox
INIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/init"
cp "$INIT_SRC" "$WORK/init"
chmod +x "$WORK/init"

cp "$BB_BIN" "$WORK/bin/busybox"
chmod +x "$WORK/bin/busybox"

# BusyBox applets symlinks (common set; enough for switch_root + mount helpers)
# BusyBox works via symlink argv[0].
for a in sh mount umount mkdir modprobe dmesg sleep ls cat echo ln cp mv rm kill killall pkill ifconfig ip route sysctl tee uname pivot_root switch_root; do
  ln -sf /bin/busybox "$WORK/bin/$a" 2>/dev/null || true
done

# Also provide a /sbin symlink to keep init paths standard
ln -sfn /bin/busybox "$WORK/sbin/busybox" 2>/dev/null || true

# Minimal /dev nodes (optional; devtmpfs may populate later)
# We'll keep initramfs small; kernel may create /dev via devtmpfs.
# Add only what exists as regular files? best-effort not required.

# Pack initramfs as newc cpio
cd "$WORK"
rm -f "$OUT_DIR/initramfs.cpio"
find . -mindepth 1 -print0 | cpio --null -ov --format=newc > "$OUT_DIR/initramfs.cpio"

echo "Created initramfs: $OUT_DIR/initramfs.cpio"

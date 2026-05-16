#!/usr/bin/env bash
set -euo pipefail

# Builds an offline rootfs image for NebulaOS ISO WITHOUT debootstrap.
# Approach:
#  - Download Ubuntu 24.04 minimal cloud image rootfs tarball (as an xz)
#  - Extract into nebulaos/build/rootfs/work using unprivileged tools
#  - Customize inside the rootfs with proot (no sudo at customization time)
#  - Install a minimal Wayland baseline (weston) + Mesa tooling (build-time download allowed)
#  - Package final rootfs into squashfs for inclusion in ISO
#
# Output:
#   nebulaos/out/rootfs/rootfs.squashfs
#
# Initramfs expects:
#   /mnt/nebula_iso/rootfs/rootfs.squashfs

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEBULA_DIR="$ROOT_DIR/nebulaos"
OUT_DIR="$NEBULA_DIR/out"
ROOTFS_DIR="$OUT_DIR/rootfs"
ROOTFS_WORK="$ROOTFS_DIR/work"
OUT_IMAGE="$ROOTFS_DIR/rootfs.squashfs"

mkdir -p "$ROOTFS_WORK" "$ROOTFS_DIR"

: "${UBUNTU_TARBALL_URL:=https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64-root.tar.xz}"
: "${UBUNTU_TARBALL_SHA256:=}"
: "${ARCH:=amd64}"

CACHE_DIR="$NEBULA_DIR/cache/rootfs"
mkdir -p "$CACHE_DIR"
TARBALL_NAME="$(basename "$UBUNTU_TARBALL_URL")"
TARBALL_PATH="$CACHE_DIR/$TARBALL_NAME"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[NebulaOS] ERROR: Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd wget
require_cmd xz
require_cmd tar
require_cmd rsync
require_cmd mksquashfs
require_cmd proot

echo "[NebulaOS] Stage: download Ubuntu minimal rootfs tarball..." >&2
if [ ! -f "$TARBALL_PATH" ]; then
  wget -q -O "$TARBALL_PATH" "$UBUNTU_TARBALL_URL"
fi

if [ -n "$UBUNTU_TARBALL_SHA256" ]; then
  echo "[NebulaOS] Verifying SHA256..." >&2
  echo "$UBUNTU_TARBALL_SHA256  $TARBALL_PATH" | sha256sum -c -
fi

echo "[NebulaOS] Stage: extract rootfs (uncompressed)..." >&2
rm -rf "$ROOTFS_WORK"
mkdir -p "$ROOTFS_WORK"

tar -xf "$TARBALL_PATH" -C "$ROOTFS_WORK"

# Ensure essential dirs
mkdir -p "$ROOTFS_WORK"/dev "$ROOTFS_WORK"/proc "$ROOTFS_WORK"/sys "$ROOTFS_WORK"/run "$ROOTFS_WORK"/tmp

# Basic system files that initramfs/systemd expect
if [ ! -f "$ROOTFS_WORK/etc/fstab" ]; then
  cat > "$ROOTFS_WORK/etc/fstab" <<'EOF'
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
EOF
fi

# Provide a NebulaOS user and systemd target for graphical boot.
# We do this via proot to avoid sudo/chroot.
ROOT_PROOT="$ROOTFS_WORK"

# Install/upgrade base networking bits to allow systemd units to start; package installs
# are allowed at build time (offline at boot).
# IMPORTANT: We do not attempt to "keep ISO offline" during this build step; we only ensure
# no network is required at runtime.
echo "[NebulaOS] Stage: proot customization + install Wayland baseline..." >&2

# Detect whether apt exists in the extracted rootfs.
if [ ! -x "$ROOT_PROOT/usr/bin/apt-get" ] && [ ! -x "$ROOT_PROOT/bin/apt-get" ] && [ ! -x "$ROOT_PROOT/usr/bin/dpkg" ]; then
  echo "[NebulaOS] ERROR: Extracted rootfs doesn't appear to have apt/dpkg." >&2
  exit 1
fi

# proot environment: map rootfs as /
export PROOT_BIN="proot"
# Use a resolv.conf to allow apt to work during build. (Build-time only.)
cp -f /etc/resolv.conf "$ROOT_PROOT/etc/resolv.conf" 2>/dev/null || true

# Add basic nebula user if missing
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c 'id -u nebula >/dev/null 2>&1 || useradd -m -s /bin/bash nebula || true'

# Create sudoers
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c 'mkdir -p /etc/sudoers.d; printf "nebula ALL=(ALL) NOPASSWD:ALL\n" > /etc/sudoers.d/nebula; chmod 0440 /etc/sudoers.d/nebula || true'

# Create NebulaOS systemd service that runs weston baseline on tty1.
# This will later be replaced by NebulaOS custom shell; for v1 we ensure we reach graphics reliably.
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c '
mkdir -p /etc/systemd/system;
cat > /etc/systemd/system/nebulaos-wayland.service << "EOF"
[Unit]
Description=NebulaOS Wayland session (weston baseline)
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=simple
User=nebula
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/usr/bin/weston --backend=drm-backend.so --tty=1 --shell=weston-terminal-shell.so
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF
'

# Ensure graphical.target is default
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c 'ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target 2>/dev/null || true'

# Install packages: weston + Mesa tooling + fonts.
# We avoid huge stacks; v1 is only “boots to a working compositor”.
PACKAGES=(
  systemd
  udev
  dbus
  weston
  xwayland
  mesa-utils
  libdrm2
  libgbm1
  libegl1
  libgles2
  fonts-dejavu
  fontconfig
  xdg-utils
  dbus-user-session
)

# apt update + install inside rootfs using proot.
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c '
export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y '"$(printf '%s ' "${PACKAGES[@]}")"';
rm -rf /var/lib/apt/lists/*;
' || true

# Cleanup some caches to reduce squashfs size.
$PROOT_BIN -R "$ROOT_PROOT" -w / /bin/sh -c '
rm -rf /var/cache/apt/archives/* /tmp/* || true
' || true

echo "[NebulaOS] Stage: create squashfs..." >&2
rm -f "$OUT_IMAGE"
mksquashfs "$ROOTFS_WORK" "$OUT_IMAGE" -noappend -comp xz -b 1048576 >/dev/null

echo "[NebulaOS] Rootfs image created: $OUT_IMAGE" >&2

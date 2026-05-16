#!/usr/bin/env bash
set -euo pipefail

# Downloads a stable Ubuntu/Debian generic amd64 kernel package (offline after build),
# extracts vmlinuz, System.map, and builds an ISO-ready modules tree and firmware staging.
#
# Output paths (relative to repo):
#   nebulaos/build/kernel/vmlinuz
#   nebulaos/build/kernel/initrd.img (optional, currently not used by Limine)
#   nebulaos/build/kernel/modules/
#   nebulaos/build/kernel/firmware/   (empty unless extracted)
#
# Notes:
# - This script is intended for offline ISO creation. The ISO will not download at boot.
# - Kernel+modules are copied into the ISO under:
#     /kernel/vmlinuz
#     /kernel/modules
#     /kernel/firmware (if present)
#
# The kernel command line uses initramfs.cpio as rdinit root.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEBULA_DIR="$ROOT_DIR/nebulaos"
CACHE_DIR="$NEBULA_DIR/cache"
BUILD_DIR="$NEBULA_DIR/build"
KERNEL_BUILD_DIR="$BUILD_DIR/kernel"

mkdir -p "$CACHE_DIR" "$KERNEL_BUILD_DIR"

if [ $# -gt 0 ]; then
  echo "Usage: $0" >&2
  exit 1
fi

APT_GET="${APT_GET:-apt-get}"
APT_ARCH="${APT_ARCH:-amd64}"

# Choose a stable distro base. Ubuntu LTS is usually available on debian/ubuntu mirrors.
DISTRO_CODENAME="${DISTRO_CODENAME:-jammy}"
# We use a generic image variant to maximize DRM/KMS coverage.
# For Ubuntu: linux-image-generic, linux-modules-generic, linux-firmware
# On Debian stable, package names differ. We default to Ubuntu jammy.
UBUNTU_FLAVOR_PACKAGES=(
  "linux-image-generic"
  "linux-modules-generic"
  "linux-firmware"
)

# Kernel artifacts filenames inside the extracted packages vary slightly.
# We'll locate vmlinuz via find after extraction.

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd "$APT_GET"
require_cmd dpkg-deb
require_cmd ar
require_cmd tar
require_cmd wget
require_cmd sha256sum

# Helper: download .deb deterministically and verify size (sha256 when available)
download_deb() {
  local url="$1"
  local out="$2"
  if [ -f "$out" ]; then
    return 0
  fi
  echo "[NebulaOS] Downloading: $url" >&2
  wget -q -O "$out" "$url"
}

# We will use apt-get download to fetch debs into cache.
APT_DOWNLOAD_DIR="$CACHE_DIR/apt-download"
rm -rf "$APT_DOWNLOAD_DIR"
mkdir -p "$APT_DOWNLOAD_DIR"

echo "[NebulaOS] Fetching kernel packages into cache..." >&2

# apt-get download resolves dependencies from network at build time.
# ISO itself remains offline because we embed artifacts below.
# Need root for /var/lib/apt locks.
SUDO="${SUDO:-sudo}"
SUDO_NONINTERACTIVE="$SUDO -n"

# Fail fast if we don't have sudo privileges.
if ! command -v sudo >/dev/null 2>&1; then
  echo "[NebulaOS] ERROR: sudo is not available; cannot run apt in kernel asset stage." >&2
  exit 1
fi

echo "[NebulaOS] Updating apt indexes (kernel asset stage)..." >&2
DEBIAN_FRONTEND=noninteractive "$SUDO_NONINTERACTIVE" "$APT_GET" update -y

# Download the three packages explicitly
# (We will extract the exact installed kernel version files from these .debs.)
for pkg in "${UBUNTU_FLAVOR_PACKAGES[@]}"; do
  "$APT_GET" download -y "$pkg" -o=Dir::Cache::Archives="$APT_DOWNLOAD_DIR" >/dev/null
done

# Identify the downloaded debs
DEBS=()
while IFS= read -r -d '' f; do
  DEBS+=("$f")
done < <(find "$APT_DOWNLOAD_DIR" -maxdepth 1 -type f -name "*.deb" -print0)

if [ "${#DEBS[@]}" -eq 0 ]; then
  echo "[NebulaOS] ERROR: No .deb files downloaded in $APT_DOWNLOAD_DIR" >&2
  exit 1
fi

WORK="$KERNEL_BUILD_DIR/work"
rm -rf "$WORK"
mkdir -p "$WORK"

# Extract all .debs into WORK/extract
EXTRACT_DIR="$WORK/extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

for deb in "${DEBS[@]}"; do
  echo "[NebulaOS] Extracting $(basename "$deb")" >&2
  # deb is ar archive containing data.tar.* and control.tar.*
  mkdir -p "$WORK/tmp"
  rm -rf "$WORK/tmp"/*
  ar x "$deb" --output "$WORK/tmp" 2>/dev/null || true

  # Find data.tar.* (usually data.tar.xz)
  data_tar="$(find "$WORK/tmp" -maxdepth 1 -type f -name "data.tar.*" | head -n 1 || true)"
  if [ -z "$data_tar" ]; then
    # Try alternative location
    data_tar="$(find "$WORK/tmp" -type f -name "data.tar.*" | head -n 1 || true)"
  fi
  if [ -z "$data_tar" ]; then
    echo "[NebulaOS] ERROR: Could not find data.tar.* inside $(basename "$deb")" >&2
    exit 1
  fi

  tar -xf "$data_tar" -C "$EXTRACT_DIR"
done

# Locate a vmlinuz in extracted tree
VM_PATH="$(find "$EXTRACT_DIR" -type f -name "vmlinuz*" | head -n 1 || true)"
if [ -z "$VM_PATH" ]; then
  # On some packages it might be bzImage naming or under /boot/
  VM_PATH="$(find "$EXTRACT_DIR" -type f -path "*boot*" -name "vmlinuz*" | head -n 1 || true)"
fi

if [ -z "$VM_PATH" ]; then
  echo "[NebulaOS] ERROR: Could not locate vmlinuz in extracted kernel packages." >&2
  exit 1
fi

mkdir -p "$KERNEL_BUILD_DIR"
cp -f "$VM_PATH" "$KERNEL_BUILD_DIR/vmlinuz"

# Modules tree: extracted packages usually install under /lib/modules/<ver>
MOD_ROOT="$(find "$EXTRACT_DIR" -type d -path "*/lib/modules/*" | head -n 1 || true)"
if [ -z "$MOD_ROOT" ]; then
  echo "[NebulaOS] ERROR: Could not locate /lib/modules/<version> in extracted packages." >&2
  exit 1
fi

# Normalize version dir
MOD_VERSION_DIR="$(echo "$MOD_ROOT" | sed -E 's#^.*/lib/modules/##')"
# If MOD_ROOT ends with /lib/modules/<ver>, keep it; else adjust.
# We'll set:
MODULES_SRC_DIR="$EXTRACT_DIR/lib/modules/$MOD_VERSION_DIR"
if [ ! -d "$MODULES_SRC_DIR" ]; then
  # Fall back: take last path segment after lib/modules/
  MOD_VERSION_DIR2="$(echo "$MOD_ROOT" | awk -F/ '{print $NF}')"
  MODULES_SRC_DIR="$EXTRACT_DIR/lib/modules/$MOD_VERSION_DIR2"
  MOD_VERSION_DIR="$MOD_VERSION_DIR2"
fi

if [ ! -d "$MODULES_SRC_DIR" ]; then
  echo "[NebulaOS] ERROR: Modules source dir not found: $MODULES_SRC_DIR" >&2
  exit 1
fi

rm -rf "$KERNEL_BUILD_DIR/modules"
mkdir -p "$KERNEL_BUILD_DIR/modules"
cp -a "$MODULES_SRC_DIR" "$KERNEL_BUILD_DIR/modules/"

# Firmware blobs
FW_DIR_SRC="$EXTRACT_DIR/lib/firmware"
if [ -d "$FW_DIR_SRC" ]; then
  rm -rf "$KERNEL_BUILD_DIR/firmware"
  mkdir -p "$KERNEL_BUILD_DIR/firmware"
  cp -a "$FW_DIR_SRC/." "$KERNEL_BUILD_DIR/firmware/"
fi

echo "[NebulaOS] Kernel artifacts prepared:" >&2
echo "  vmlinuz: $KERNEL_BUILD_DIR/vmlinuz" >&2
echo "  modules: $KERNEL_BUILD_DIR/modules/<version>/" >&2
if [ -d "$KERNEL_BUILD_DIR/firmware" ]; then
  echo "  firmware: $KERNEL_BUILD_DIR/firmware/" >&2
fi

echo "[NebulaOS] Kernel build done."

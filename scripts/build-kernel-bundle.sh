#!/usr/bin/env bash
set -euo pipefail

# DEBUG=1 => preserve intermediate extraction evidence on failure.
DEBUG="${DEBUG:-0}"

if [ "${DEBUG}" = "1" ]; then
  set -x
fi


# Builds a NebulaOS kernel bundle.
#
# Kernel artifact acquisition/extraction backend is intended to be tarball-based
# (no dpkg-deb/ar extraction logic), producing outputs consumed by build-iso.sh.


# Debugging instrumentation (needed because CI/output capture is flaky):
# - prints the failing line number and exit code
# - ensures errors are visible immediately
# - preserves intermediate extraction evidence when DEBUG=1
trap 'rc=$?;
  echo "[NebulaOS] ERROR: build-kernel-bundle.sh failed at line ${LINENO} (exit=${rc})" >&2;
  if [ "${DEBUG}" = "1" ]; then
    echo "[NebulaOS] DEBUG=1 enabled: preserving WORK_DIR evidence" >&2;
    echo "[NebulaOS] retained paths:" >&2;
    echo "  - ${WORK_DIR}" >&2;
    echo "  - ${CACHE_DIR}" >&2;
  fi;
  exit $rc
' ERR


checkpoint() {
  # checkpoint_file is created after NEBULA_DIR is known
  if [ -n "${checkpoint_file:-}" ]; then
    echo "[NebulaOS] checkpoint: $1" | tee -a "$checkpoint_file" >&2
  else
    echo "[NebulaOS] checkpoint: $1" >&2
  fi
}






#
# Output:
#   nebulaos/build/kernel/
#     vmlinuz
#     modules/<kernel-version>/
#     firmware/
#
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEBULA_DIR="$ROOT_DIR/nebulaos"
CACHE_DIR="$NEBULA_DIR/cache/kernel"
BUILD_DIR="$NEBULA_DIR/build/kernel"
WORK_DIR="$NEBULA_DIR/build/kernel/work"

mkdir -p "$CACHE_DIR" "$BUILD_DIR" "$WORK_DIR"

: "${KERNEL_SERIES:=v6.6}"
: "${KERNEL_VERSION:=v6.6.10}"
: "${CURL_BIN:=curl}"
: "${WGET_BIN:=wget}"
: "${FIRMWARE_TARBALL_URL:=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/linux-firmware-snapshot.tar.gz}"

BUNDLE_OUT_VMLINUZ="$BUILD_DIR/vmlinuz"
BUNDLE_OUT_MODULES_DIR="$BUILD_DIR/modules"
BUNDLE_OUT_FIRMWARE_DIR="$BUILD_DIR/firmware"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[NebulaOS] ERROR: Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd tar
require_cmd wget || true
require_cmd curl || true
command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1

require_cmd sha256sum


fetch() {
  local url="$1"
  local out="$2"

  rm -f "$out" 2>/dev/null || true

  local attempts=${FETCH_ATTEMPTS:-3}
  local i
  for ((i=1; i<=attempts; i++)); do
    echo "[NebulaOS] fetch attempt ${i}/${attempts}: $url" >&2

    if command -v wget >/dev/null 2>&1; then
      # --tries/--timeout are for transient network hiccups
      wget -q --tries=2 --timeout=60 -O "$out" "$url" && break
    else
      curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 15 --max-time 300 -o "$out" "$url" && break
    fi

    sleep 1
  done

  if [ ! -f "$out" ] || [ ! -s "$out" ]; then
    echo "[NebulaOS] ERROR: fetch produced empty output: $out" >&2
    exit 1
  fi

  # If it's a .deb, do a lightweight integrity check (ar archive listing)
  if echo "$out" | grep -qE '\.deb$'; then
    if ! ar t "$out" >/dev/null 2>&1; then
      echo "[NebulaOS] ERROR: fetched .deb failed ar integrity check: $out" >&2
      exit 1
    fi
  fi
}


UBUNTU_MAINLINE_BASE="https://kernel.ubuntu.com/mainline"
KERNEL_URL="${UBUNTU_MAINLINE_BASE}/${KERNEL_VERSION}"
AMD64_DIR_URL="${KERNEL_URL}/amd64"

echo "[NebulaOS] Kernel series: ${KERNEL_SERIES}" >&2
echo "[NebulaOS] Pinned kernel dir: ${KERNEL_VERSION}" >&2
echo "[NebulaOS] Mainline amd64 dir: ${AMD64_DIR_URL}" >&2

# Fetch directory listing
checkpoint "start:fetch dir listing"
LIST_HTML="$WORK_DIR/amd64_index.html"
fetch "${AMD64_DIR_URL}/" "$LIST_HTML"
checkpoint "after:fetch listing"

IMG_DEB="$(grep -oE 'href="linux-image-[^"]+_amd64\.deb"' "$LIST_HTML" | head -n 1 | sed 's/href="//; s/"$//')"
MOD_DEB="$(grep -oE 'href="linux-modules-[^"]+_amd64\.deb"' "$LIST_HTML" | head -n 1 | sed 's/href="//; s/"$//')"
checkpoint "after:parse img/mod deb filenames"


if [ -z "${IMG_DEB:-}" ] || [ -z "${MOD_DEB:-}" ]; then
  echo "[NebulaOS] ERROR: Could not find linux-image/linux-modules .deb in ${AMD64_DIR_URL}" >&2
  exit 1
fi

IMG_DEB_URL="${AMD64_DIR_URL}/${IMG_DEB}"
MOD_DEB_URL="${AMD64_DIR_URL}/${MOD_DEB}"

IMG_DEB_PATH="$WORK_DIR/$IMG_DEB"
MOD_DEB_PATH="$WORK_DIR/$MOD_DEB"

mkdir -p "$CACHE_DIR"

IMG_CACHE="$CACHE_DIR/$IMG_DEB"
MOD_CACHE="$CACHE_DIR/$MOD_DEB"

if [ ! -f "$IMG_CACHE" ]; then
  echo "[NebulaOS] Downloading kernel image deb: $IMG_DEB" >&2
  fetch "$IMG_DEB_URL" "$IMG_CACHE"
else
  echo "[NebulaOS] Using cached kernel image deb: $IMG_DEB" >&2
fi

if [ ! -f "$MOD_CACHE" ]; then
  echo "[NebulaOS] Downloading kernel modules deb: $MOD_DEB" >&2
  fetch "$MOD_DEB_URL" "$MOD_CACHE"
else
  echo "[NebulaOS] Using cached kernel modules deb: $MOD_DEB" >&2
fi

# Validate caches are non-truncated (common failure mode: unexpected EOF while extracting)
# Heuristic to detect truncated downloads in a flaky network.
# Use a low threshold to avoid false positives on smaller debs (e.g., linux-image-unsigned can be ~10-20MB).
MIN_DEB_SIZE_BYTES=${MIN_DEB_SIZE_BYTES:-1000000} # 1MB
if [ "${DEBUG}" = "1" ]; then
  echo "[NebulaOS] DEBUG=1 enabled; cache files will be preserved." >&2
fi
if [ -f "$IMG_CACHE" ] && [ "$(stat -c%s "$IMG_CACHE" 2>/dev/null || echo 0)" -lt "$MIN_DEB_SIZE_BYTES" ]; then


  echo "[NebulaOS] Cache kernel image deb looks truncated; re-downloading: $IMG_DEB" >&2
  rm -f "$IMG_CACHE"
  fetch "$IMG_DEB_URL" "$IMG_CACHE"
fi
if [ -f "$MOD_CACHE" ] && [ "$(stat -c%s "$MOD_CACHE" 2>/dev/null || echo 0)" -lt "$MIN_DEB_SIZE_BYTES" ]; then
  echo "[NebulaOS] Cache kernel modules deb looks truncated; re-downloading: $MOD_DEB" >&2
  rm -f "$MOD_CACHE"
  fetch "$MOD_DEB_URL" "$MOD_CACHE"
fi


cp -f "$IMG_CACHE" "$IMG_DEB_PATH"
cp -f "$MOD_CACHE" "$MOD_DEB_PATH"


# Extract with dpkg-deb into dedicated staging dirs
KIMG_EXTRACT="$WORK_DIR/extract_kernel_img"
KMOD_EXTRACT="$WORK_DIR/extract_kernel_mods"

# Preserve evidence on failure when DEBUG=1.
if [ "${DEBUG}" != "1" ]; then
  rm -rf "$KIMG_EXTRACT" "$KMOD_EXTRACT"
fi
mkdir -p "$KIMG_EXTRACT" "$KMOD_EXTRACT"


# Kernel backend: Ubuntu mainline via .deb + dpkg-deb extraction.
# NOTE: we avoid ar/data.tar manual handling.

echo "[NebulaOS] Verifying input deb paths:" >&2
echo "  IMG_DEB_PATH: $IMG_DEB_PATH" >&2
echo "  MOD_DEB_PATH: $MOD_DEB_PATH" >&2
ls -lh "$IMG_DEB_PATH" "$MOD_DEB_PATH" >&2

# Print dpkg-deb commands before execution
echo "[NebulaOS] dpkg-deb -x \"$IMG_DEB_PATH\" \"$KIMG_EXTRACT\"" >&2
echo "[NebulaOS] dpkg-deb -x \"$MOD_DEB_PATH\" \"$KMOD_EXTRACT\"" >&2

# Extract (fail fast; do not mask exit codes)
dpkg-deb -x "$IMG_DEB_PATH" "$KIMG_EXTRACT"

# Verify image extraction produced content.
if [ ! -d "$KIMG_EXTRACT" ]; then
  echo "[NebulaOS] ERROR: KIMG_EXTRACT dir missing after dpkg-deb" >&2
  exit 1
fi
if [ -z "$(find "$KIMG_EXTRACT" -type f 2>/dev/null | head -n 1 || true)" ]; then
  echo "[NebulaOS] ERROR: KIMG_EXTRACT contains no files after dpkg-deb" >&2
  (ls -la "$KIMG_EXTRACT" 2>/dev/null || true) >&2
  exit 1
fi

set +e
dpkg-deb -x "$MOD_DEB_PATH" "$KMOD_EXTRACT"
MOD_EXTRACT_RC=$?
set -e

if [ "$MOD_EXTRACT_RC" -ne 0 ]; then
  echo "[NebulaOS] ERROR: dpkg-deb -x modules failed (rc=$MOD_EXTRACT_RC)" >&2
  echo "[NebulaOS] modules deb: $MOD_DEB_PATH" >&2
  (ls -lh "$MOD_DEB_PATH" 2>/dev/null || true) >&2
  (file "$MOD_DEB_PATH" 2>/dev/null || true) >&2
  echo "[NebulaOS] partial KMOD_EXTRACT tree preview (maxdepth 4):" >&2
  (ls -la "$KMOD_EXTRACT" 2>/dev/null || true) >&2
  (find "$KMOD_EXTRACT" -maxdepth 4 -type d 2>/dev/null | head -n 80) >&2 || true
  echo "[NebulaOS] partial modules.dep locations (max 20):" >&2
  (find "$KMOD_EXTRACT" -type f -name modules.dep 2>/dev/null | head -n 20) >&2 || true
  exit "$MOD_EXTRACT_RC"
fi

# Post-extract diagnostics for modules .deb (needed because earlier logs truncated)
# Bounded output to keep logs readable.
if [ ! -d "$KMOD_EXTRACT" ]; then
  echo "[NebulaOS] ERROR: KMOD_EXTRACT dir missing after dpkg-deb" >&2
  exit 1
fi


echo "[NebulaOS] Post-dpkg-deb: KMOD_EXTRACT tree preview (maxdepth 4):" >&2
(ls -la "$KMOD_EXTRACT" 2>/dev/null || true) >&2
(find "$KMOD_EXTRACT" -maxdepth 4 -type d 2>/dev/null | head -n 80) >&2 || true

echo "[NebulaOS] Post-dpkg-deb: modules.dep locations (max 20):" >&2
find "$KMOD_EXTRACT" -type f -name modules.dep 2>/dev/null | head -n 20 >&2 || true

if [ -z "$(find "$KMOD_EXTRACT" -type f 2>/dev/null | head -n 1 || true)" ]; then
  echo "[NebulaOS] ERROR: KMOD_EXTRACT contains no files after dpkg-deb" >&2
  (ls -la "$KMOD_EXTRACT" 2>/dev/null || true) >&2
  exit 1
fi

# Verify modules metadata exists (hard fail with diagnostics)
if ! find "$KMOD_EXTRACT" -type f -name modules.dep 2>/dev/null | grep -q .; then
  echo "[NebulaOS] ERROR: modules.dep not found in KMOD_EXTRACT after dpkg-deb" >&2
  echo "[NebulaOS] KMOD_EXTRACT top-level preview:" >&2
  (find "$KMOD_EXTRACT" -maxdepth 3 -type f 2>/dev/null | head -n 100) >&2 || true
  exit 1
fi



# Immediate instrumentation after extraction (needed because failures were hard to diagnose)
# Print candidate locations for vmlinuz and modules.dep.
echo "[NebulaOS] Post-extract sanity:" >&2
echo "  KIMG_EXTRACT: $KIMG_EXTRACT" >&2
echo "  KMOD_EXTRACT: $KMOD_EXTRACT" >&2

# vmlinuz candidates
(echo "[NebulaOS] vmlinuz candidates:" >&2; find "$KIMG_EXTRACT" -type f -iname 'vmlinuz*' 2>/dev/null | head -n 50 >&2) || true
(echo "[NebulaOS] bzImage candidates:" >&2; find "$KIMG_EXTRACT" -type f -iname 'bzImage*' 2>/dev/null | head -n 50 >&2) || true
(echo "[NebulaOS] boot/* candidates:" >&2; find "$KIMG_EXTRACT" -maxdepth 6 -type f -path '*boot*' 2>/dev/null | head -n 50 >&2) || true

# modules.dep candidates
(echo "[NebulaOS] modules.dep candidates:" >&2; find "$KMOD_EXTRACT" -type f -name modules.dep 2>/dev/null | head -n 20 >&2) || true

echo "[NebulaOS] Extraction success. Trees:" >&2
ls -la "$KIMG_EXTRACT" | head -n 50 >&2 || true
ls -la "$KMOD_EXTRACT" | head -n 50 >&2 || true

# Locate vmlinuz and modules version
# Mainline Ubuntu linux-image .deb payloads often place vmlinuz under /boot/.
# We resolve vmlinuz deterministically to avoid filename/path edge-cases.
echo "[NebulaOS] Debug: locating vmlinuz under: $KIMG_EXTRACT" >&2
(ls -la "$KIMG_EXTRACT" 2>/dev/null || true) >&2

resolve_vmlinuz() {
  local root="$1"
  local candidates=()

  # Candidate discovery (best-first ordering)
  while IFS= read -r f; do candidates+=("$f"); done < <(find "$root" -type f -path '*/boot/vmlinuz-*' 2>/dev/null | sort)
  if [ ${#candidates[@]} -eq 0 ]; then
    while IFS= read -r f; do candidates+=("$f"); done < <(find "$root" -type f -path '*/boot/vmlinuz' 2>/dev/null | sort)
  fi
  if [ ${#candidates[@]} -eq 0 ]; then
    while IFS= read -r f; do candidates+=("$f"); done < <(find "$root" -type f -name 'vmlinuz-*' 2>/dev/null | sort)
  fi
  if [ ${#candidates[@]} -eq 0 ]; then
    while IFS= read -r f; do candidates+=("$f"); done < <(find "$root" -type f -name 'vmlinuz*' 2>/dev/null | sort)
  fi

  if [ ${#candidates[@]} -eq 0 ]; then
    echo ""
    return 0
  fi

  # Deterministic choice
  echo "${candidates[0]}"
}

VMLINUX_SRC="$(resolve_vmlinuz "$KIMG_EXTRACT")"

# Dump what we found for diagnostics
if [ -n "${VMLINUX_SRC:-}" ]; then
  echo "[NebulaOS] Resolved vmlinuz candidate: $VMLINUX_SRC" >&2
  (ls -la "$(dirname "$VMLINUX_SRC")" 2>/dev/null || true) >&2
fi

if [ -z "${VMLINUX_SRC:-}" ] || [ ! -f "${VMLINUX_SRC:-}" ]; then

  echo "[NebulaOS] ERROR: Could not find vmlinuz in kernel image deb contents." >&2

  echo "[NebulaOS] Verification: extract root:" >&2
  (ls -la "$KIMG_EXTRACT" 2>/dev/null || true) >&2
  echo "[NebulaOS] Verification: boot/ subtree (if any):" >&2
  (find "$KIMG_EXTRACT" -maxdepth 6 -type f -path '*boot*' 2>/dev/null | head -n 50) >&2 || true

  echo "[NebulaOS] Verification: vmlinuz-like files found:" >&2
  (find "$KIMG_EXTRACT" -type f -iname 'vmlinuz*' 2>/dev/null || true) >&2

  echo "[NebulaOS] Verification: bzImage-like files found:" >&2
  (find "$KIMG_EXTRACT" -type f -iname 'bzImage*' 2>/dev/null || true) >&2

  echo "[NebulaOS] Verification: total extracted files (cap 200):" >&2
  (find "$KIMG_EXTRACT" -type f 2>/dev/null | head -n 200) >&2 || true

  exit 1
fi



MOD_ROOT="$(find "$KMOD_EXTRACT/lib/modules" -maxdepth 2 -mindepth 2 -type d | head -n 1 || true)"
if [ -z "${MOD_ROOT:-}" ]; then
  # fallback: just pick the first /lib/modules/<ver>
  MOD_ROOT="$(find "$KMOD_EXTRACT/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
fi
if [ -z "${MOD_ROOT:-}" ]; then
  echo "[NebulaOS] ERROR: Could not locate /lib/modules/<ver> in modules deb contents." >&2
  exit 1
fi

KERNEL_VER="$(basename "$MOD_ROOT")"

# Extract firmware
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy outputs
# Ensure we copy into nebulaos/build/kernel/* (not only into work/).
cp -f "$VMLINUX_SRC" "$BUNDLE_OUT_VMLINUZ"

mkdir -p "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER"
cp -a "$MOD_ROOT/." "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER/"

# Also sanity-log immediately (helps catch path/layout bugs)
echo "[NebulaOS] Copied kernel vmlinuz to: $BUNDLE_OUT_VMLINUZ" >&2
echo "[NebulaOS] Copied modules to: $BUNDLE_OUT_MODULES_DIR/$KERNEL_VER" >&2


# Firmware: use linux-firmware snapshot tarball fallback
FW_DIR_OUT="$BUNDLE_OUT_FIRMWARE_DIR"
mkdir -p "$FW_DIR_OUT"

FW_TARBALL_PATH="$WORK_DIR/linux-firmware-snapshot.tar.gz"
FW_CACHE="$CACHE_DIR/linux-firmware-snapshot.tar.gz"
if [ ! -f "$FW_CACHE" ]; then
  echo "[NebulaOS] Downloading linux-firmware snapshot..." >&2
  fetch "$FIRMWARE_TARBALL_URL" "$FW_CACHE"
else
  echo "[NebulaOS] Using cached linux-firmware snapshot..." >&2
fi
cp -f "$FW_CACHE" "$FW_TARBALL_PATH"

FW_EXTRACT="$WORK_DIR/linux-firmware"
if [ "${DEBUG}" != "1" ]; then
  rm -rf "$FW_EXTRACT"
fi
mkdir -p "$FW_EXTRACT"

tar -xf "$FW_TARBALL_PATH" -C "$WORK_DIR"

# Common layout: $WORK_DIR/linux-firmware/lib/firmware
if [ -d "$WORK_DIR/linux-firmware/lib/firmware" ]; then
  cp -a "$WORK_DIR/linux-firmware/lib/firmware/." "$FW_DIR_OUT/"
else
  # fallback search
  FW_SRC_DIR="$(find "$WORK_DIR" -type d -path '*/lib/firmware' | head -n 1 || true)"
  if [ -z "${FW_SRC_DIR:-}" ]; then
    echo "[NebulaOS] ERROR: Could not locate firmware directory after extracting linux-firmware snapshot." >&2
    exit 1
  fi
  cp -a "$FW_SRC_DIR/." "$FW_DIR_OUT/"
fi

# Sanity + layout validation
if [ ! -f "$BUNDLE_OUT_VMLINUZ" ]; then
  echo "[NebulaOS] ERROR: vmlinuz output missing: $BUNDLE_OUT_VMLINUZ" >&2
  exit 1
fi

# Ensure vmlinuz is non-empty (common silent failure mode)
if [ ! -s "$BUNDLE_OUT_VMLINUZ" ]; then
  echo "[NebulaOS] ERROR: vmlinuz is empty: $BUNDLE_OUT_VMLINUZ" >&2
  exit 1
fi

if [ ! -d "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER" ]; then
  echo "[NebulaOS] ERROR: modules output missing: $BUNDLE_OUT_MODULES_DIR/$KERNEL_VER" >&2
  exit 1
fi

# Validate modules metadata exists
if [ ! -f "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER/modules.dep" ]; then
  echo "[NebulaOS] ERROR: modules.dep missing under $BUNDLE_OUT_MODULES_DIR/$KERNEL_VER" >&2
  exit 1
fi
if [ ! -f "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER/modules.alias" ] && [ ! -f "$BUNDLE_OUT_MODULES_DIR/$KERNEL_VER/modules.builtin.modinfo" ]; then
  echo "[NebulaOS] WARNING: expected modules metadata not found (modules.alias or builtin.modinfo)." >&2
fi

# Validate firmware placement: we expect /lib/firmware inside firmware dir (ISO layout copies firmware/ at /kernel/firmware)
# After copy we want: nebulaos/build/kernel/firmware/lib/firmware/*
if [ ! -d "$BUNDLE_OUT_FIRMWARE_DIR" ]; then
  echo "[NebulaOS] ERROR: firmware output missing: $BUNDLE_OUT_FIRMWARE_DIR" >&2
  exit 1
fi

FW_EXPECT_DIR="$BUNDLE_OUT_FIRMWARE_DIR/lib/firmware"
if [ ! -d "$FW_EXPECT_DIR" ]; then
  echo "[NebulaOS] WARNING: firmware lib/firmware directory missing at: $FW_EXPECT_DIR" >&2
  echo "[NebulaOS] WARNING: firmware top-level contents:" >&2
  (ls -la "$BUNDLE_OUT_FIRMWARE_DIR" 2>/dev/null || true) >&2
  echo "[NebulaOS] ERROR: firmware layout not compatible with expected /lib/firmware path." >&2
  exit 1
fi

# Validate kernel version consistency: vmlinuz should match the module version in filename or directory version if present.
# Best-effort: only warn if mismatch.
VMLINUX_BASENAME="$(basename "$VMLINUX_SRC")"
if echo "$VMLINUX_BASENAME" | grep -q "$KERNEL_VER"; then
  :
else
  echo "[NebulaOS] WARNING: kernel version consistency check: vmlinuz ($VMLINUX_BASENAME) does not contain modules version ($KERNEL_VER)." >&2
fi

echo "[NebulaOS] Kernel assets ready for ISO:" >&2
echo "  vmlinuz: $BUNDLE_OUT_VMLINUZ" >&2
echo "  modules: $BUNDLE_OUT_MODULES_DIR/$KERNEL_VER" >&2
echo "  firmware: $BUNDLE_OUT_FIRMWARE_DIR" >&2

#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper around run-qemu.sh
# Ensures serial stdio and uses OVMF.

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-qemu.sh" "$@"


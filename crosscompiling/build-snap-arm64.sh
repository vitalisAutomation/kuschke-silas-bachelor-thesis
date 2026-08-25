#!/usr/bin/env bash
# Compatibility entry point: build an ARM64 snap from ARM64 wheels on AMD64.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env SNAP_BUILD_MODE=wheels SNAP_BUILD_FOR=arm64 "$PROJECT_DIR/build-snap-wheels.sh"

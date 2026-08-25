#!/usr/bin/env bash
# Compatibility entry point: build a native AMD64 snap.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env SNAP_BUILD_MODE=native SNAP_BUILD_FOR=amd64 "$PROJECT_DIR/build-snap-native.sh"

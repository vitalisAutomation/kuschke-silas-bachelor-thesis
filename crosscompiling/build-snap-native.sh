#!/usr/bin/env bash
# Build a snap natively on the host architecture.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_FOR="${SNAP_BUILD_FOR:-$(uname -m)}"

case "$BUILD_FOR" in
	aarch64|arm64) BUILD_FOR=arm64 ;;
	x86_64|amd64) BUILD_FOR=amd64 ;;
	*) echo "Unsupported native build architecture: $BUILD_FOR" >&2; exit 1 ;;
esac

case "$(uname -m):$BUILD_FOR" in
	aarch64:arm64|arm64:arm64|x86_64:amd64|amd64:amd64) ;;
	*) echo "Native build target $BUILD_FOR does not match host $(uname -m)." >&2; exit 1 ;;
esac

if [[ -n "${WHEELHOUSE:-}" ]]; then
	echo "WHEELHOUSE is not used for a native build. Use build-snap.sh mode 1 for wheel builds." >&2
	exit 1
fi

cd "$PROJECT_DIR"
echo "== Building $BUILD_FOR snap natively =="
printf '%s\n' native > "$PROJECT_DIR/.snap-build-mode"
snapcraft pack --destructive-mode --build-for="$BUILD_FOR" --verbosity=verbose
echo "Done. Native $BUILD_FOR snap built."

#!/usr/bin/env bash
# Interactive build entry point for the NumPy cross-compiling sample.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Required command not found: $1" >&2
		exit 1
	fi
}

host_arch="$(uname -m)"
cat <<'EOF'
Choose the snap build mode:

1) Build an ARM64 snap on AMD64 using prebuilt ARM64 wheels
2) Build an ARM64 snap natively on an ARM64 machine
3) Build an AMD64 snap natively on an AMD64 machine

EOF

read -r -p "Select a mode [1-3]: " mode
case "$mode" in
	1)
		if [[ "$host_arch" != "x86_64" && "$host_arch" != "amd64" ]]; then
			echo "Mode 1 requires an AMD64 host; detected: $host_arch" >&2
			exit 1
		fi
		require_command python3
		require_command snapcraft
		exec env SNAP_BUILD_MODE=wheels SNAP_BUILD_FOR=arm64 "$PROJECT_DIR/build-snap-wheels.sh"
		;;
	2)
		if [[ "$host_arch" != "aarch64" && "$host_arch" != "arm64" ]]; then
			echo "Mode 2 requires an ARM64 host; detected: $host_arch" >&2
			exit 1
		fi
		require_command snapcraft
		exec env SNAP_BUILD_MODE=native SNAP_BUILD_FOR=arm64 "$PROJECT_DIR/build-snap-native.sh"
		;;
	3)
		if [[ "$host_arch" != "x86_64" && "$host_arch" != "amd64" ]]; then
			echo "Mode 3 requires an AMD64 host; detected: $host_arch" >&2
			exit 1
		fi
		require_command snapcraft
		exec env SNAP_BUILD_MODE=native SNAP_BUILD_FOR=amd64 "$PROJECT_DIR/build-snap-native.sh"
		;;
	*)
		echo "Invalid selection. Choose 1, 2 or 3." >&2
		exit 1
		;;
esac

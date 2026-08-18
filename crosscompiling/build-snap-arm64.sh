#!/usr/bin/env bash
# Builds the snap natively for arm64 inside an emulated arm64 LXD container.
# Prerequisite: ./setup-arm64-emulation.sh has been run once.
set -euo pipefail

CONTAINER="${CONTAINER:-snapbuild-arm64}"
IMAGE_SERIES="${IMAGE_SERIES:-24.04}"   # must match the 'base' in snapcraft.yaml (core24)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! grep -q "flags:.*F" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	echo "qemu-aarch64 binfmt is not registered correctly. Please run ./setup-arm64-emulation.sh." >&2
	exit 1
fi

if ! lxc info "$CONTAINER" >/dev/null 2>&1; then
	echo "== Resolving arm64 image =="
	FINGERPRINT="$(lxc image list "ubuntu:${IMAGE_SERIES}" architecture=aarch64 --format csv -c f | head -n1 | tr -d '"')"
	if [[ -z "$FINGERPRINT" ]]; then
		echo "No aarch64 image found for ubuntu:${IMAGE_SERIES}." >&2
		exit 1
	fi

	echo "== Launching arm64 container (emulated, this takes a while) =="
	# security.nesting: snapd and snapcraft run inside the container
	lxc launch "ubuntu:${FINGERPRINT}" "$CONTAINER" -c security.nesting=true
	lxc exec "$CONTAINER" -- cloud-init status --wait || true

	echo "== Installing toolchain inside the container =="
	lxc exec "$CONTAINER" -- bash -lc '
		set -euo pipefail
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get install -y snapd
		systemctl start snapd.socket
		snap wait system seed.loaded
		snap install snapcraft --classic
	'
fi

echo "== Copying sources into the container =="
# The existing parts/stage/prime dirs are kept so rebuilds stay incremental.
lxc exec "$CONTAINER" -- mkdir -p /root/project
tar --exclude=./parts --exclude=./stage --exclude=./prime --exclude=./.git \
	--exclude=./venv --exclude=./.venv --exclude=./qemu --exclude='./*.snap' \
	-cf - -C "$PROJECT_DIR" . | lxc exec "$CONTAINER" -- tar -xf - -C /root/project

echo "== Building the snap (native arm64, emulated) =="
# --destructive-mode: the container already is the arm64 build environment.
# Rebuilds are incremental by default; set CLEAN=1 for a full rebuild.
lxc exec "$CONTAINER" \
	--env CLEAN="${CLEAN:-0}" \
	--env SNAP_PIP_NO_BINARY="${SNAP_PIP_NO_BINARY:-:all:}" \
	-- bash -lc '
	set -euo pipefail
	cd /root/project
	export SNAPCRAFT_BUILD_ENVIRONMENT=host
	if [[ "$CLEAN" == "1" ]]; then
		snapcraft clean --destructive-mode
	fi
	snapcraft pack --destructive-mode --verbosity=verbose
'

echo "== Retrieving the result =="
SNAP_PATH="$(lxc exec "$CONTAINER" -- bash -lc 'ls -1 /root/project/*.snap | head -n1')"
lxc file pull "$CONTAINER${SNAP_PATH}" "$PROJECT_DIR/$(basename "$SNAP_PATH")"

echo "Done: $PROJECT_DIR/$(basename "$SNAP_PATH")"
echo "Stop the container with: lxc stop $CONTAINER   (delete: lxc delete -f $CONTAINER)"
#!/usr/bin/env bash
# Two-stage arm64 snap build:
#   1. Build all Python wheels from source inside an emulated arm64 LXD container.
#   2. Pack the snap natively on the amd64 host, consuming the prebuilt wheels.
# Prerequisite: ./setup-arm64-emulation.sh has been run once.
set -euo pipefail

CONTAINER="${CONTAINER:-wheelbuild-arm64}"
IMAGE_SERIES="${IMAGE_SERIES:-24.04}"   # must match the 'base' in snapcraft.yaml (core24)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELHOUSE="$PROJECT_DIR/wheelhouse"

if ! grep -q "flags:.*F" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	echo "qemu-aarch64 binfmt is not registered correctly. Please run ./setup-arm64-emulation.sh." >&2
	exit 1
fi

if ! lxc info "$CONTAINER" >/dev/null 2>&1; then
	echo "== Resolving arm64 image =="
	FINGERPRINT="$(lxc image list "ubuntu:${IMAGE_SERIES}" architecture=aarch64 type=virtual-machine --format csv -c f | head -n1 | tr -d '"')"
	if [[ -z "$FINGERPRINT" ]]; then
		echo "No aarch64 image found for ubuntu:${IMAGE_SERIES}." >&2
		exit 1
	fi

	echo "== Launching arm64 VM (emulated, this takes a while) =="
	lxc launch --vm "ubuntu:${FINGERPRINT}" "$CONTAINER"

	# The container does not inherit the host proxy, so apt and pip would fail.
	PROXY="${https_proxy:-${http_proxy:-}}"
	if [[ -n "$PROXY" ]]; then
		echo "Configuring the container for proxy $PROXY"
		for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
			lxc config set "$CONTAINER" "environment.$var" "$PROXY"
		done
		for var in no_proxy NO_PROXY; do
			lxc config set "$CONTAINER" "environment.$var" "${no_proxy:-localhost,127.0.0.1}"
		done
		lxc exec "$CONTAINER" -- bash -c "printf 'Acquire::http::Proxy \"%s\";\nAcquire::https::Proxy \"%s\";\n' '$PROXY' '$PROXY' > /etc/apt/apt.conf.d/99proxy"
		lxc restart "$CONTAINER"
	fi

	lxc exec "$CONTAINER" -- cloud-init status --wait || true

	echo "== Installing build dependencies inside the container =="
	lxc exec "$CONTAINER" -- bash -lc '
		set -euo pipefail
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		# libsystemd-dev would be needed here again for cysystemd.
		apt-get install -y \
			build-essential ccache gfortran pkg-config patchelf \
			python3-dev python3-pip python3-venv python3-setuptools python3-wheel \
			cython3 meson ninja-build \
			libopenblas-dev liblapack-dev
		python3 -m venv /root/buildenv
		/root/buildenv/bin/pip install --upgrade pip wheel
	'
fi

echo "== Building wheels from source (native arm64, emulated) =="
lxc file push "$PROJECT_DIR/requirements.txt" "$CONTAINER/root/requirements.txt"
# Deliberately not named PIP_NO_BINARY: that env var would also leak into pip's
# build isolation and force meson/ninja/cython to be compiled from source too.
lxc exec "$CONTAINER" \
	--env WHEEL_NO_BINARY="${SNAP_PIP_NO_BINARY:-:all:}" \
	-- bash -lc '
	set -euo pipefail
	export PATH="/usr/lib/ccache:$PATH"
	export CCACHE_DIR=/root/.ccache
	export CCACHE_MAXSIZE=5G
	export MAKEFLAGS="-j$(nproc)"
	mkdir -p /root/wheelhouse
	/root/buildenv/bin/pip wheel \
		--no-binary "$WHEEL_NO_BINARY" \
		--wheel-dir /root/wheelhouse \
		-r /root/requirements.txt
	ccache --show-stats || true
'

echo "== Fetching the wheelhouse =="
rm -rf "$WHEELHOUSE"
lxc file pull -r "$CONTAINER/root/wheelhouse" "$PROJECT_DIR"
ls -1 "$WHEELHOUSE"

echo "== Packing the snap (native on amd64) =="
cd "$PROJECT_DIR"
if [[ "${CLEAN:-0}" == "1" ]]; then
	snapcraft clean --use-lxd
fi
snapcraft pack --use-lxd --build-for=arm64 --verbosity=verbose

echo "Done. Stop the container with: lxc stop $CONTAINER   (delete: lxc delete -f $CONTAINER)"

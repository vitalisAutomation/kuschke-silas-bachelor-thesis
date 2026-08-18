#!/usr/bin/env bash
# Two-stage arm64 snap build:
#   1. Build all Python wheels from source inside an emulated arm64 rootfs.
#   2. Pack the snap natively on the amd64 host, consuming the prebuilt wheels.
# Prerequisite: qemu-aarch64 binfmt and debootstrap are available.
set -euo pipefail

IMAGE_SERIES="${IMAGE_SERIES:-24.04}"   # must match the 'base' in snapcraft.yaml (core24)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELHOUSE="$PROJECT_DIR/wheelhouse"
ROOTFS="${ROOTFS:-$PROJECT_DIR/.arm64-rootfs}"
ROOTFS_MIRROR="${ROOTFS_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"
PROXY="${https_proxy:-${http_proxy:-}}"

if ! grep -q "flags:.*F" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	echo "qemu-aarch64 binfmt is not registered correctly. Please run ./setup-arm64-emulation.sh." >&2
	exit 1
fi

if ! command -v debootstrap >/dev/null || ! command -v chroot >/dev/null; then
	echo "debootstrap and chroot are required. Install them with:" >&2
	echo "  sudo apt-get install debootstrap qemu-user-static binfmt-support" >&2
	exit 1
fi

if [[ ! -d "$ROOTFS/etc" ]]; then
	echo "== Creating persistent ARM64 rootfs =="
	sudo debootstrap --arch=arm64 --foreign "$IMAGE_SERIES" "$ROOTFS" "$ROOTFS_MIRROR"
	fi

if [[ ! -x "$ROOTFS/usr/bin/qemu-aarch64-static" ]]; then
	sudo install -m 0755 /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/qemu-aarch64-static"
fi

mount_rootfs() {
	sudo mount --rbind /dev "$ROOTFS/dev"
	sudo mount --make-rslave "$ROOTFS/dev"
	sudo mount -t proc proc "$ROOTFS/proc"
	sudo mount --rbind /sys "$ROOTFS/sys"
	sudo mount --make-rslave "$ROOTFS/sys"
	sudo mount --rbind /run "$ROOTFS/run"
	sudo mount --make-rslave "$ROOTFS/run"
}

unmount_rootfs() {
	sudo umount -l "$ROOTFS/run" 2>/dev/null || true
	sudo umount -l "$ROOTFS/sys" 2>/dev/null || true
	sudo umount -l "$ROOTFS/proc" 2>/dev/null || true
	sudo umount -l "$ROOTFS/dev" 2>/dev/null || true
}

trap unmount_rootfs EXIT INT TERM
mount_rootfs

if [[ ! -f "$ROOTFS/.debootstrap-complete" ]]; then
	sudo rm -f "$ROOTFS/etc/resolv.conf"
	sudo cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
	sudo chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
	sudo touch "$ROOTFS/.debootstrap-complete"
fi

if [[ -n "$PROXY" ]]; then
	sudo env "http_proxy=$PROXY" "https_proxy=$PROXY" chroot "$ROOTFS" /bin/bash -lc \
		'printf "Acquire::http::Proxy \"%s\";\nAcquire::https::Proxy \"%s\";\n" "$http_proxy" "$https_proxy" > /etc/apt/apt.conf.d/99proxy'
fi

echo "== Installing ARM64 build dependencies in rootfs =="
sudo env "http_proxy=$PROXY" "https_proxy=$PROXY" chroot "$ROOTFS" /bin/bash -lc '
	set -euo pipefail
	export DEBIAN_FRONTEND=noninteractive
	cat > /etc/apt/sources.list <<EOF
deb http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse
EOF
	apt-get update
	apt-get install -y \
		ca-certificates build-essential ccache gfortran pkg-config patchelf \
		python3-dev python3-pip python3-venv python3-setuptools python3-wheel \
		cython3 meson ninja-build libopenblas-dev liblapack-dev
	python3 -m venv /root/buildenv
	/root/buildenv/bin/pip install --upgrade pip wheel
'

echo "== Building ARM64 wheels from source through qemu-aarch64 =="
sudo cp "$PROJECT_DIR/requirements.txt" "$ROOTFS/root/requirements.txt"
sudo env "WHEEL_NO_BINARY=${SNAP_PIP_NO_BINARY:-:all:}" "http_proxy=$PROXY" "https_proxy=$PROXY" chroot "$ROOTFS" /bin/bash -lc '
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
sudo cp -a "$ROOTFS/root/wheelhouse" "$WHEELHOUSE"
sudo chown -R "$(id -u):$(id -g)" "$WHEELHOUSE"
ls -1 "$WHEELHOUSE"

echo "== Packing the snap (native on amd64) =="
cd "$PROJECT_DIR"
if [[ "${CLEAN:-0}" == "1" ]]; then
	snapcraft clean --use-lxd
fi
snapcraft pack --use-lxd --build-for=arm64 --verbosity=verbose

echo "Done. The ARM64 rootfs is kept at: $ROOTFS"

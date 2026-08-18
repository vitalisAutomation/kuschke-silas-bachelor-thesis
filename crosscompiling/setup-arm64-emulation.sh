#!/usr/bin/env bash
# One-time setup on the Ubuntu VM:
#   - Check KVM (optional, informational only)
#   - Register qemu-user-static + binfmt so arm64 binaries run transparently
#   - Install and initialize LXD plus snapcraft
set -euo pipefail

# This SDK VM has arm64 registered as a foreign architecture and APT may even
# default to it. Every package here must therefore be pinned to the host
# architecture explicitly - installing qemu-user-static:arm64 would register an
# ARM interpreter for x86-64 binaries and render the VM unusable.
HOST_ARCH="$(dpkg --print-architecture)"
APT_ARCH="$(apt-config dump APT::Architecture | cut -d '"' -f2)"
if [[ "$APT_ARCH" != "$HOST_ARCH" ]]; then
	echo "Note: APT defaults to '$APT_ARCH' while the host is '$HOST_ARCH'."
	echo "All packages below are pinned to :$HOST_ARCH."
fi

# KVM is NOT required for the arm64 build: the emulation runs through qemu-user
# in user space. A missing /dev/kvm therefore only produces a warning.
echo "== 1) KVM (optional) =="
# Not fatal: the host may have broken arm64 sources, which does not matter here.
# arm64 packages are only needed inside the emulated container.
sudo apt-get update || echo "apt-get update reported errors - continuing."
sudo apt-get install -y "cpu-checker:$HOST_ARCH"

if [[ -e /dev/kvm ]] && kvm-ok >/dev/null 2>&1; then
	sudo usermod -aG kvm "$USER"
	echo "KVM available - the Ubuntu VM itself runs accelerated."
else
	cat <<'EOF'
WARNING: KVM is not available inside this VM (no /dev/kvm).

This is uncritical for the arm64 snap build - the ARM emulation uses
qemu-user (binfmt) and does not need KVM. Only the overall VM speed is
affected.

Typical cause on a Windows host with active VBS/Hyper-V protection:
QEMU accelerates through WHPX, and WHPX cannot pass VT-x through to the
guest (no nested virtualization).

If nested KVM is required, run the VM under Hyper-V instead:
  Set-VMProcessor -VMName <VMName> -ExposeVirtualizationExtensions $true
  (VM powered off; disable dynamic memory)
EOF
fi

echo "Note: the arm64 emulation runs through qemu-user and is NOT accelerated by KVM."

echo
echo "== 2) ARM64 emulation via binfmt_misc =="
sudo apt-get install -y "qemu-user-static:$HOST_ARCH" "binfmt-support:$HOST_ARCH"
sudo systemctl restart systemd-binfmt || true

# Guard against the arm64 build of qemu-user-static, which would register an
# ARM interpreter for the host's own binaries.
if [[ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]]; then
	echo "ERROR: a qemu-x86_64 binfmt handler is registered on an x86-64 host." >&2
	echo "This breaks execution of native binaries. Remove qemu-user-static:arm64." >&2
	exit 1
fi

# The 'F' (fix-binary) flag is essential: the qemu interpreter is opened at
# registration time and therefore also works inside containers without qemu.
if ! grep -q "flags:.*F" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	echo "ERROR: qemu-aarch64 binfmt is missing or registered without the 'F' flag." >&2
	cat /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null || true
	exit 1
fi
echo "binfmt qemu-aarch64 registered (fix-binary)."

echo
echo "== 3) LXD and snapcraft =="
sudo snap install lxd || sudo snap refresh lxd
sudo snap install snapcraft --classic || sudo snap refresh snapcraft
# dir backend: no fixed pool size, so builds cannot run out of pool space.
sudo lxd init --auto --storage-backend=dir || echo "LXD is already initialized - keeping the existing configuration."
sudo usermod -aG lxd "$USER"

# Behind a corporate proxy the LXD daemon needs its own configuration,
# otherwise it cannot reach the image server.
PROXY="${https_proxy:-${http_proxy:-}}"
if [[ -n "$PROXY" ]]; then
	echo "Configuring LXD for proxy $PROXY"
	sudo lxc config set core.proxy_http "${http_proxy:-$PROXY}"
	sudo lxc config set core.proxy_https "$PROXY"
	sudo lxc config set core.proxy_ignore_hosts "${no_proxy:-localhost,127.0.0.1}"
fi

echo
echo "Done. Log in again (or run 'newgrp lxd'), then start: ./build-snap-arm64.sh"

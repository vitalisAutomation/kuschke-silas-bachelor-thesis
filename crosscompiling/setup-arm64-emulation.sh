#!/usr/bin/env bash
# One-time setup on the Ubuntu VM:
#   - Check KVM (optional, informational only)
#   - Register qemu-user-static + binfmt so arm64 binaries run transparently
#   - Install and initialize LXD plus snapcraft
set -euo pipefail

# KVM is NOT required for the arm64 build: the emulation runs through qemu-user
# in user space. A missing /dev/kvm therefore only produces a warning.
echo "== 1) KVM (optional) =="
sudo apt-get update
sudo apt-get install -y cpu-checker

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
sudo apt-get install -y qemu-user-static binfmt-support
sudo systemctl restart systemd-binfmt || true

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

echo
echo "Done. Log in again (or run 'newgrp lxd'), then start: ./build-snap-arm64.sh"

#!/usr/bin/env bash
# One-time setup for the amd64 VM used to download wheels and pack the snap.
set -euo pipefail

HOST_ARCH="$(dpkg --print-architecture)"
if [[ "$HOST_ARCH" != "amd64" ]]; then
	echo "This setup expects an amd64 Ubuntu VM, found: $HOST_ARCH" >&2
	exit 1
fi

echo "== Installing Snapcraft and LXD =="
sudo snap install lxd || sudo snap refresh lxd
sudo snap install snapcraft --classic || sudo snap refresh snapcraft
sudo lxd init --auto --storage-backend=dir || true
sudo usermod -aG lxd "$USER"

PROXY="${https_proxy:-${http_proxy:-}}"
if [[ -n "$PROXY" ]]; then
	echo "Configuring LXD for proxy $PROXY"
	sudo lxc config set core.proxy_http "${http_proxy:-$PROXY}"
	sudo lxc config set core.proxy_https "$PROXY"
	sudo lxc config set core.proxy_ignore_hosts "${no_proxy:-localhost,127.0.0.1}"
fi

echo
echo "Done. Log in again (or run 'newgrp lxd'), then start: ./build-snap.sh"
echo "Choose mode 1 to build the ARM64 snap from prebuilt ARM64 wheels."

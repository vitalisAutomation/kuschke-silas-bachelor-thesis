#!/usr/bin/env bash
set -euo pipefail

# Avoid accidental host/destructive-mode builds from inherited env vars.
unset CRAFT_BUILD_ENVIRONMENT
unset SNAPCRAFT_BUILD_ENVIRONMENT

# Destructive-mode runs often leave root-owned artifacts behind.
root_owned_file="$(find parts prime stage overlay -xdev -uid 0 -print -quit 2>/dev/null || true)"
if [[ -n "$root_owned_file" ]]; then
	echo "Root-owned build artifacts found: $root_owned_file"
	echo "Run: sudo chown -R $(id -u):$(id -g) parts prime stage overlay"
	exit 1
fi

snapcraft clean --use-lxd
snapcraft pack --use-lxd --build-for=arm64 --verbosity=verbose
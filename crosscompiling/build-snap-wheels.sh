#!/usr/bin/env bash
# Build an ARM64 snap on AMD64 from prebuilt ARM64 Python wheels.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELHOUSE="$PROJECT_DIR/wheelhouse"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
PROXY_ARGS=()

if [[ -n "${https_proxy:-${http_proxy:-}}" ]]; then
	PROXY_ARGS+=(--proxy "${https_proxy:-$http_proxy}")
fi

for command_name in python3 snapcraft; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Required command not found: $command_name" >&2
		exit 1
	fi
done

if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "amd64" ]]; then
	echo "The ARM64 wheel build requires an AMD64 host." >&2
	exit 1
fi

echo "== Downloading ARM64 wheels on AMD64 =="
rm -rf "$WHEELHOUSE"
mkdir -p "$WHEELHOUSE"
printf '%s\n' wheels > "$PROJECT_DIR/.snap-build-mode"
python3 -m pip download \
	--only-binary=:all: \
	--platform linux_aarch64 \
	--platform manylinux2014_aarch64 \
	--platform manylinux_2_17_aarch64 \
	--platform manylinux_2_28_aarch64 \
	--python-version "$PYTHON_VERSION" \
	--implementation cp \
	--abi "cp${PYTHON_VERSION//./}" \
	--dest "$WHEELHOUSE" \
	"${PROXY_ARGS[@]}" \
	-r "$PROJECT_DIR/requirements.txt"

if ! compgen -G "$WHEELHOUSE/*.whl" >/dev/null; then
	echo "No compatible ARM64 wheels were downloaded." >&2
	exit 1
fi

find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -printf '%f\n'
cd "$PROJECT_DIR"
snapcraft pack --use-lxd --build-for=arm64 --verbosity=verbose
echo "Done. ARM64 snap built on AMD64 from precompiled wheels."

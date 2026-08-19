#!/usr/bin/env bash
# Build the amd64 snap using prebuilt Python wheels only.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELHOUSE="$PROJECT_DIR/wheelhouse"
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

echo "== Downloading prebuilt AMD64 wheels =="
rm -rf "$WHEELHOUSE"
mkdir -p "$WHEELHOUSE"
python3 -m pip download \
	--only-binary=:all: \
	--dest "$WHEELHOUSE" \
	"${PROXY_ARGS[@]}" \
	-r "$PROJECT_DIR/requirements.txt"

if ! compgen -G "$WHEELHOUSE/*.whl" >/dev/null; then
	echo "No compatible AMD64 wheels were downloaded." >&2
	exit 1
fi

find "$WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -printf '%f\n'
cd "$PROJECT_DIR"
snapcraft pack --build-for=amd64 --verbosity=verbose
echo "Done. AMD64 snap built from precompiled wheels."

#!/bin/sh

# Put the snap's site-packages first so the bundled arm64 build is used.
export PYTHONPATH="$SNAP/lib/python3.12/site-packages:$SNAP:$PYTHONPATH"

exec python3 -u "$SNAP/app/main.py"

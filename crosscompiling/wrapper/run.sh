#!/bin/sh

# Put the snap's site-packages first so the bundled arm64 build is used.
export PYTHONPATH="$SNAP/lib/python3.12/site-packages:$SNAP:$PYTHONPATH"

# NumPy links against the staged OpenBLAS/LAPACK, which is not on the default loader path.
export LD_LIBRARY_PATH="$SNAP/usr/lib/$(uname -m)-linux-gnu:$SNAP/usr/lib:$LD_LIBRARY_PATH"

exec python3 -u "$SNAP/app/main.py"

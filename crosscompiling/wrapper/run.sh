#!/bin/sh

# 1. Wir setzen den PYTHONPATH absolut prioritär auf die site-packages Ihres Snaps!
#    Dadurch sucht Python zwingend zuerst nach der cross-kompilierten NumPy-Version.
export PYTHONPATH="$SNAP/lib/python3.12/site-packages:$SNAP:$PYTHONPATH"

# 2. Wir starten den Python-Interpreter der Steuerung und übergeben Ihr Skript
exec python3 -u "$SNAP/app/main.py"

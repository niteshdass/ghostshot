#!/bin/bash
# Rebuilds and (re)starts Ghostshot in the background.
set -euo pipefail
cd "$(dirname "$0")"

pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp' 2>/dev/null || true
./build.sh
open -a "$PWD/Ghostshot.app"
echo "Ghostshot is running. Double-tap Right Command to capture."

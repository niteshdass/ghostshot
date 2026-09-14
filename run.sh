#!/bin/bash
# Rebuilds and (re)starts Ghostshot in the background.
set -euo pipefail
cd "$(dirname "$0")"

pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp' 2>/dev/null || true
./build.sh
open -a "$PWD/Ghostshot.app"

# The launcher is a separate process under launchd; restart it so it picks up the
# rebuilt binary. Skipped when it was never installed.
if launchctl print "gui/$UID/com.ghostshot.launcher" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$UID/com.ghostshot.launcher"
    echo "launcher restarted."
fi

echo "Ghostshot is running. Double-tap Right Command to capture."

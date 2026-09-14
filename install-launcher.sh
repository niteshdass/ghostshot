#!/bin/bash
# Installs (or removes) the login agent that keeps GhostshotLauncher.app running.
# The launcher is what brings Ghostshot back after Right ⇧ ⇧ has quit it.
#
#   ./install-launcher.sh            install and start
#   ./install-launcher.sh --uninstall  stop and remove
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.ghostshot.launcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BINARY="$PWD/GhostshotLauncher.app/Contents/MacOS/GhostshotLauncher"

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed $PLIST"
    exit 0
fi

[ -x "$BINARY" ] || { echo "missing $BINARY — run ./build.sh first" >&2; exit 1; }

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLISTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ghostshot-launcher.log</string>
</dict>
</plist>
PLISTXML

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
echo "installed $PLIST"
echo "the launcher runs now and at every login; ./install-launcher.sh --uninstall undoes it."

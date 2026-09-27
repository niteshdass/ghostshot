#!/bin/bash
# Installs Ghostshot from the release zip. Run from Terminal, in the unzipped folder:
#
#   bash install.sh              install (or update) and start
#   bash install.sh --uninstall  stop and remove everything except your config
#
# Why a script and not drag-to-Applications: the apps are signed with a
# self-signed certificate, so Gatekeeper rejects them while they carry the
# download quarantine flag. Clearing that flag is the one step a drag cannot do.
set -euo pipefail
cd "$(dirname "$0")"

APPS="$HOME/Applications"
CONFIG_DIR="$HOME/Library/Application Support/Ghostshot"
LABEL="com.ghostshot.launcher"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

stop_everything() {
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp' 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
    stop_everything
    rm -f "$AGENT"
    rm -rf "$APPS/Ghostshot.app" "$APPS/GhostshotLauncher.app"
    echo "Ghostshot removed. Your keys are still in: $CONFIG_DIR"
    echo "Also switch Ghostshot off in System Settings > Privacy & Security."
    exit 0
fi

for app in Ghostshot.app GhostshotLauncher.app; do
    [ -d "$app" ] || { echo "missing $app — run this from the unzipped Ghostshot folder" >&2; exit 1; }
done

stop_everything

mkdir -p "$APPS"
for app in Ghostshot.app GhostshotLauncher.app; do
    rm -rf "${APPS:?}/$app"
    ditto "$app" "$APPS/$app"
    xattr -dr com.apple.quarantine "$APPS/$app" 2>/dev/null || true
done
echo "installed apps into $APPS"

mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cp config.example.json "$CONFIG_DIR/config.json"
    chmod 600 "$CONFIG_DIR/config.json"
    echo "created $CONFIG_DIR/config.json"
fi

# The launcher brings Ghostshot back on Right ⌘ ⌘ after Right ⇧ ⇧ quit it.
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<PLISTXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APPS/GhostshotLauncher.app/Contents/MacOS/GhostshotLauncher</string>
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
launchctl bootstrap "gui/$UID" "$AGENT"

open "$APPS/Ghostshot.app"

cat <<EOF

Ghostshot is running (no Dock icon — it lives in the background).

Next:
  1. Put your Gemini API key in the config (get one at https://aistudio.google.com/apikey):
       open -e "$CONFIG_DIR/config.json"
  2. System Settings > Privacy & Security, turn on:
       Accessibility                  -> Ghostshot, Ghostshot Launcher
       Screen & System Audio Recording -> Ghostshot
  3. Restart it after granting:  open ~/Applications/Ghostshot.app

Double-tap Right ⌘ to capture the screen and ask.
EOF

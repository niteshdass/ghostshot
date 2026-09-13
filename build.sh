#!/bin/bash
# Builds Ghostshot.app. TCC permissions are granted to a bundle, not to a bare
# binary, so the app must be bundled and signed even for local use.
set -euo pipefail
cd "$(dirname "$0")"

APP="Ghostshot.app"
CONTENTS="$APP/Contents"

swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/GhostshotApp "$CONTENTS/MacOS/GhostshotApp"
cp Resources/Info.plist "$CONTENTS/Info.plist"

# TCC keys its grants to the designated requirement. An ad-hoc signature has a
# requirement of nothing but the cdhash, so every code change looks like a new app
# and Accessibility / Screen Recording have to be granted again. A self-signed
# certificate gives "this bundle id, signed by this leaf", which survives rebuilds.
IDENTITY="Ghostshot Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier com.ghostshot.app --timestamp=none "$APP"
else
    echo "warning: no '$IDENTITY' identity; falling back to ad-hoc." >&2
    echo "         macOS will ask for permissions again after every rebuild." >&2
    echo "         run ./setup-signing.sh once to stop that." >&2
    codesign --force --sign - --identifier com.ghostshot.app --timestamp=none "$APP"
fi

echo "built $PWD/$APP"

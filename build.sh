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

# Ad-hoc signature. Enough for a stable local identity; not distributable.
codesign --force --sign - --timestamp=none "$APP"

echo "built $PWD/$APP"

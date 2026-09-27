#!/bin/bash
# Builds Ghostshot.app and GhostshotLauncher.app. TCC permissions are granted to a
# bundle, not to a bare binary, so both must be bundled and signed even for local use.
set -euo pipefail
cd "$(dirname "$0")"

# --universal builds arm64 and x86_64 separately and lipo's them together, for the
# release zip. Command Line Tools cannot do `--arch a --arch b` (that needs Xcode's
# build system), but they can cross-compile one triple at a time.
if [ "${1:-}" = "--universal" ]; then
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx14.0"
    done
    BIN=".build/universal"
    mkdir -p "$BIN"
    for exe in GhostshotApp GhostshotLauncher; do
        lipo -create -output "$BIN/$exe" \
            ".build/arm64-apple-macosx/release/$exe" \
            ".build/x86_64-apple-macosx/release/$exe"
    done
else
    swift build -c release
    BIN=".build/release"
fi

IDENTITY="Ghostshot Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    SIGN=("$IDENTITY")
else
    echo "warning: no '$IDENTITY' identity; falling back to ad-hoc." >&2
    echo "         macOS will ask for permissions again after every rebuild." >&2
    echo "         run ./setup-signing.sh once to stop that." >&2
    SIGN=("-")
fi

# TCC keys its grants to the designated requirement. An ad-hoc signature has a
# requirement of nothing but the cdhash, so every code change looks like a new app
# and Accessibility / Screen Recording have to be granted again. A self-signed
# certificate gives "this bundle id, signed by this leaf", which survives rebuilds.
bundle() {
    local app="$1" executable="$2" plist="$3" identifier="$4"
    local contents="$app/Contents"

    rm -rf "$app"
    mkdir -p "$contents/MacOS" "$contents/Resources"
    cp "$BIN/$executable" "$contents/MacOS/$executable"
    cp "Resources/$plist" "$contents/Info.plist"
    codesign --force --sign "${SIGN[0]}" --identifier "$identifier" --timestamp=none "$app"
    echo "built $PWD/$app"
}

bundle "Ghostshot.app" GhostshotApp Info.plist com.ghostshot.app
bundle "GhostshotLauncher.app" GhostshotLauncher LauncherInfo.plist com.ghostshot.launcher

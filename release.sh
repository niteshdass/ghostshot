#!/bin/bash
# Packages a universal build into dist/Ghostshot-<version>.zip for a GitHub release.
# The zip holds both apps, packaging/install.sh and packaging/README.txt. The version
# comes from CFBundleShortVersionString in Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)

./build.sh --universal

STAGE="dist/Ghostshot"
rm -rf dist
mkdir -p "$STAGE"
ditto Ghostshot.app "$STAGE/Ghostshot.app"
ditto GhostshotLauncher.app "$STAGE/GhostshotLauncher.app"
cp packaging/install.sh packaging/README.txt config.example.json "$STAGE/"
chmod +x "$STAGE/install.sh"

# ditto keeps the bundles intact; --norsrc leaves out the ._ AppleDouble files
# that extended attributes would otherwise add next to every file.
ZIP="dist/Ghostshot-$VERSION.zip"
ditto -c -k --norsrc --keepParent "$STAGE" "$ZIP"
shasum -a 256 "$ZIP"
echo "packaged $PWD/$ZIP"

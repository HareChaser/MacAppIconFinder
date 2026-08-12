#!/bin/bash
# Builds AppIconFinder.app into ./build. Run: ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

APP="build/AppIconFinder.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/AppIconFinder "$APP/Contents/MacOS/AppIconFinder"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: enough for a locally built app on Apple silicon.
codesign --force --sign - "$APP" >/dev/null

echo "Built $PWD/$APP"

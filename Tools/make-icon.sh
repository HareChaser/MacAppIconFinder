#!/bin/bash
# Regenerates Resources/AppIcon.icns from Tools/MakeAppIcon.swift.
# Only needed when the icon artwork changes; the .icns is checked in.
set -euo pipefail

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/AppIcon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift Tools/MakeAppIcon.swift "$MASTER"

for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$MASTER" --out "$ICONSET/icon_$name.png" >/dev/null
done

mkdir -p Resources
iconutil --convert icns "$ICONSET" --output Resources/AppIcon.icns
cp "$MASTER" Resources/AppIcon.png

echo "Wrote Resources/AppIcon.icns"

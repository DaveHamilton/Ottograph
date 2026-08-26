#!/bin/zsh
# Regenerates Assets/AppIcon.icns from Assets/icon.svg.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="dist/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift Scripts/render-icon.swift Assets/icon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
echo "Assets/AppIcon.icns updated"

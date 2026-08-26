#!/bin/zsh
# Regenerates Assets/AppIcon.icns.
# Prefers Assets/nbp-icon.png (edge-to-edge square artwork, squircle-masked
# here); falls back to the hand-drawn Assets/icon.svg.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="dist/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

SOURCE="Assets/icon.svg"
if [[ -f Assets/nbp-icon.png ]]; then
	swift Scripts/mask-icon.swift Assets/nbp-icon.png dist/icon-masked.png
	SOURCE="dist/icon-masked.png"
fi
echo "icon source: $SOURCE"

swift Scripts/render-icon.swift "$SOURCE" "$ICONSET"
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
echo "Assets/AppIcon.icns updated"

if [[ -f Assets/nbp-menubar.png ]]; then
	swift Scripts/make-menubar-icon.swift Assets/nbp-menubar.png Assets/menubar-template.png
fi

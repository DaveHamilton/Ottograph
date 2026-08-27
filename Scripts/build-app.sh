#!/bin/zsh
# Builds Ottograph.app from the SPM release build.
# Usage: Scripts/build-app.sh [--install] [--universal]
#   --install    also copy the bundle to ~/Applications
#   --universal  build a universal (arm64 + x86_64) binary — slower, and
#                what release.sh uses so Intel Macs can run it too
#
# Every build is signed with the best identity available (Developer ID
# first) under the hardened runtime, which notarization requires. Signing
# local and distribution builds the same way means they share one code
# signature identity, so macOS treats them as the same app and you grant
# Accessibility once rather than after every switch.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.11.0"
BUNDLE_ID="com.davehamilton.Ottograph"
APP="dist/Ottograph.app"

INSTALL=0
UNIVERSAL=0
for arg in "$@"; do
	case "$arg" in
		--install) INSTALL=1 ;;
		--universal) UNIVERSAL=1 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

if (( UNIVERSAL )); then
	swift build -c release --arch arm64 --arch x86_64
	BINARY=".build/apple/Products/Release/Ottograph"
else
	swift build -c release
	BINARY=".build/release/Ottograph"
fi
[[ -f "$BINARY" ]] || { echo "build product not found at $BINARY" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Ottograph"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -f Assets/menubar-template.png ]]; then
	cp Assets/menubar-template.png "$APP/Contents/Resources/menubar-template.png"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Ottograph</string>
	<key>CFBundleExecutable</key>
	<string>Ottograph</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Ottograph</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Ottograph reads your signature names from Mail so Settings can offer them as choices.</string>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Dave The Nerd, LLC</string>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Developer ID Application/{print $2; exit}')
if [[ -z "${IDENTITY}" ]]; then
	IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development/{print $2; exit}')
fi

if [[ -n "${IDENTITY}" ]]; then
	echo "Signing with: ${IDENTITY}"
	# --timestamp and --options runtime are both required by notarization.
	codesign --force --sign "${IDENTITY}" \
		--options runtime \
		--timestamp \
		--entitlements Ottograph.entitlements \
		"$APP"
else
	echo "No signing identity found — ad-hoc signing (not distributable; Accessibility grant resets each rebuild)"
	codesign --force --sign - --entitlements Ottograph.entitlements "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "Built ${APP} (v${VERSION}, $(lipo -archs "$APP/Contents/MacOS/Ottograph"))"

if (( INSTALL )); then
	mkdir -p ~/Applications
	rm -rf ~/Applications/Ottograph.app
	cp -R "$APP" ~/Applications/
	echo "Installed to ~/Applications/Ottograph.app"
fi

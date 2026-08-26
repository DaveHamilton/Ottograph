#!/bin/zsh
# Builds Ottograph.app from the SPM release build.
# Usage: Scripts/build-app.sh [--install]
#   --install  also copies the bundle to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.4.0"
BUNDLE_ID="com.davehamilton.Ottograph"
APP="dist/Ottograph.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Ottograph "$APP/Contents/MacOS/Ottograph"

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
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Dave Hamilton</string>
</dict>
</plist>
PLIST

# Prefer a real signing identity (stable designated requirement means the
# Accessibility grant survives rebuilds); fall back to ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Developer ID Application|Apple Development/{print $2; exit}')
if [[ -n "${IDENTITY}" ]]; then
	echo "Signing with: ${IDENTITY}"
	codesign --force --sign "${IDENTITY}" "$APP"
else
	echo "No signing identity found — ad-hoc signing (Accessibility grant will reset on each rebuild)"
	codesign --force --sign - "$APP"
fi

codesign --verify --strict "$APP"
echo "Built ${APP} (v${VERSION})"

if [[ "${1:-}" == "--install" ]]; then
	mkdir -p ~/Applications
	rm -rf ~/Applications/Ottograph.app
	cp -R "$APP" ~/Applications/
	echo "Installed to ~/Applications/Ottograph.app"
fi

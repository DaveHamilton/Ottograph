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
#
# Sparkle.framework is embedded here rather than by Xcode, so its nested
# helpers have to be signed by hand and inside-out — deepest first, the
# outer app last. Signing the app first and the helpers after would
# invalidate the outer signature.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.11.7"
BUNDLE_ID="com.davehamilton.Ottograph"
APP="dist/Ottograph.app"

# Sparkle's appcast feed and the public half of the EdDSA key pair that
# signs updates. The private half lives in the login keychain — it is the
# one unrecoverable secret in this project: lose it and existing installs
# can never be updated again, because they only trust this public key.
FEED_URL="https://davehamilton.github.io/Ottograph/appcast.xml"
SPARKLE_PUBLIC_KEY="zEpE4xCPRbhlmIjXWHigwTlGVh19XG4VV/XOQ9H36Q4="

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

SPARKLE_FW=$(find .build/artifacts/sparkle/Sparkle/Sparkle.xcframework \
	-type d -name Sparkle.framework -path "*macos*" 2>/dev/null | head -1)
[[ -n "$SPARKLE_FW" ]] || { echo "Sparkle artifact missing — run 'swift package resolve'" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
FW="$APP/Contents/Frameworks/Sparkle.framework"
# Headers and module maps are compile-time only, and Sparkle's docs say a
# non-sandboxed app never uses the XPC services. Dropping them keeps the
# DMG small and shrinks what has to be signed and notarized. The top-level
# entries are symlinks into Versions/Current, so they go too or they dangle
# and codesign rejects the bundle.
rm -rf "$FW/Versions/B/Headers" "$FW/Versions/B/PrivateHeaders" \
	"$FW/Versions/B/Modules" "$FW/Versions/B/XPCServices"
rm -f "$FW/Headers" "$FW/PrivateHeaders" "$FW/Modules" "$FW/XPCServices"

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
	<key>SUFeedURL</key>
	<string>${FEED_URL}</string>
	<key>SUPublicEDKey</key>
	<string>${SPARKLE_PUBLIC_KEY}</string>
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
else
	echo "No signing identity found — ad-hoc signing (not distributable; Accessibility grant resets each rebuild)"
	IDENTITY="-"
fi

# --timestamp and --options runtime are both required by notarization, but
# neither is possible ad-hoc, so they are only added for a real identity.
sign() {
	local target="$1" entitlements="${2:-}"
	local -a flags=(--force --sign "${IDENTITY}")
	# Plain `[[ x ]] && ...` would return 1 when false and set -e would kill
	# the build on the very first ad-hoc sign.
	if [[ "${IDENTITY}" != "-" ]]; then
		flags+=(--options runtime --timestamp)
	fi
	if [[ -n "$entitlements" ]]; then
		flags+=(--entitlements "$entitlements")
	fi
	codesign "${flags[@]}" "$target"
}

# Inside-out: every nested Mach-O before the thing that contains it. The
# versioned directory is what you sign for a framework, not the .framework
# wrapper — signing the wrapper leaves the real payload unsigned.
sign "$FW/Versions/B/Updater.app/Contents/MacOS/Updater"
sign "$FW/Versions/B/Updater.app"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B"
sign "$APP" Ottograph.entitlements

# --deep on *verify* (unlike on sign) is the right tool: it walks the
# nested code and catches a helper that was missed or resigned out of order.
codesign --verify --strict --deep --verbose=2 "$APP"
echo "Built ${APP} (v${VERSION}, $(lipo -archs "$APP/Contents/MacOS/Ottograph"))"

if (( INSTALL )); then
	mkdir -p ~/Applications
	rm -rf ~/Applications/Ottograph.app
	cp -R "$APP" ~/Applications/
	echo "Installed to ~/Applications/Ottograph.app"
fi

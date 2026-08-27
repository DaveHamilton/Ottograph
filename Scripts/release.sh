#!/bin/zsh
# Builds, signs, notarizes, and packages Ottograph for distribution.
#
#   Scripts/release.sh
#
# One-time setup — store notary credentials in the keychain under the
# profile name this script expects (either auth method works; the App Store
# Connect API key avoids involving your Apple ID password at all):
#
#   xcrun notarytool store-credentials "ottograph" \
#       --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \
#       --key-id XXXXXXXXXX --issuer <issuer-uuid>
#
#   ...or...
#
#   xcrun notarytool store-credentials "ottograph" \
#       --apple-id you@example.com --team-id DG7GMFWG86 --password <app-specific-password>
#
# Override the profile name with NOTARY_PROFILE if you use a different one.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-ottograph}"
APP="dist/Ottograph.app"
VERSION=$(awk -F'"' '/^VERSION=/{print $2}' Scripts/build-app.sh)
UPLOAD_ZIP="dist/Ottograph-notarize.zip"
DMG="dist/Ottograph-${VERSION}.dmg"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
	echo "No Developer ID Application certificate found — distribution builds need one." >&2
	exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
	echo "No notary credentials stored under profile '$PROFILE'." >&2
	echo "Run the 'notarytool store-credentials' command in this script's header first." >&2
	exit 1
fi

echo "==> Building universal, hardened, signed app"
Scripts/build-app.sh --universal

echo "==> Submitting to Apple's notary service (usually a few minutes)"
rm -f "$UPLOAD_ZIP"
ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"
xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$UPLOAD_ZIP"

echo "==> Stapling the ticket so it validates offline"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Verifying the way Gatekeeper will on someone else's Mac"
spctl --assess --verbose=4 --type install "$APP"

echo "==> Packaging $DMG"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Ottograph" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# The disk image is signed too, so the download itself is trusted.
IDENTITY=$(security find-identity -v -p codesigning \
	| awk -F'"' '/Developer ID Application/{print $2; exit}')
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo
echo "Done: $DMG (v${VERSION})"
echo "Ship that file. Recipients drag Ottograph to Applications and launch it —"
echo "no Gatekeeper warning. They still grant Accessibility on first run."

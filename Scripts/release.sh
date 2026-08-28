#!/bin/zsh
# Builds, signs, notarizes, and packages Ottograph for distribution.
#
#   Scripts/release.sh [--no-publish]
#
# Publishing is part of the release, not a postscript: the appcast points at
# the release asset, so a feed pushed before the release exists advertises a
# download that 404s for every user whose Mac checks in the meantime. This
# script therefore creates the GitHub release itself (after asking) and then
# checks that every enclosure URL in the feed actually resolves before you
# are told to push it. --no-publish stops after the DMG.
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

PUBLISH=1
for arg in "$@"; do
	case "$arg" in
		--no-publish) PUBLISH=0 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

PROFILE="${NOTARY_PROFILE:-ottograph}"
APP="dist/Ottograph.app"
FEED="docs/appcast.xml"
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

NOTES="Notes/Ottograph-${VERSION}.md"
if [[ ! -f "$NOTES" ]]; then
	echo "No release notes at $NOTES — Sparkle shows these in the update dialog." >&2
	exit 1
fi
if (( PUBLISH )) && ! command -v gh >/dev/null 2>&1; then
	echo "gh not installed, and publishing is part of this script. Install it, or re-run with --no-publish." >&2
	exit 1
fi
if (( PUBLISH )) && ! gh auth status >/dev/null 2>&1; then
	echo "gh is not logged in — run 'gh auth login', or re-run with --no-publish." >&2
	exit 1
fi
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
	echo "Tag v${VERSION} already exists — bump VERSION in Scripts/build-app.sh first." >&2
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

echo "==> Regenerating the Sparkle feed"
Scripts/appcast.sh

echo
echo "Done: $DMG (v${VERSION})"

if (( ! PUBLISH )); then
	echo
	echo "--no-publish: stopping here. Nothing has been released, and the feed in"
	echo "$FEED now references a v${VERSION} download that does not exist yet."
	echo "Do not push it until 'gh release create v${VERSION} $DMG' has run."
	exit 0
fi

echo
printf 'Publish release v%s to GitHub now? [y/N] ' "$VERSION"
read -r reply
if [[ "$reply" != [yY] ]]; then
	echo "Left unpublished. $FEED already references v${VERSION} — don't push it yet."
	exit 0
fi

echo "==> Creating the GitHub release"
gh release create "v${VERSION}" "$DMG" --title "Ottograph ${VERSION}" --notes-file "$NOTES"

# The invariant this whole ordering exists to protect, checked rather than
# described: every enclosure the feed advertises has to be downloadable.
echo "==> Verifying every download the feed advertises"
missing=0
for url in ${(f)"$(grep -o 'url="https://[^\"]*\.dmg"' "$FEED" | sed 's/^url="//; s/"$//')"}; do
	status=$(curl -sIL -o /dev/null -w '%{http_code}' "$url" || echo 000)
	if [[ "$status" == "200" ]]; then
		echo "  ok   $url"
	else
		echo "  $status  $url" >&2
		missing=1
	fi
done
if (( missing )); then
	echo >&2
	echo "Some enclosures don't resolve. DO NOT push $FEED — Sparkle would offer" >&2
	echo "those downloads to every install that checks in." >&2
	exit 1
fi

echo
echo "Release published and every enclosure resolves. Publish the feed:"
echo "  git add $FEED CHANGELOG.md docs/Ottograph-${VERSION}.md && git commit && git push"

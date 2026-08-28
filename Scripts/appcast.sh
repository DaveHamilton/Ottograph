#!/bin/zsh
# Regenerates docs/appcast.xml — the Sparkle update feed that GitHub Pages
# serves at https://davehamilton.github.io/Ottograph/appcast.xml — and the
# CHANGELOG that mirrors it.
#
#   Scripts/appcast.sh
#
# Every DMG ever released must stay in dist/appcast/ (gitignored, not in the
# repo): generate_appcast reads the archives to compute each entry's EdDSA
# signature, length, and minimum OS. A DMG that disappears from that folder
# disappears from the feed.
#
# Signing uses the private EdDSA key in the login keychain. That key is the
# one unrecoverable secret here — every installed copy trusts only its
# public half, so losing it means no existing install can ever be updated
# again. Export a backup with:
#
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
#
# ...and keep that file somewhere safe and out of this repo.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="https://github.com/DaveHamilton/Ottograph"
ARCHIVES="dist/appcast"
FEED="docs/appcast.xml"
NOTES_DIR="Notes"

GEN=$(find .build/artifacts/sparkle/Sparkle/bin -name generate_appcast 2>/dev/null | head -1)
[[ -n "$GEN" ]] || { echo "Sparkle tools missing — run 'swift package resolve'" >&2; exit 1; }

VERSION=$(awk -F'"' '/^VERSION=/{print $2}' Scripts/build-app.sh)

mkdir -p "$ARCHIVES"
# Only the version just built is copied in — never a blanket dist/*.dmg.
# Releases before 0.11.2 have no Sparkle and therefore no SUPublicEDKey,
# and generate_appcast happily emits an entry for them with no
# sparkle:edSignature at all: an unsigned item in a signed feed.
if [[ -f "dist/Ottograph-${VERSION}.dmg" ]]; then
	cp -f "dist/Ottograph-${VERSION}.dmg" "$ARCHIVES/"
fi
# Sparkle reads a .md/.html sidecar whose basename matches the archive and
# links to it from the feed, so Notes/ is the single source for the in-app
# release notes, the GitHub release body, and CHANGELOG.md.
for note in "$NOTES_DIR"/Ottograph-*.md(N); do
	cp -f "$note" "$ARCHIVES/"
	# The generated releaseNotesLink resolves against the feed's own
	# directory, so the notes have to ship next to it on Pages or the
	# update dialog shows a 404 instead of the notes.
	cp -f "$note" docs/
done

# generate_appcast reuses an appcast already sitting in the archives
# directory to carry existing entries forward, so seed it with the feed we
# publish — otherwise each run would rebuild history from scratch.
if [[ -f "$FEED" ]]; then
	cp -f "$FEED" "$ARCHIVES/appcast.xml"
fi

# --download-url-prefix applies one prefix to every entry, but each DMG
# lives under its own release tag, so generate with a placeholder and
# rewrite per version below. Safe to post-edit only because appcast
# signing is off; the enclosure URL isn't covered by the EdDSA signature.
# --maximum-deltas 0: no binary deltas. They save real bandwidth on big
# apps, but this one is ~3.5MB, and each delta is another asset that has
# to be uploaded to exactly the right release — a delta advertised in the
# feed but missing from the release is a 404 on the update path.
"$GEN" "$ARCHIVES" \
	-o "$FEED" \
	--link "$REPO_URL" \
	--full-release-notes-url "$REPO_URL/releases" \
	--maximum-deltas 0 \
	--download-url-prefix "https://ottograph.invalid/"

perl -pi -e 's{https://ottograph\.invalid/Ottograph-([0-9]+(?:\.[0-9]+)*)\.dmg}
             {'"$REPO_URL"'/releases/download/v$1/Ottograph-$1.dmg}gx' "$FEED"

if grep -q "ottograph.invalid" "$FEED"; then
	echo "Placeholder URLs survived the rewrite — check the DMG filenames." >&2
	exit 1
fi

# The changelog is generated, never hand-edited, so it can't drift from
# the notes Sparkle actually shows.
{
	echo "# Changelog"
	echo
	echo "Generated from \`Notes/\` by \`Scripts/appcast.sh\` — edit those files, not this one."
	for note in $(ls "$NOTES_DIR"/Ottograph-*.md 2>/dev/null | sort -Vr); do
		version="${note##*/Ottograph-}"; version="${version%.md}"
		echo
		echo "## v${version}"
		echo
		cat "$note"
	done
} > CHANGELOG.md

echo "Wrote $FEED and CHANGELOG.md"
grep -o 'sparkle:version="[^"]*"' "$FEED" | sort -Vu | sed 's/^/  /'

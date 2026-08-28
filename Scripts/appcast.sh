#!/bin/zsh
# Regenerates docs/appcast.xml — the Sparkle update feed that GitHub Pages
# serves at https://davehamilton.github.io/Ottograph/appcast.xml — and the
# CHANGELOG that mirrors it.
#
#   Scripts/appcast.sh
#
# generate_appcast reads the archives themselves to compute each entry's
# EdDSA signature, length, and minimum OS, so every DMG ever released has to
# be present in dist/appcast/ or its entry silently drops out of the feed.
# That folder is gitignored and lives on one machine — so rather than treat
# it as precious, this script rebuilds it from GitHub Releases, where every
# one of those DMGs already lives as a public asset.
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

# Pull back any released DMG that isn't in the archive folder, so a fresh
# clone (or a replacement Mac) can regenerate the whole feed. Releases
# before MIN_SPARKLE_VERSION shipped without Sparkle and therefore without
# an EdDSA signature; generate_appcast would happily emit an unsigned item
# into a signed feed, so they stay out. This encodes that rule instead of
# leaving it as a comment someone has to remember.
MIN_SPARKLE_VERSION="0.11.2"
older_than() {
	[[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
	for tag in $(gh release list --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null); do
		v="${tag#v}"
		# Plain `cond && continue` would return 1 when false, and set -e
		# would end the script on the first release that's new enough.
		if older_than "$v" "$MIN_SPARKLE_VERSION"; then continue; fi
		if [[ -f "$ARCHIVES/Ottograph-${v}.dmg" ]]; then continue; fi
		echo "Restoring Ottograph-${v}.dmg from release ${tag}"
		gh release download "$tag" --pattern "Ottograph-${v}.dmg" --dir "$ARCHIVES" || \
			echo "  (no matching asset on ${tag} — skipping)" >&2
	done
else
	echo "gh unavailable or not logged in — using only what's already in $ARCHIVES" >&2
fi

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
# Versions are elements (<sparkle:version>0.11.3</sparkle:version>), not
# attributes. Grepping for the attribute form matched nothing, so this
# summary silently printed an empty list every time — and an empty list
# looks identical to a feed that lost an entry, which is the exact failure
# this line exists to catch.
grep -oE '<sparkle:version>[^<]+' "$FEED" | sed 's|<sparkle:version>|  |' | sort -Vu

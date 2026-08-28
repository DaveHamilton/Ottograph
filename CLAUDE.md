# CLAUDE.md

Guidance for Claude (and any human) working in this repo. The README explains
what Ottograph is for users; this file is about *building* it — the commands,
the architecture, and the surprising things macOS and Mail do that we've
already paid for in debugging time.

## What this is

A menu bar app that gives Apple Mail per-alias signatures (plus auto-Cc and a
longer undo-send window). Apple killed Mail plugins in Sonoma and MailKit
extensions deliberately can't touch signatures, so Ottograph drives Mail's UI
through the Accessibility API instead.

## Commands

```bash
swift build                       # compile
swift test                        # the pure logic — parsing, config, Settings conversions
swift run                         # run unbundled (dev loop)
Scripts/build-app.sh --install    # build Ottograph.app, sign it, install to ~/Applications
Scripts/build-app.sh --universal  # arm64 + x86_64 (what releases use)
Scripts/make-icon.sh              # regenerate AppIcon.icns + menu bar template from Assets/
Scripts/release.sh                # universal build → sign → notarize → staple → signed DMG → appcast
Scripts/appcast.sh                # regenerate docs/appcast.xml + CHANGELOG.md on their own
swift Scripts/ax-probe.swift      # dump what Mail's compose windows expose to AX
```

`ax-probe.swift` is the tool for "what did Mail change?" after a macOS or
Mail update — it prints every compose-window popup and field with its
`AXIdentifier`, title, value, and label element, and with `--open-menus`
the Signature menu's items too. Run it from a terminal that has
Accessibility trust. It's also the standing answer to whether the engine
could stop matching on English titles: if identifiers are populated, they
are structural and locale-independent, and `discoverControls` should be
using them.

`Scripts/release.sh` needs a Developer ID Application certificate and notary
credentials stored in the keychain under the profile `ottograph`; the script's
header documents both auth options. It refuses to start if either is missing.

Publishing a release: write `Notes/Ottograph-X.Y.Z.md`, bump `VERSION` in
`Scripts/build-app.sh`, run `Scripts/release.sh`. The script asks before
creating the GitHub release, then checks that every enclosure URL in the
feed actually resolves — the appcast points at the release asset, so a feed
published first advertises a download that 404s, and that ordering is now
enforced rather than written down. It prints the final commit for you:

```bash
git add docs/appcast.xml CHANGELOG.md docs/Ottograph-X.Y.Z.md && git commit && git push
```

`--no-publish` stops after the DMG (and says plainly that the feed on disk
now references a release that doesn't exist yet).
**Never commit build artifacts** — `dist/` is gitignored; binaries belong on
GitHub Releases.

## Architecture

| File | Role |
| --- | --- |
| `main.swift` | Entry point. Single-instance `flock`, accessory activation policy. |
| `AppDelegate.swift` | Menu bar item, hot keys, notification wiring, invisible Edit menu. |
| `SignatureEngine.swift` | The engine: watches compose windows, applies signatures and auto-Cc. |
| `AX.swift` | Thin helpers over the AXUIElement C API. |
| `DelayedSend.swift` | "Send in N seconds" via Mail's own Send Later. |
| `HotKey.swift` | Carbon global hot keys. |
| `MenuBarIcon.swift` | Template glyph, normal and struck-through (paused). |
| `Notifier.swift` | UNUserNotificationCenter wrapper with repeat suppression. |
| `LoginItem.swift` | SMAppService registration. |
| `Config.swift` | JSON config model + store, hot-reloaded from disk. |
| `Log.swift` | Unified logging, so diagnostics outlive a Finder launch. |
| `Diagnostics.swift` | Builds a bug report: versions, AX trust, recent log. |
| `Tests/OttographTests` | The pure logic only — the engine needs a live Mail. |
| `docs/appcast.xml` | Sparkle update feed, served by GitHub Pages. Generated. |
| `Settings/` | SwiftUI settings window, its model, and Mail introspection. |

User config lives at `~/Library/Application Support/Ottograph/config.json` —
user data, never in the repo. Keep personal addresses out of this file and out
of any example you commit; use `example.com`.

## Hard-won constraints

Things that look like reasonable ideas but are known dead ends. Each cost real
debugging time; please don't re-derive them.

**Strip Mail's invisible marks *before* trimming punctuation, not after.**
`emailAddress(in:)` used to trim `<>,` first and clean the bidi marks
second. A mark sitting outside the bracket blocks the trim, so
`\u{200E}<dave@example.com>` parsed as `<dave@example.com` — an address that
matches no mapping, so the alias silently gets nothing and the log says only
"No mapping for". Found by a unit test, never by using the app: it needs an
address Mail decided to wrap, which most don't.

**Don't rewrite the engine in AppleScript.** Mail's `outgoing messages` only
lists *script-created* compose windows. Windows the user opens (⌘N, reply,
forward) are invisible to it. The `message signature` property genuinely works
— but only on windows AppleScript created, which is useless in practice. This
is why the engine uses Accessibility.

**Setting the Signature popup's `AXValue` silently does nothing.** The only
thing that works is pressing the popup to open its menu and pressing the menu
item. Verified directly against Mail.

**Don't verify a signature apply synchronously.** Mail updates the popup's
readable value on its own late schedule. Checking right after the press reports
a phantom failure, which triggers a retry, which re-opens the menu — the cause
of a persistent double blink. Trust a press on a menu item that was found;
re-check ~1.2s later with *freshly discovered* elements (the old reference goes
stale when Mail rebuilds the header).

**React ~300ms after a From change, not instantly.** Mail resets the Signature
popup itself shortly after a From change; applying sooner gets stomped.

**Don't prune per-window state the moment a window disappears.** A compose
window in a background tab vanishes from the AX window list entirely, so
immediate pruning makes every tab switch look like a brand-new window and
triggers a pointless re-apply. State is retained for 10 minutes instead.

**Cc is a token field.** Setting its value tokenizes visually, but recipients
only reach the message model when the field loses focus — so focus in, then
restore focus. Dedupe must strip invisible Unicode bidi marks that Mail wraps
around stored addresses, or every re-switch adds a duplicate.

**Use `Message > Send Later > Send Later…`, not the toolbar button.** The menu
is always present regardless of toolbar customization, pressing a menu item via
AX opens no visible menu, and the item's enabled state doubles as validation
(it's disabled unless a sendable compose window is key). The sheet's
`AXDateTimeArea` accepts an exact `Date` — no stepper clicking.

**An accessory app has no menu bar, so text fields have no cut/copy/paste.**
Nothing supplies the standard Edit-menu key equivalents. `AppDelegate`
installs an `NSApp.mainMenu` that stays invisible under this activation policy
but still dispatches those shortcuts.

**One instance only.** Two engines both react to every From change: doubled
menu blinks and retry crossfire. `main.swift` takes an exclusive lock.

**Multiple hot keys need distinct `EventHotKeyID`s.** Otherwise every
registered callback fires for any hot key press.

**Settings saves on commit, not per keystroke.** The engine reads the config
file live, so a half-typed signature name would be applied to a real compose
window and reported as a failure (and notified about). Text fields save on
Return, focus loss, or window close; toggles and pickers save immediately.
`save()` must **not** reload afterwards — `load()` sorts rows, which would make
them jump around under the cursor mid-edit.

**`print()` goes nowhere in a shipped build.** An app launched from Finder
has no stdout, so every log line the app produced in normal use was
discarded — which meant a user report could never be more than "it stopped
working". Logging goes through `Log` (unified logging) instead. Read it back
with:

```bash
log show --last 1h --predicate 'subsystem == "com.davehamilton.Ottograph"'
```

Messages are logged `.public` deliberately: the default redacts interpolated
strings, which would replace every alias and signature name with `<private>`
— exactly the words that make a report actionable. Nothing sensitive goes
in, and the engine never reads a compose body at all (`AXTextArea` is
pruned before it gets there). **Copy Diagnostics** in the menu bar menu
packages this up with the version, macOS, Mail, and Accessibility state.

## Distribution constraints

**Ottograph can never ship on the Mac App Store or TestFlight.** App Store apps
must be sandboxed, and the Accessibility write API the engine depends on does
not work inside the sandbox. Submitting unsandboxed is rejected automatically.
Direct distribution with Developer ID + notarization is the only path.

**Hardened runtime requires the `com.apple.security.automation.apple-events`
entitlement** (`Ottograph.entitlements`). It's needed for exactly one feature:
reading Mail's signature and address lists for the Settings pickers. Drop it
and that silently breaks while everything else keeps working.

**A Sparkle update keeps the Accessibility grant; a hand-swapped bundle
doesn't.** Verified on 0.11.2 → 0.11.3 across two Macs: the app updated and
came straight back to "Watching Mail". But replacing `Ottograph.app` by hand
(`rm -rf` + `cp -R`) *stales the TCC entry* even though the designated
requirement is byte-identical — the app relaunches saying the permission is
needed. This looks exactly like a signing regression and isn't one. It also
means a manual downgrade can't be used to test whether an update preserved
the grant: the downgrade itself breaks it, so the result is unattributable.
Test updates on a machine where the app was installed normally.

**`generate_appcast` emits binary deltas once two versions exist**, and a
delta's enclosure URL is not a `.dmg`, so `appcast.sh`'s per-tag URL rewrite
skipped it and left a placeholder domain in the feed. Deltas are off
(`--maximum-deltas 0`). Note this only appears on the *second* Sparkle
release — the first has nothing to diff against, so testing one release
proves nothing about the next.

**The Sparkle private key is unrecoverable.** It lives in the login keychain;
every installed copy trusts only its public half, baked into `Info.plist` by
`build-app.sh`. Lose it and no existing install can ever be updated again —
they'd all need a manual re-download. Back it up
(`generate_keys -x <file>`) and keep that file out of this repo.

**Sparkle's helpers must be signed inside-out, by hand.** Xcode would do this;
`build-app.sh` assembles the bundle itself, so it signs `Updater.app`'s
binary, then `Updater.app`, then `Autoupdate`, then the framework's *versioned
directory* (`Versions/B`, not the `.framework` wrapper), and only then the app.
Signing the app first invalidates it the moment a nested helper is re-signed.
`--deep` belongs on `codesign --verify`, never on `codesign --sign`.

**Sparkle's `XPCServices` are deleted at build time.** They exist only for
sandboxed apps, and Ottograph can't be sandboxed. Their top-level symlinks
have to go too, or they dangle and codesign rejects the bundle.

**`CHANGELOG.md` is generated — don't hand-edit it.** `Scripts/appcast.sh`
builds it from `Notes/Ottograph-*.md`, the same files Sparkle shows in its
update dialog, so the two can't drift.

**Every released DMG must be in `dist/appcast/` when the feed is generated.**
`generate_appcast` reads the archives themselves to compute each entry's
signature and minimum OS; a DMG missing from that folder vanishes from the
feed. The folder is gitignored, so it isn't in the repo — but it is no
longer precious: `appcast.sh` pulls any missing DMG back from GitHub
Releases, where all of them already live as public assets. Releases before
0.11.2 are deliberately excluded, since they predate Sparkle and would be
added to a signed feed unsigned.

**Release builds must be universal.** Apple Silicon-only builds leave Intel
users with an app that won't launch.

**Changing the signing identity resets the user's Accessibility grant**, since
TCC keys off the code signature. Local and release builds are therefore signed
the same way (Developer ID + hardened runtime) so they count as the same app.

## Verifying changes against live Mail

Unit tests can't cover the *engine*; the real verification is driving Mail
and reading back what happened. They do cover everything that isn't a
conversation with Mail — `swift test` checks the From-popup parsing, the
config normalising and clamping, and the Settings ↔ config conversions,
where the three signature states (a name, `"None"`, and blank) cross two
representations in both directions and a regression is completely silent.
That suite found the bidi-mark bug above on its first run. Write a small Swift script that uses the AX API (or
AppleScript, for reading Mail's model), run it from a process that has
Accessibility trust, and assert on actual state — the popup's value, the
message's `cc recipients`, the config file on disk.

Guidelines that keep this honest:

- **Prove the mechanism, not the log line.** A successful log can hide a retry
  that already happened. Check the state the user would see.
- **Clean up after tests**: close test compose windows, delete anything left in
  the Send Later mailbox before it actually sends, restore the clipboard, and
  never leave a second instance running.
- **A locked Mac renders nothing.** macOS won't create or lay out windows while
  the screen is locked, so AX reports empty windows or none at all — which
  looks exactly like a catastrophic regression. Take a screenshot before
  concluding anything.
- Test against real user-opened windows (⌘N, reply, forward), not just
  script-created ones. They behave differently — that difference is the whole
  reason for the Accessibility design.

## Conventions

- Swift 6 language mode, enforced (`swiftLanguageMode(.v6)` in
  `Package.swift`) rather than merely intended. `AppDelegate`, the settings
  types, and `SignatureEngine` are all `@MainActor`; `main.swift` wraps
  launch in `MainActor.assumeIsolated`. The engine's `assumeIsolated` calls
  assert something already true — the poll timer, the AXObserver's run loop
  source, and AppDelegate all run on the main run loop, and its per-window
  state has no locking of its own.
- One type per file, grouped by feature (`Settings/`).
- Comments explain *why*, not what — especially around the workarounds above,
  since every one of them looks like a bug until you know the reason.
- English UI labels are matched by name ("From", "Signature", "Send Later…",
  "Schedule"). Localization would need a different approach.
- Commit messages: what changed and *why*, with the reasoning behind non-obvious
  fixes preserved.

## Repo and release conventions

This repo is **public** and MIT licensed. Keep it that way: no real email
addresses, API keys, issuer IDs, or personal config in commits — use
`example.com` in documentation and examples. The user's own config lives at
`~/Library/Application Support/Ottograph/config.json` and is never committed.

Releases go out as GitHub Release assets, never as commits:

```bash
# bump VERSION in Scripts/build-app.sh, then
Scripts/release.sh
gh release create vX.Y.Z dist/Ottograph-X.Y.Z.dmg --notes-file <notes>
```

**The default config must stay empty** (`Config.defaultConfig`). It used to
seed example.com placeholder rows, which meant a first-time user opened
Settings to three fake mappings that looked like a bug. Settings shows a
`ContentUnavailableView` empty state instead — don't reintroduce sample data
as a substitute for that.

**Verify user-visible changes on a fresh install, not just your own.** Move
`config.json` aside, relaunch, look at what a newcomer actually sees, then
restore it — and diff the restored file against a backup to prove nothing
drifted.

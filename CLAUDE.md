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
swift run                         # run unbundled (dev loop)
Scripts/build-app.sh --install    # build Ottograph.app, sign it, install to ~/Applications
Scripts/build-app.sh --universal  # arm64 + x86_64 (what releases use)
Scripts/make-icon.sh              # regenerate AppIcon.icns + menu bar template from Assets/
Scripts/release.sh                # universal build → sign → notarize → staple → signed DMG
```

`Scripts/release.sh` needs a Developer ID Application certificate and notary
credentials stored in the keychain under the profile `ottograph`; the script's
header documents both auth options. It refuses to start if either is missing.

Publishing a release: bump `VERSION` in `Scripts/build-app.sh`, run
`Scripts/release.sh`, then `gh release create vX.Y.Z dist/Ottograph-X.Y.Z.dmg`.
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
| `Settings/` | SwiftUI settings window, its model, and Mail introspection. |

User config lives at `~/Library/Application Support/Ottograph/config.json` —
user data, never in the repo. Keep personal addresses out of this file and out
of any example you commit; use `example.com`.

## Hard-won constraints

Things that look like reasonable ideas but are known dead ends. Each cost real
debugging time; please don't re-derive them.

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

## Distribution constraints

**Ottograph can never ship on the Mac App Store or TestFlight.** App Store apps
must be sandboxed, and the Accessibility write API the engine depends on does
not work inside the sandbox. Submitting unsandboxed is rejected automatically.
Direct distribution with Developer ID + notarization is the only path.

**Hardened runtime requires the `com.apple.security.automation.apple-events`
entitlement** (`Ottograph.entitlements`). It's needed for exactly one feature:
reading Mail's signature and address lists for the Settings pickers. Drop it
and that silently breaks while everything else keeps working.

**Release builds must be universal.** Apple Silicon-only builds leave Intel
users with an app that won't launch.

**Changing the signing identity resets the user's Accessibility grant**, since
TCC keys off the code signature. Local and release builds are therefore signed
the same way (Developer ID + hardened runtime) so they count as the same app.

## Verifying changes against live Mail

Unit tests can't cover this app; the real verification is driving Mail and
reading back what happened. Write a small Swift script that uses the AX API (or
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

- Swift 6 concurrency: `AppDelegate` and the settings types are `@MainActor`;
  `main.swift` wraps launch in `MainActor.assumeIsolated`.
- One type per file, grouped by feature (`Settings/`).
- Comments explain *why*, not what — especially around the workarounds above,
  since every one of them looks like a bug until you know the reason.
- English UI labels are matched by name ("From", "Signature", "Send Later…",
  "Schedule"). Localization would need a different approach.
- Commit messages: what changed and *why*, with the reasoning behind non-obvious
  fixes preserved.

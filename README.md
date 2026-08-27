# Ottograph ✒️

<img src="Assets/otto.png" width="320" alt="Otto, a small friendly robot, signing a flowing cursive O with a fountain pen" align="right">

**The right signature, automatically.**

Ottograph is a macOS menu bar app that gives Apple Mail what it has never had
natively: a different signature for each **alias** address. Pick an alias in a
compose window's From popup and Ottograph swaps in the signature you mapped to
it — instantly, exactly as if you'd chosen it from the Signature popup yourself.

## The name

*Otto* is the robot in the Automator icon — the mascot of the Sal Soghoian era
of Mac automation. An *autograph* is a signature. Ottograph is Otto, writing
your autograph. It's also a loose homage to SigPro, which did this job back when
Mail still allowed plugins.

The app icon and mascot art were generated with Nano Banana Pro
(`Assets/nbp-icon.png`, `Assets/otto.png`); `Scripts/make-icon.sh` masks the
icon artwork into the macOS squircle and packs the `.icns`.

## How it works

Apple killed Mail plugins (macOS Sonoma) and the modern MailKit extension API
deliberately can't touch signatures or the compose body. Mail's AppleScript
dictionary looks promising (`outgoing message` has a readable `sender` and a
writable `message signature`) — but there's a trap we hit in testing: **modern
Mail only lists script-created messages in `outgoing messages`. Compose
windows the user opens (⌘N, reply, forward) are invisible to AppleScript.**

So Ottograph uses the Accessibility API instead. Every compose window exposes
its **From popup** (readable) and **Signature popup** (settable) in the
accessibility tree. Ottograph is event-driven: an AXObserver watches Mail for
new windows and for From-popup changes, so when you pick an alias — or a
compose window first appears — the mapped signature is selected in that
window's Signature popup immediately, exactly like a human would. A polling
scan (default: every `pollSeconds`, only while Mail is running) remains as a
safety net for anything events miss, such as sleep/wake or a Mail relaunch.
Each compose window is tracked independently, and Ottograph only acts on a
*change* of sender, so if you manually pick a different signature afterward,
it leaves you alone.

Bonus of this approach: no Apple events at all, so the only permission needed
is Accessibility.

## Running it

The real thing — builds `Ottograph.app`, signs it (stable Accessibility
identity), and installs it to `~/Applications`:

```
Scripts/build-app.sh --install
open ~/Applications/Ottograph.app
```

For quick development iteration, `swift run` still works (grant Accessibility
to your terminal app in that case, since CLI tools inherit it from their
parent). The bundled app adds a "Start at Login" menu item; the bare
executable can't offer one (SMAppService requires a bundle).

First run:

1. macOS will ask for the Accessibility permission
   (System Settings → Privacy & Security → Accessibility). Approve it once —
   the signed bundle's identity is stable across rebuilds.
2. Open **Settings…** from the menu bar icon and map your aliases. With Mail
   running, both the address and signature columns come pre-filled with
   pickers of your real addresses and signature names — reading those uses
   Apple events, so macOS asks once for Automation permission (decline and
   the fields simply stay free-text). Addresses already mapped are filtered
   out of other rows' pickers.

Settings has no Save button: toggles and picker choices apply on the spot,
and text fields commit when you press Return, move focus, or close the
window (never mid-keystroke, so a half-typed signature name is never written
and can't be reported as a failure). It writes
`~/Library/Application Support/Ottograph/config.json`, which you can also
edit by hand — the engine picks up changes either way:

```json
{
  "pollSeconds": 1.0,
  "signatures": {
    "dave@example.com": "Personal",
    "dave@podcast-example.com": "Show Signature"
  },
  "autoCc": {
    "feedback@example.com": "dave@example.com"
  }
}
```

Keys are From addresses (case-insensitive); values are signature **names
exactly as they appear** in Mail → Settings → Signatures. An empty string
value selects "None" for that alias. Config changes are picked up
automatically — no restart needed.

`autoCc` (optional) maps a From alias to an address that gets added to the
Cc field whenever that alias is selected — e.g. auto-cc yourself on mail
sent from a shared or feedback address. It de-duplicates (switching away
and back won't double up), respects a Cc field you're actively editing,
and an alias can have a signature mapping, an autoCc, or both.

## Send in 2 Minutes (⌃⌥⌘S)

Mail's Undo Send caps out at 30 seconds, the limit isn't stored in any
`defaults` domain, and the real setting lives in Mail's TCC-protected,
cloud-synced store — there is no terminal override. So Ottograph provides a
longer regret window a different way: press **⌃⌥⌘S** in a compose window
(or use the menu bar item) and Ottograph drives Mail's own **Send Later**
flow, scheduling the message for now + `sendDelaySeconds` (default 120;
set it in the config). Until then the message sits in Mail's Send Later
mailbox where you can open, edit, or delete it — a strictly better undo
than Undo Send, and the schedule survives quitting Mail.

Driven through `Message > Send Later > Send Later…`, so it doesn't depend on
the compose toolbar's buttons — but like everything else here it matches
English UI labels.

Optionally, **Take over Mail's Send shortcut (⇧⌘D)** (Settings, off by
default) routes Mail's own Send shortcut to delayed send while Mail is
frontmost, so muscle memory gets the regret window too. The hot key is only
registered while Mail is frontmost, so no other app loses ⇧⌘D. Send in the
toolbar and the Message menu still send immediately.

## Feedback and status

The menu bar glyph is struck through while Ottograph is paused, so a paused
app doesn't look like a working one. Ottograph notifies you when something
actually fails (a mapped signature isn't available for that account, a
delayed send couldn't be set up); routine work stays silent. A second,
off-by-default option notifies you when a message is scheduled rather than
sent — Mail's own Send Later sheet is usually feedback enough. Both are in
Settings.

Each mapped signature must appear in the compose window's Signature popup for
the selected account — i.e., it must be attached to the account that owns the
alias in Mail → Settings → Signatures.

## Prototype

`Prototype/ottograph-poc.applescript` is the original single-shot AppleScript
proof of concept. It still works — but only on *script-created* compose
windows, which is exactly the limitation that forced the Accessibility
rewrite. Kept for archaeology.

## Distribution

Ottograph can never ship on the Mac App Store: App Store apps must be
sandboxed, and the Accessibility write API it depends on (setting Mail's
Signature popup and Cc field) does not work inside the sandbox at all. That
also rules out TestFlight, which distributes through App Store Connect. Like
every other app in this category, it ships directly.

`Scripts/release.sh` does the whole thing: universal build, Developer ID
signing under the hardened runtime, notarization, stapling, a Gatekeeper
check, and a signed + notarized DMG. One-time setup is storing notary
credentials in the keychain — see the comment block at the top of that
script for both auth options.

Every build (local ones too) is signed with the same Developer ID identity
under the hardened runtime, so macOS treats development and release builds
as the same app and the Accessibility grant carries across them.

## Project status / roadmap

- [x] v0.1 — menu bar app, JSON config, AppleScript engine
      (worked, but only for script-created compose windows)
- [x] v0.2 — Accessibility engine: real ⌘N/reply/forward windows,
      every compose window tracked independently
- [x] v0.3 — event-driven engine (AXObserver): instant reaction to From
      changes and new windows, polling demoted to a fallback safety net
- [x] v0.4 — app bundle (`Scripts/build-app.sh`), signed, menu-bar-only
      (`LSUIElement`), Start at Login via SMAppService
- [x] v0.5 — per-alias auto-Cc: choosing a mapped From alias also adds a
      configured address to the Cc field (deduped, focus-preserving)
- [x] v0.6 — "Send in 2 Minutes" (⌃⌥⌘S): schedules the focused compose
      window via Mail's native Send Later, for a regret window beyond
      Undo Send's 30-second cap
- [x] v0.7 — Settings window (menu bar → Settings…): edit alias mappings,
      auto-Cc, and timing in a UI
- [x] v0.9.1 — Settings polish: addresses and signature names load from Mail
      automatically when the window opens, both columns are pickable,
      already-mapped addresses are filtered out, and the standard Edit-menu
      shortcuts (cut/copy/paste/undo) work in the fields
- [x] v0.10 — UX pass: Start at Login moved into Settings, notifications for
      failures (and optionally for scheduled sends), and a struck-through
      menu bar glyph while paused
- [x] v0.11 — Settings apply immediately; the Save and Revert buttons are
      gone, so every control behaves the same way
- [ ] App icon
- [ ] Notarized distribution build (Developer ID + hardened runtime)
- [ ] Localization-proof popup detection (currently matches English
      "From"/"Signature" labels with value-based fallbacks)

## Limitations

- **Tabbed compose windows** (Merge All Windows / "prefer tabs") work with
  caveats: background tabs vanish from the accessibility tree, so per-window
  state is retained for 10 minutes to avoid re-applying on every tab switch.
  However, macOS's AX exposure of tabbed windows is flaky — popup discovery
  intermittently fails, and a From change made immediately around a tab
  switch can occasionally be missed (the 1s fallback scan usually catches
  it). Separate compose windows remain the well-tested path.

- Requires the Accessibility permission (see First run above).
- Applying a signature briefly opens the Signature popup menu on screen —
  it's the same UI action a human would take, just fast.
- Popup identification assumes English labels ("From", "Signature",
  "Priority") with heuristic fallbacks.

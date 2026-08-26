# Ottograph ✒️

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

```
swift run
```

First run:

1. macOS will ask for the Accessibility permission
   (System Settings → Privacy & Security → Accessibility). When running via
   `swift run`, grant it to your **terminal app** — CLI tools inherit it from
   their parent. A future app-bundle build will request it as itself.
2. A default config is created at
   `~/Library/Application Support/Ottograph/config.json`. Edit it
   (menu bar icon → Open Config File) to map your aliases:

```json
{
  "pollSeconds": 1.0,
  "signatures": {
    "dave@example.com": "Personal",
    "dave@podcast-example.com": "Show Signature"
  }
}
```

Keys are From addresses (case-insensitive); values are signature **names
exactly as they appear** in Mail → Settings → Signatures. An empty string
value selects "None" for that alias. Config changes are picked up
automatically — no restart needed.

Each mapped signature must appear in the compose window's Signature popup for
the selected account — i.e., it must be attached to the account that owns the
alias in Mail → Settings → Signatures.

## Prototype

`Prototype/ottograph-poc.applescript` is the original single-shot AppleScript
proof of concept. It still works — but only on *script-created* compose
windows, which is exactly the limitation that forced the Accessibility
rewrite. Kept for archaeology.

## Project status / roadmap

- [x] v0.1 — menu bar app, JSON config, AppleScript engine
      (worked, but only for script-created compose windows)
- [x] v0.2 — Accessibility engine: real ⌘N/reply/forward windows,
      every compose window tracked independently
- [x] v0.3 — event-driven engine (AXObserver): instant reaction to From
      changes and new windows, polling demoted to a fallback safety net
- [ ] Settings window (edit mappings in UI, read signature list from Mail)
- [ ] Launch at login
- [ ] App bundle + notarization for distribution
- [ ] Localization-proof popup detection (currently matches English
      "From"/"Signature" labels with value-based fallbacks)

## Limitations

- Requires the Accessibility permission (see First run above).
- Applying a signature briefly opens the Signature popup menu on screen —
  it's the same UI action a human would take, just fast.
- Popup identification assumes English labels ("From", "Signature",
  "Priority") with heuristic fallbacks.

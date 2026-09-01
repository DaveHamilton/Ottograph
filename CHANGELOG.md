# Changelog

Generated from `Notes/` by `Scripts/appcast.sh` — edit those files, not this one.

## v0.11.6

One fix, for anyone using auto-Cc with an address that's also in Contacts.

- **Auto-Cc no longer mangles the address it just added.** If the Cc address was in your Contacts, the recipient appeared correctly for a moment — *Otto Graph <otto@example.com>* — and was then replaced by a single mangled recipient, *"Otto Graph , otto@example.com"*. Mail reports a recipient differently once it has matched the address against Contacts, and Ottograph was reading that as a different address, deciding its Cc was missing, and adding it a second time — which is what broke the recipient. It now recognises the address either way, so in the normal case it leaves a Cc it already added completely alone.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

## v0.11.5

One fix, for anyone using the ⇧⌘D takeover.

- **⇧⌘D outside a compose window does what it always did — Send Again.** Mail's ⇧⌘D is two commands, not one: Send in a compose window, and Message > Send Again in the viewer when a sent message is selected. Taking the shortcut over claimed both, so Send Again silently stopped working whenever the takeover was on — with no other shortcut to fall back on, because Mail doesn't offer one. Ottograph now asks Mail which command applies before acting: in a compose window you get the delayed send, everywhere else the keystroke goes through to Send Again.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

## v0.11.4

A reliability release — and the first one that can tell you what went wrong.

- **Copy Diagnostics**, in the menu bar menu. It puts the version, your macOS and Mail versions, whether the Accessibility grant is still in place, and the last half hour of Ottograph's own log on the clipboard. If something looks off, that's the whole bug report, in one click.
- **Fixed: some aliases silently got no signature.** Mail wraps certain addresses in invisible formatting characters, and Ottograph was reading those as part of the address — so the alias matched none of your mappings and nothing was applied. If one alias has never worked while the others always did, this was probably why.
- **A signature name Mail doesn't have is now flagged in Settings**, right next to the row it's in. Previously a typo stayed invisible until that alias was next used, and then arrived as a failure notification long after the mistake — with the list of real names sitting in the picker beside it the whole time.
- **A stalled Mail no longer takes Ottograph with it.** Ottograph now waits a bounded time for Mail to answer, so a beachballing Mail can't freeze the menu bar icon and the Settings window along with it.
- **Alias switches register while a menu is open or a window is being dragged.** They used to be queued until you finished, and only the fallback scan picked them up.

Behind the scenes: the parts that aren't a conversation with Mail now have a test suite — it's what found the invisible-characters bug above — every push is built and tested automatically, and the project builds clean under Swift 6's concurrency checking.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

## v0.11.3

Settings gains control over updates themselves.

- **Automatically check for updates** is now a preference you can change. Sparkle asks once at first launch; until now, whatever you answered that day was permanent.
- **Check Now**, next to the time of the last check, so the section tells you where you stand rather than only offering a button.
- **The running version sits on that same line** — what you're running and how current it is are one question, so they're one sentence.

Check for Updates… stays in the menu bar menu. For a menu-bar-only app that menu *is* the app menu, which is where macOS puts the command; Settings owns the preference behind it.

Automatic *downloading* is deliberately not offered. Replacing the app in the background is a poor default for something whose Accessibility grant is load-bearing.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

## v0.11.2

**Ottograph updates itself from here on.** This is the last version you have to download by hand.

- **Automatic updates**, via [Sparkle](https://sparkle-project.org). Ottograph checks for new versions and installs them in place. **Check for Updates…** in the menu bar menu forces a check. Every update is signed with an EdDSA key whose public half is built into the app, so a tampered download is refused even if the feed itself were replaced.
- **Because updates keep the same code signature, your Accessibility grant carries across them** — no re-approving after each version.
- **Settings shows the running version**, bottom right. "I'm on the latest" is now checkable.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

### Install
1. Open the DMG and drag **Ottograph** to Applications, replacing any older copy.
2. Launch it. Grant **Accessibility** when macOS asks — that permission *is* the engine.
3. Menu bar ✒️ → **Settings…** to map your aliases.

Replacing the app by hand — as opposed to letting Sparkle do it — can stale the existing Accessibility grant. If the menu says the permission is needed, remove Ottograph from System Settings → Privacy & Security → Accessibility and add it back.

### Requirements
macOS 14 or later, and Apple Mail. Signature names must match those in Mail → Settings → Signatures, and the mapped signature must be attached to the account that owns the alias.

### Known limits
- Matches English UI labels ("From", "Signature", "Send Later…").
- Tabbed compose windows work, but macOS's accessibility exposure of tabs is unreliable; separate windows are the well-tested path.

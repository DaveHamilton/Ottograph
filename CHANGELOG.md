# Changelog

Generated from `Notes/` by `Scripts/appcast.sh` — edit those files, not this one.

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

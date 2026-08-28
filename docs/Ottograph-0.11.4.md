A reliability release — and the first one that can tell you what went wrong.

- **Copy Diagnostics**, in the menu bar menu. It puts the version, your macOS and Mail versions, whether the Accessibility grant is still in place, and the last half hour of Ottograph's own log on the clipboard. If something looks off, that's the whole bug report, in one click.
- **Fixed: some aliases silently got no signature.** Mail wraps certain addresses in invisible formatting characters, and Ottograph was reading those as part of the address — so the alias matched none of your mappings and nothing was applied. If one alias has never worked while the others always did, this was probably why.
- **A signature name Mail doesn't have is now flagged in Settings**, right next to the row it's in. Previously a typo stayed invisible until that alias was next used, and then arrived as a failure notification long after the mistake — with the list of real names sitting in the picker beside it the whole time.
- **A stalled Mail no longer takes Ottograph with it.** Ottograph now waits a bounded time for Mail to answer, so a beachballing Mail can't freeze the menu bar icon and the Settings window along with it.
- **Alias switches register while a menu is open or a window is being dragged.** They used to be queued until you finished, and only the fallback scan picked them up.

Behind the scenes: the parts that aren't a conversation with Mail now have a test suite — it's what found the invisible-characters bug above — every push is built and tested automatically, and the project builds clean under Swift 6's concurrency checking.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

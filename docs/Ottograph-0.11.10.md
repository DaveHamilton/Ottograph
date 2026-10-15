A second fix for auto-Cc leaving a contact's name in the Cc field as plain text, which Mail then refuses to send.

- **Auto-Cc won't rewrite a field it can't fully read.** 0.11.9 stopped the usual cause, but it happened once more: the Cc field again ended up as the contact's name in plain text, followed by the address. Ottograph now checks the field itself, not just the recipients it could read. If anything there can't be written back cleanly — a recipient without a readable address, or text that hasn't become a recipient yet — it leaves the field alone. Adding your auto-Cc address alongside other recipients works as before.
- **Better clues if it ever happens again.** Copy Diagnostics now records which compose window each Cc change happened in and what the field looked like at the time (never anyone else's address). It also notes when switching From caused Cc to be checked again.

Signatures, the rest of auto-Cc, and delayed send behave as before.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

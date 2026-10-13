A fix for auto-Cc occasionally leaving a contact's name in the Cc field as plain text, which Mail then refuses to send.

- **Auto-Cc no longer mangles its own recipient.** Every so often, replying from an alias with auto-Cc left the Cc field reading as the contact's name in plain text followed by the address — not a valid recipient, so Mail wouldn't send it. The cause: Mail sometimes resets the Signature popup a moment after a compose window opens, and Ottograph rightly puts your signature back. But re-applying the signature also re-ran the Cc step, and by then Mail had matched the address to your Contacts, so it no longer read back as the address. Ottograph took it for some other recipient, rewrote the field, and the name ended up as text. The Cc is now handled once per sender per window; putting a signature back never touches it. Switching From to another alias and back still re-checks it.
- **A second safeguard.** If Ottograph ever finds a Cc recipient it can't read an address from, it now leaves the field alone rather than rewriting it.

It was rare — it needs Mail to reset the signature in that particular window — which is why the same reply could come out right several times in a row and then wrong. Signatures, the rest of auto-Cc, and delayed send behave as before.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

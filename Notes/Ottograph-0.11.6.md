One fix, for anyone using auto-Cc with an address that's also in Contacts.

- **Auto-Cc no longer mangles the address it just added.** If the Cc address was in your Contacts, the recipient appeared correctly for a moment — *Otto Graph <otto@example.com>* — and was then replaced by a single mangled recipient, *"Otto Graph , otto@example.com"*. Mail reports a recipient differently once it has matched the address against Contacts, and Ottograph was reading that as a different address, deciding its Cc was missing, and adding it a second time — which is what broke the recipient. It now recognises the address either way, so in the normal case it leaves a Cc it already added completely alone.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

One fix, for anyone using the ⇧⌘D takeover.

- **⇧⌘D outside a compose window does what it always did — Send Again.** Mail's ⇧⌘D is two commands, not one: Send in a compose window, and Message > Send Again in the viewer when a sent message is selected. Taking the shortcut over claimed both, so Send Again silently stopped working whenever the takeover was on — with no other shortcut to fall back on, because Mail doesn't offer one. Ottograph now asks Mail which command applies before acting: in a compose window you get the delayed send, everywhere else the keystroke goes through to Send Again.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

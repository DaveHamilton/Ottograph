The first bug report, fixed — and two things the Settings window did wrong once you had more than a handful of mappings.

- **Signatures apply with Mail's Format bar showing.** If you keep the Format bar open in compose windows (View > Show Format Bar), Ottograph applied your signature once after Mail launched, then never again — the log said the signature wasn't in the menu, on an account where it plainly was. The Format bar adds three popups (typeface, style, size) ahead of the header, and Ottograph was taking the first unlabeled one to be the Signature popup: it pressed the font menu, looked for your signature among typefaces, and gave up. Compose controls are now recognised by the identifiers Mail gives them, never by elimination. That also removes the dependency on English labels for the controls themselves.
- **Settings opens tall enough for its content.** The "Alias Mappings" heading and the version line were each cropped by a few points. The window now measures what it needs and can't be shrunk to where anything is clipped.
- **Add Mapping shows you the row it added.** With more mappings than fit, the new row appeared below the fold while the list stayed at the top. It scrolls into view now.

Universal (Apple Silicon + Intel), signed by Dave The Nerd, LLC, notarized and stapled.

**Still a test build.** It does real work on real mail, so treat it accordingly.

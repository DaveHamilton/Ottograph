import ApplicationServices

/// Mail's ⇧⌘D is two commands, not one. In a compose window it's Send; in
/// the viewer, with a sent message selected, it's Message > Send Again —
/// which opens a fresh compose window from that message. Ottograph's
/// takeover only means to replace the first of those, so when the shortcut
/// arrives outside a compose window it hands the keystroke back to Mail's
/// other meaning rather than swallowing it.
enum SendAgain {
    /// The menu path, in one place, since two call sites need it: the
    /// availability probe that routes ⇧⌘D and the press itself.
    static let menuPath = ["Message", "Send Again"]

    /// True when Mail would act on ⇧⌘D as Send Again — i.e. a sent message
    /// is selected in the key window. Mail's own validation, read off the
    /// menu item's enabled state.
    static var isAvailable: Bool {
        MailMenu.isEnabled(itemAt: menuPath)
    }

    /// Presses Message > Send Again. Returns false if the item is missing
    /// or disabled, so the caller can fall back rather than report a
    /// success that didn't happen.
    @discardableResult
    static func perform() -> Bool {
        guard let mail = MailMenu.application(),
              let item = MailMenu.item(at: menuPath, in: mail.element),
              MailMenu.isEnabled(item) else { return false }
        guard AX.press(item) else {
            Log.send.error("Message > Send Again wouldn't press")
            return false
        }
        Log.send.note("Not a compose window — passed ⇧⌘D through to Message > Send Again")
        return true
    }
}

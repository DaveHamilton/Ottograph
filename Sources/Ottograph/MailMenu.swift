import AppKit
import ApplicationServices

/// Finding and pressing items in Mail's menu bar.
///
/// The menu bar is the reliable way to drive Mail: an item is present
/// regardless of toolbar customization, pressing one via the accessibility
/// API opens no visible menu, and — the part this file exists for — an
/// item's enabled state is Mail's own answer to "does this command apply to
/// the key window right now?". That's what lets the ⇧⌘D takeover tell a
/// compose window from a viewer without reimplementing Mail's validation.
enum MailMenu {
    static let bundleIdentifier = "com.apple.mail"

    /// Mail as both an `NSRunningApplication` (for activation) and an AX
    /// element (for everything else), with the messaging timeout already
    /// clamped so a stalled Mail can't hang the main thread.
    static func application() -> (running: NSRunningApplication, element: AXUIElement)? {
        guard let mail = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first else { return nil }
        let element = AXUIElementCreateApplication(mail.processIdentifier)
        AX.limitMessagingTime(for: element)
        return (mail, element)
    }

    /// Walks a path of menu titles from the menu bar, e.g.
    /// `["Message", "Send Later", "Send Later…"]`, descending through each
    /// item's single `AXMenu` child on the way down.
    ///
    /// Titles, not identifiers: Mail's menu items all report
    /// `_popUpItemAction:` as their `AXIdentifier` — the selector, not an
    /// identity — so there is nothing structural to match on here.
    static func item(at path: [String], in application: AXUIElement) -> AXUIElement? {
        guard let rawBar = AX.attribute(application, kAXMenuBarAttribute),
              CFGetTypeID(rawBar) == AXUIElementGetTypeID() else { return nil }
        var container = rawBar as! AXUIElement
        var item: AXUIElement?
        for title in path {
            guard let match = AX.children(of: container)
                .first(where: { AX.title(of: $0) == title }) else { return nil }
            item = match
            guard let submenu = AX.children(of: match).first else { continue }
            container = submenu
        }
        return item
    }

    /// Mail disables a menu item when its command doesn't apply, so this
    /// doubles as validation — see the type comment.
    static func isEnabled(_ item: AXUIElement) -> Bool {
        (AX.attribute(item, kAXEnabledAttribute) as? Bool) ?? false
    }

    /// Convenience for the common "is this command available right now?"
    /// question, which needs a fresh Mail element each time.
    static func isEnabled(itemAt path: [String]) -> Bool {
        guard let mail = application(),
              let item = item(at: path, in: mail.element) else { return false }
        return isEnabled(item)
    }
}

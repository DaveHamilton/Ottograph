import ApplicationServices
import Foundation

/// Thin helpers over the Accessibility (AXUIElement) C API.
enum AX {
    /// Every AX call is a synchronous IPC round trip into the target app,
    /// and the default timeout is ~6 seconds *per call*. A single scan
    /// makes hundreds of them, so a beachballing Mail would otherwise hang
    /// Ottograph's main thread — freezing the menu bar item and the
    /// Settings window, which looks like Ottograph crashed rather than
    /// Mail stalling. Two seconds is far longer than a healthy reply and
    /// short enough to stay responsive.
    static let messagingTimeout: Float = 2.0

    /// Applies to every message sent to this app's element tree.
    static func limitMessagingTime(for application: AXUIElement) {
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return err == .success ? value : nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return raw.compactMap { obj in
            guard CFGetTypeID(obj) == AXUIElementGetTypeID() else { return nil }
            return (obj as! AXUIElement)
        }
    }

    static func role(of element: AXUIElement) -> String {
        attribute(element, kAXRoleAttribute) as? String ?? ""
    }

    static func stringValue(of element: AXUIElement) -> String? {
        attribute(element, kAXValueAttribute) as? String
    }

    static func title(of element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute) as? String
    }

    /// The text of the label element associated with a control (e.g. "From:").
    static func labelText(of element: AXUIElement) -> String? {
        guard let raw = attribute(element, kAXTitleUIElementAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let label = raw as! AXUIElement
        return stringValue(of: label) ?? title(of: label)
    }

    static func description(of element: AXUIElement) -> String? {
        attribute(element, kAXDescriptionAttribute) as? String
    }

    /// The developer-assigned identifier (`popup_signature`, `Mail.ccField`).
    /// Structural rather than presentational, so it survives localisation
    /// and costs one round trip where a label costs two. Empty reads as nil.
    static func identifier(of element: AXUIElement) -> String? {
        guard let id = attribute(element, kAXIdentifierAttribute) as? String, !id.isEmpty else { return nil }
        return id
    }

    /// Depth-first search for the first element passing `test`.
    static func findFirst(in element: AXUIElement, depth: Int = 0, where test: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth < 15 else { return nil }
        if test(element) { return element }
        for child in children(of: element) {
            if let hit = findFirst(in: child, depth: depth + 1, where: test) { return hit }
        }
        return nil
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func cancel(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXCancelAction as CFString) == .success
    }
}

/// Hashable wrapper so AXUIElements can key a dictionary (per-window state).
struct AXElementKey: Hashable {
    let element: AXUIElement

    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

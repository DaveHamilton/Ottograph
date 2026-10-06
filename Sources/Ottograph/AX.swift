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

    /// Roles a walk never enters. While the screen is locked, Mail on macOS
    /// 27.2 (beta 3) answers `AXWindows` — and `AXMainWindow`,
    /// `AXFocusedWindow` — with the *application* element, and lists the
    /// application twice among its own children. A depth-limited walk from
    /// a "window" therefore branched app → app, app, menu bar at every
    /// level: ~475,000 AX calls and 90+ seconds per window, once a second,
    /// all night. Nothing we look for lives under these roles anyway.
    static let neverEnteredRoles: Set<String> = [
        "AXApplication", "AXMenuBar", "AXMenuBarItem", "AXMenu",
    ]

    enum WalkStep { case descend, skip, stop }

    /// Depth-first, pre-order walk of everything below `root`, which every
    /// tree search goes through so none of them can run away. Three
    /// independent bounds, because each one alone has a way to fail: a
    /// visited set (cycles), a depth limit, and an element cap (a tree
    /// that is merely huge — the message viewer). `visit` gets each
    /// element with its role, already read. Returns false if the cap hit.
    @discardableResult
    static func walk(
        below root: AXUIElement, maxDepth: Int = 15, maxElements: Int = 1500,
        _ visit: (AXUIElement, String) -> WalkStep
    ) -> Bool {
        var seen: Set<AXElementKey> = [AXElementKey(element: root)]
        var stack: [(element: AXUIElement, depth: Int)] = children(of: root).reversed().map { ($0, 1) }
        var visited = 0
        while let (element, depth) = stack.popLast() {
            guard seen.insert(AXElementKey(element: element)).inserted else { continue }
            visited += 1
            guard visited <= maxElements else { return false }
            let role = role(of: element)
            if neverEnteredRoles.contains(role) { continue }
            switch visit(element, role) {
            case .stop: return true
            case .skip: continue
            case .descend:
                guard depth < maxDepth else { continue }
                stack.append(contentsOf: children(of: element).reversed().map { ($0, depth + 1) })
            }
        }
        return true
    }

    /// Depth-first search for the first element passing `test`.
    static func findFirst(in element: AXUIElement, where test: (AXUIElement) -> Bool) -> AXUIElement? {
        if test(element) { return element }
        var hit: AXUIElement?
        walk(below: element) { candidate, _ in
            guard test(candidate) else { return .descend }
            hit = candidate
            return .stop
        }
        return hit
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

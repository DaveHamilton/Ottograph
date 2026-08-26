import ApplicationServices
import Foundation

/// Thin helpers over the Accessibility (AXUIElement) C API.
enum AX {
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

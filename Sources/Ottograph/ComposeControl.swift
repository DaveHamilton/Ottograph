import Foundation

/// The compose-window controls the engine drives, and how to recognise
/// each one from what an element exposes to Accessibility.
///
/// Recognition is deliberately a pure function of two strings so it can be
/// unit tested against real probe output (`Scripts/ax-probe.swift`) — the
/// engine itself can only be exercised against a live Mail.
///
/// Mail 16 gives every compose control a stable `AXIdentifier`
/// (`popup_signature`, `Mail.ccField`, …). Those are structural and
/// locale-independent, so they win. The label element next to the control
/// ("Signature:") is the fallback for a Mail that doesn't populate them.
///
/// There is no third guess. There used to be one — "an unlabeled popup
/// whose value isn't an address or a priority is the Signature popup" —
/// and it was wrong the moment the Format bar was showing: its font popups
/// ("Helvetica", "Regular", "16") have no label, no identifier, and come
/// *before* the header controls in the tree. The engine then pressed the
/// font popup, looked for the signature in a list of typefaces, and
/// reported the signature as missing from the account. Anyone who keeps
/// the Format bar open saw that on every compose window.
enum ComposeControl: Equatable {
    case from
    case signature
    case cc
    case subject

    static func classify(identifier: String?, label: String?) -> ComposeControl? {
        switch identifier {
        case "popup_from": return .from
        case "popup_signature": return .signature
        case "Mail.ccField": return .cc
        case "Mail.subjectField": return .subject
        default: break
        }
        guard let label else { return nil }
        if label.hasPrefix("From") { return .from }
        if label.hasPrefix("Signature") { return .signature }
        if label.hasPrefix("Cc") { return .cc }
        if label.hasPrefix("Subject") { return .subject }
        return nil
    }
}

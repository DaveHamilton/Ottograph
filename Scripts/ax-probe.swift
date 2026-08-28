#!/usr/bin/env swift
// Dumps what Mail's compose windows actually expose to the Accessibility
// API — specifically whether the popups and menu items carry an
// AXIdentifier. Identifiers are structural and locale-independent; the
// engine currently matches on English titles ("From", "Signature",
// "None"), which is both the localisation blocker and the most fragile
// thing in the app. If identifiers are there, discoverControls should be
// matching on those instead.
//
//   swift ax-probe.swift              # read-only: windows, popups, fields
//   swift ax-probe.swift --open-menus # also presses popups to list items
//
// The process running this needs Accessibility trust — grant it to
// Terminal (System Settings → Privacy & Security → Accessibility).
// --open-menus briefly opens menus, so have a throwaway compose window
// open (⌘N) and don't touch the mouse while it runs.

import AppKit
import ApplicationServices

let openMenus = CommandLine.arguments.contains("--open-menus")

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String? { attr(e, name) as? String }
func kids(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap {
        CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
    }
}
/// The whole point of the probe: is there a locale-independent handle?
func identifier(_ e: AXUIElement) -> String {
    str(e, "AXIdentifier").map { $0.isEmpty ? "(empty)" : $0 } ?? "—"
}
func label(_ e: AXUIElement) -> String {
    guard let raw = attr(e, kAXTitleUIElementAttribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return "—" }
    let l = raw as! AXUIElement
    return str(l, kAXValueAttribute) ?? str(l, kAXTitleAttribute) ?? "—"
}
func describe(_ e: AXUIElement, indent: String) {
    let role = str(e, kAXRoleAttribute) ?? "?"
    print("\(indent)\(role)")
    print("\(indent)  AXIdentifier:      \(identifier(e))")
    print("\(indent)  AXTitle:           \(str(e, kAXTitleAttribute) ?? "—")")
    print("\(indent)  AXValue:           \(str(e, kAXValueAttribute) ?? "—")")
    print("\(indent)  AXDescription:     \(str(e, kAXDescriptionAttribute) ?? "—")")
    print("\(indent)  AXRoleDescription: \(str(e, "AXRoleDescription") ?? "—")")
    print("\(indent)  label element:     \(label(e))")
}

guard AXIsProcessTrusted() else {
    print("This process isn't trusted for Accessibility.")
    print("System Settings → Privacy & Security → Accessibility → add your terminal.")
    exit(1)
}
guard let mail = NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.mail").first else {
    print("Mail isn't running.")
    exit(1)
}
let app = AXUIElementCreateApplication(mail.processIdentifier)
AXUIElementSetMessagingTimeout(app, 2.0)

// Same pruning the engine uses, so the probe sees what the engine sees.
let pruned: Set<String> = ["AXTable", "AXOutline", "AXList", "AXWebArea",
                           "AXStaticText", "AXTextArea", "AXImage", "AXMenu"]
func collect(_ e: AXUIElement, _ depth: Int, _ popups: inout [AXUIElement], _ fields: inout [AXUIElement]) {
    guard depth < 15 else { return }
    for c in kids(e) {
        let role = str(c, kAXRoleAttribute) ?? ""
        if role == "AXPopUpButton" { popups.append(c); continue }
        if role == "AXTextField" { fields.append(c); continue }
        if pruned.contains(role) { continue }
        collect(c, depth + 1, &popups, &fields)
    }
}

let windows = (attr(app, kAXWindowsAttribute) as? [AnyObject] ?? []).compactMap {
    CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
}
print("Mail pid \(mail.processIdentifier), \(windows.count) window(s)\n")

for (i, w) in windows.enumerated() {
    var popups: [AXUIElement] = [], fields: [AXUIElement] = []
    collect(w, 0, &popups, &fields)
    // A compose window is the one with popups; the viewer has none.
    print("── window \(i): \(str(w, kAXTitleAttribute) ?? "(untitled)") — \(popups.count) popup(s), \(fields.count) field(s)")
    guard !popups.isEmpty else { print("   (not a compose window)\n"); continue }

    for (j, p) in popups.enumerated() {
        print("\n  popup \(j):")
        describe(p, indent: "  ")
        guard openMenus else { continue }
        // Menu items only exist while the menu is open, so this has to
        // press — the same press the engine makes in normal use.
        guard AXUIElementPerformAction(p, kAXPressAction as CFString) == .success else {
            print("    (couldn't press)"); continue
        }
        var menu: AXUIElement?
        for _ in 0..<200 {
            if let m = kids(p).first(where: { str($0, kAXRoleAttribute) == "AXMenu" }) { menu = m; break }
            usleep(5_000)
        }
        if let menu {
            print("    menu items:")
            for item in kids(menu) {
                print("      title: \(str(item, kAXTitleAttribute) ?? "—")   AXIdentifier: \(identifier(item))")
            }
            AXUIElementPerformAction(menu, kAXCancelAction as CFString) // leave the UI as we found it
        } else {
            print("    (menu didn't open)")
        }
    }
    for (j, f) in fields.enumerated() {
        print("\n  field \(j):")
        describe(f, indent: "  ")
    }
    print("")
}

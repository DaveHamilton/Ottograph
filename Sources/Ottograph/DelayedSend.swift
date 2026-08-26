import AppKit
import ApplicationServices

/// "Send in N minutes": a regret window longer than Undo Send's 30-second
/// cap, built on Mail's own Send Later machinery. The focused compose
/// window is scheduled for now + delay via the Send Later sheet (whose
/// AXDateTimeArea accepts an exact Date through the accessibility API).
/// Until the time arrives the message sits in Mail's Send Later mailbox,
/// where it can be opened, edited, or deleted — a strictly better undo
/// than Undo Send, and it survives quitting Mail.
enum DelayedSend {
    static func schedule(afterSeconds delay: TimeInterval, onStatus: (String) -> Void) {
        guard let mail = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.mail").first else {
            onStatus("Mail isn't running")
            return
        }
        let app = AXUIElementCreateApplication(mail.processIdentifier)
        guard let rawWindow = AX.attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            onStatus("No focused Mail window")
            return
        }
        let window = rawWindow as! AXUIElement

        guard let sendLaterButton = AX.findFirst(in: window, where: {
            AX.role(of: $0) == "AXMenuButton" && AX.description(of: $0) == "Send Later"
        }) else {
            onStatus("Focus a compose window first (its toolbar needs the Send Later button)")
            return
        }

        // The Send Later menu only opens for the frontmost window.
        mail.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        usleep(400_000)

        guard AX.press(sendLaterButton) else {
            onStatus("Couldn't press Send Later")
            return
        }
        guard let menu = wait(timeout: 1.5, for: {
            AX.children(of: sendLaterButton).first { AX.role(of: $0) == "AXMenu" }
                ?? AX.findFirst(in: window, where: { AX.role(of: $0) == "AXMenu" })
        }) else {
            onStatus("Send Later menu didn't open")
            return
        }
        guard let customItem = AX.children(of: menu).first(where: { AX.title(of: $0) == "Send Later…" }) else {
            AX.cancel(menu)
            onStatus("'Send Later…' menu item not found")
            return
        }
        AX.press(customItem)

        guard let sheet = wait(timeout: 2.0, for: {
            AX.children(of: window).first { AX.role(of: $0) == "AXSheet" }
        }) else {
            onStatus("Send Later dialog didn't appear")
            return
        }
        guard let dateArea = AX.findFirst(in: sheet, where: { AX.role(of: $0) == "AXDateTimeArea" }) else {
            cancel(sheet)
            onStatus("Date picker not found in Send Later dialog")
            return
        }

        let target = Date(timeIntervalSinceNow: delay)
        guard AXUIElementSetAttributeValue(dateArea, kAXValueAttribute as CFString, target as NSDate) == .success else {
            cancel(sheet)
            onStatus("Couldn't set the send time")
            return
        }
        guard let scheduleButton = AX.findFirst(in: sheet, where: {
            AX.role(of: $0) == "AXButton" && AX.title(of: $0) == "Schedule"
        }) else {
            cancel(sheet)
            onStatus("Schedule button not found")
            return
        }
        AX.press(scheduleButton)

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        onStatus("Sending at \(formatter.string(from: target)) — cancel or edit in the Send Later mailbox")
    }

    private static func wait(timeout: TimeInterval, for probe: () -> AXUIElement?) -> AXUIElement? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if let found = probe() { return found }
            usleep(50_000)
        }
        return probe()
    }

    private static func cancel(_ sheet: AXUIElement) {
        if let cancelButton = AX.findFirst(in: sheet, where: {
            AX.role(of: $0) == "AXButton" && AX.title(of: $0) == "Cancel"
        }) {
            AX.press(cancelButton)
        }
    }
}

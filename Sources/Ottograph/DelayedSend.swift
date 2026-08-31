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
    /// What happened, so the caller can distinguish a scheduled message
    /// (worth an optional receipt) from a failure (worth telling the user).
    enum Outcome {
        case scheduled(Date)
        case failed(String)
    }

    /// Use the Message > Send Later > Send Later… menu bar item rather than
    /// the toolbar button — it's always present regardless of toolbar
    /// customization, and pressing it via AX doesn't visibly open any menu.
    /// Its enabled state also doubles as validation: Mail disables it
    /// unless a sendable compose window is key.
    static let menuPath = ["Message", "Send Later", "Send Later…"]

    /// True when there's a compose window Mail would let us schedule. This
    /// is what routes the ⇧⌘D takeover: asking Mail is cheaper and more
    /// honest than inspecting the focused window ourselves, and it's the
    /// same condition `schedule` re-checks before pressing.
    static var isAvailable: Bool {
        MailMenu.isEnabled(itemAt: menuPath)
    }

    static func schedule(afterSeconds delay: TimeInterval, onOutcome: (Outcome) -> Void) {
        guard let mail = MailMenu.application() else {
            onOutcome(.failed("Mail isn't running"))
            return
        }
        guard let rawWindow = AX.attribute(mail.element, kAXFocusedWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            onOutcome(.failed("No focused Mail window"))
            return
        }
        let window = rawWindow as! AXUIElement

        guard let customItem = MailMenu.item(at: menuPath, in: mail.element) else {
            onOutcome(.failed("Message > Send Later > Send Later… not found"))
            return
        }

        mail.running.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        usleep(400_000)

        guard MailMenu.isEnabled(customItem) else {
            onOutcome(.failed("Send Later unavailable — is a compose window with a recipient focused?"))
            return
        }
        AX.press(customItem)

        guard let sheet = wait(timeout: 2.0, for: {
            AX.children(of: window).first { AX.role(of: $0) == "AXSheet" }
        }) else {
            onOutcome(.failed("Send Later dialog didn't appear"))
            return
        }
        guard let dateArea = AX.findFirst(in: sheet, where: { AX.role(of: $0) == "AXDateTimeArea" }) else {
            cancel(sheet)
            onOutcome(.failed("Date picker not found in Send Later dialog"))
            return
        }

        let target = Date(timeIntervalSinceNow: delay)
        guard AXUIElementSetAttributeValue(dateArea, kAXValueAttribute as CFString, target as NSDate) == .success else {
            cancel(sheet)
            onOutcome(.failed("Couldn't set the send time"))
            return
        }
        guard let scheduleButton = AX.findFirst(in: sheet, where: {
            AX.role(of: $0) == "AXButton" && AX.title(of: $0) == "Schedule"
        }) else {
            cancel(sheet)
            onOutcome(.failed("Schedule button not found"))
            return
        }
        AX.press(scheduleButton)

        onOutcome(.scheduled(target))
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

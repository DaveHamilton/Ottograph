import AppKit
import ApplicationServices
import Foundation

/// Watches Mail's compose windows via the Accessibility API and applies the
/// signature mapped to whichever From address each window currently has.
///
/// Why Accessibility and not AppleScript: modern Mail does not expose
/// manually opened compose windows (⌘N, replies, forwards) in AppleScript's
/// `outgoing messages` — only script-created ones. The Accessibility tree,
/// however, exposes every compose window's From popup (readable) and
/// Signature popup (settable). This also means Ottograph needs only the
/// Accessibility permission — no Apple events, no Automation prompt.
///
/// Architecture: event-driven with a polling fallback.
/// - An AXObserver watches Mail for window creation and for value changes on
///   each compose window's From popup, so reactions are immediate.
/// - A timer still scans every `pollSeconds` as a safety net for anything
///   events miss (sleep/wake, Mail relaunch, windows that finish building
///   after their creation notification).
/// - Both paths funnel into the same scan, which acts only when a window's
///   sender *changes* (or the window is first seen), so a signature the user
///   picks manually afterward is left alone.
/// - Applying a signature means opening the Signature popup's menu, which
///   macOS refuses to do while another menu (e.g. the From popup the user
///   just clicked) is open. Failed attempts are retried shortly after
///   instead of being abandoned.
/// - Never launches Mail; scanning is skipped unless Mail is already running.
///
/// Main-actor isolated on purpose: every path into it already runs on the
/// main run loop — the poll timer, the AXObserver's run loop source, and
/// AppDelegate — and the per-window state below has no locking of its own.
/// The `assumeIsolated` calls are assertions of that, not workarounds.
@MainActor
final class SignatureEngine {
    private let store: ConfigStore
    private var timer: Timer?
    private var lastSenderByWindow: [AXElementKey: String] = [:]
    private var windowLastSeen: [AXElementKey: Date] = [:]
    private var retryState: [AXElementKey: (email: String, attempts: Int)] = [:]
    private var axApp: AXUIElement?
    private var axAppPID: pid_t = -1
    /// `nonisolated(unsafe)` only so `deinit` can remove the run loop
    /// source: AXObserver is a C type with no Sendable conformance, and
    /// every assignment to this happens on the main actor.
    nonisolated(unsafe) private var observer: AXObserver?

    private static let maxApplyAttempts = 4

    /// The engine re-evaluates every tick, so a persistent failure would
    /// otherwise write a line per second for as long as it persists.
    private var failureLog = RepeatSuppressor()

    private(set) var isRunning = false

    /// Human-readable status for the menu bar UI.
    var onStatus: ((String) -> Void)?

    /// Called only for genuine failures — something the user may need to
    /// fix, as opposed to routine chatter or a transient retry that heals
    /// itself. Wired to notifications, so it must stay quiet in normal use.
    var onFailure: ((String) -> Void)?

    private func report(_ message: String, failure: Bool = false) {
        onStatus?(message)
        guard failure else { return }
        // The status line is cheap and always current; the log and the
        // banner are the ones a repeat would drown.
        if failureLog.allows(message) { Log.engine.error(message) }
        onFailure?(message)
    }

    init(store: ConfigStore) {
        self.store = store
    }

    /// Not `teardownObserver()`: a deinit can't call a main-actor method.
    /// Removing the run loop source is safe from anywhere.
    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if !Self.ensureAccessibilityPermission() {
            report("Accessibility permission needed (System Settings → Privacy & Security → Accessibility)", failure: true)
        } else {
            onStatus?("Watching Mail")
        }
        scheduleTimer()
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        teardownObserver()
        lastSenderByWindow.removeAll()
        retryState.removeAll()
        axApp = nil
        axAppPID = -1
        isRunning = false
        onStatus?("Paused")
    }

    /// Prompts the user (once, system-managed) if the process isn't trusted.
    static func ensureAccessibilityPermission() -> Bool {
        // Spelled out rather than read from kAXTrustedCheckOptionPrompt:
        // that constant is imported as a mutable global, so Swift 6 won't
        // let it be read safely. The string is the constant's value and
        // has been since the API shipped.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = store.config.pollSeconds
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            // Added to the main run loop below, so it fires on the main actor.
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - AX notifications (the event-driven path)

    fileprivate func handleNotification(_ name: String) {
        switch name {
        case kAXWindowCreatedNotification:
            // A compose window's popups can finish building after the
            // notification, so scan a few times as it settles.
            scheduleScan(after: 0.3)
            scheduleScan(after: 0.8)
            scheduleScan(after: 1.5)
        case kAXValueChangedNotification:
            // The From popup of some compose window changed. Don't react
            // instantly: Mail resets the Signature popup itself shortly
            // after a From change, and applying before that reset lands
            // means our work gets stomped and retried — a double blink.
            // ~300ms lets Mail settle so we apply exactly once.
            scheduleScan(after: 0.3)
        default:
            break
        }
    }

    private func scheduleScan(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
    }

    private func ensureObserver(for pid: pid_t) {
        guard observer == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, ottographAXCallback, &created) == .success,
              let created else { return }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let axApp {
            AXObserverAddNotification(created, axApp, kAXWindowCreatedNotification as CFString, refcon)
        }
        // .commonModes, not .defaultMode: a run loop in event-tracking mode
        // (a menu open, a window being dragged) does not run the default
        // mode, so AX notifications would queue until it returned. The poll
        // masked that; the fix is to stop relying on the poll for it.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    /// Subscribes to value changes on a compose window's From popup so alias
    /// switches are handled the moment they happen. Re-registration of an
    /// already-observed element is a harmless no-op error.
    private func observeFromPopup(_ popup: AXUIElement) {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, popup, kAXValueChangedNotification as CFString, refcon)
    }

    // MARK: - Scan (shared by timer and events)

    private func tick() {
        guard isRunning else { return }

        if store.reloadIfChanged() {
            scheduleTimer() // pick up a changed pollSeconds
            onStatus?("Config reloaded")
        }

        guard let mail = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.mail").first else {
            lastSenderByWindow.removeAll()
            retryState.removeAll()
            teardownObserver()
            axApp = nil
            axAppPID = -1
            return
        }
        guard AXIsProcessTrusted() else {
            report("Accessibility permission needed (System Settings → Privacy & Security → Accessibility)", failure: true)
            return
        }

        if axApp == nil || axAppPID != mail.processIdentifier {
            teardownObserver()
            let created = AXUIElementCreateApplication(mail.processIdentifier)
            AX.limitMessagingTime(for: created)
            axApp = created
            axAppPID = mail.processIdentifier
            lastSenderByWindow.removeAll()
            retryState.removeAll()
        }
        ensureObserver(for: mail.processIdentifier)

        guard let axApp,
              let windows = AX.attribute(axApp, kAXWindowsAttribute) as? [AnyObject] else { return }

        var seenWindows = Set<AXElementKey>()

        for rawWindow in windows {
            guard CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { continue }
            let window = rawWindow as! AXUIElement
            guard let compose = discoverControls(in: window) else { continue }

            let key = AXElementKey(element: window)
            seenWindows.insert(key)
            windowLastSeen[key] = Date()
            observeFromPopup(compose.from)

            guard let senderValue = AX.stringValue(of: compose.from),
                  let email = Self.emailAddress(in: senderValue)?.lowercased() else { continue }

            guard email != lastSenderByWindow[key] else { continue }

            let signatureName = store.config.signatures[email]
            let ccAddress = store.config.autoCc?[email]

            guard signatureName != nil || ccAddress != nil else {
                lastSenderByWindow[key] = email
                retryState[key] = nil
                onStatus?("No mapping for \(email)")
                continue
            }

            // If the user has the From popup's menu open right now (mid-
            // switch), opening the Signature menu would fail — macOS allows
            // one open menu at a time. Try again shortly.
            if openMenu(of: compose.from) != nil {
                scheduleScan(after: 0.35)
                continue
            }

            // Auto-Cc first — it's idempotent (existing tokens are read
            // for dedupe), so a signature retry replaying this block is
            // harmless. That idempotence rests on `tokenAddress` reading a
            // Contacts-resolved pill correctly; without it the replay is
            // what corrupts the recipient.
            if let ccAddress {
                ensureCc(ccAddress, controls: compose, forEmail: email)
            }

            guard let signatureName else {
                // Cc-only alias: nothing further to apply.
                lastSenderByWindow[key] = email
                retryState[key] = nil
                continue
            }

            switch apply(signatureName: signatureName, to: compose.signature, in: window, forEmail: email) {
            case .applied:
                lastSenderByWindow[key] = email
                retryState[key] = nil
                scheduleVerification(
                    windowKey: key, window: window, email: email,
                    target: signatureName.isEmpty ? "None" : signatureName
                )
            case .giveUp:
                lastSenderByWindow[key] = email
                retryState[key] = nil
            case .retry:
                var state = retryState[key] ?? (email: email, attempts: 0)
                if state.email != email { state = (email: email, attempts: 0) }
                state.attempts += 1
                if state.attempts >= Self.maxApplyAttempts {
                    lastSenderByWindow[key] = email
                    retryState[key] = nil
                    report("Gave up applying signature for \(email)", failure: true)
                    log("Gave up applying signature for \(email) after \(state.attempts) attempts")
                } else {
                    // Leave lastSenderByWindow unchanged so the next scan
                    // sees the same sender "change" and tries again.
                    retryState[key] = state
                    scheduleScan(after: 0.35)
                }
            }
        }

        // Forget windows we haven't seen for a while. NOT immediately:
        // a compose window in a background tab disappears from the AX
        // windows list entirely, and pruning it right away would make it
        // look brand-new on every tab switch — triggering a pointless
        // re-apply (and menu blink) each time it comes back to the front.
        let cutoff = Date().addingTimeInterval(-600)
        lastSenderByWindow = lastSenderByWindow.filter { key, _ in
            seenWindows.contains(key) || (windowLastSeen[key] ?? .distantPast) > cutoff
        }
        windowLastSeen = windowLastSeen.filter { lastSenderByWindow.keys.contains($0.key) }
        // Retries, by contrast, only make sense for windows still on screen.
        retryState = retryState.filter { seenWindows.contains($0.key) }
    }

    // MARK: - Compose window discovery

    private struct ComposeControls {
        let from: AXUIElement
        let signature: AXUIElement
        let cc: AXUIElement?
        let subject: AXUIElement?
    }

    /// Roles we never need to descend into — prunes the (large) subtrees of
    /// the main viewer window and the compose body so scans stay cheap.
    private static let prunedRoles: Set<String> = [
        "AXTable", "AXOutline", "AXList", "AXWebArea",
        "AXStaticText", "AXTextArea", "AXImage", "AXMenu",
    ]

    /// Returns the compose window's controls if this is a compose window
    /// (i.e. it has From and Signature popups), else nil.
    private func discoverControls(in window: AXUIElement) -> ComposeControls? {
        var popups: [AXUIElement] = []
        var textFields: [AXUIElement] = []
        collectControls(in: window, depth: 0, popups: &popups, textFields: &textFields)
        guard !popups.isEmpty else { return nil }

        var fromPopup: AXUIElement?
        var signaturePopup: AXUIElement?

        for popup in popups {
            let label = AX.labelText(of: popup) ?? ""
            let value = AX.stringValue(of: popup) ?? ""
            if label.hasPrefix("From") || (label.isEmpty && value.contains("@")) {
                fromPopup = fromPopup ?? popup
            } else if label.hasPrefix("Signature")
                || (label.isEmpty && !value.contains("@") && !value.contains("Priority")) {
                signaturePopup = signaturePopup ?? popup
            }
        }

        var ccField: AXUIElement?
        var subjectField: AXUIElement?
        for field in textFields {
            let label = AX.labelText(of: field) ?? ""
            if label.hasPrefix("Cc") {
                ccField = ccField ?? field
            } else if label.hasPrefix("Subject") {
                subjectField = subjectField ?? field
            }
        }

        guard let fromPopup, let signaturePopup else { return nil }
        return ComposeControls(from: fromPopup, signature: signaturePopup, cc: ccField, subject: subjectField)
    }

    private func collectControls(
        in element: AXUIElement, depth: Int,
        popups: inout [AXUIElement], textFields: inout [AXUIElement]
    ) {
        guard depth < 15 else { return }
        for child in AX.children(of: element) {
            let role = AX.role(of: child)
            if role == "AXPopUpButton" {
                popups.append(child)
                continue
            }
            if role == "AXTextField" {
                // Leaf on purpose: an address field's children are its
                // token pills (themselves AXTextFields) — we want the
                // container here, not the tokens.
                textFields.append(child)
                continue
            }
            if Self.prunedRoles.contains(role) { continue }
            collectControls(in: child, depth: depth + 1, popups: &popups, textFields: &textFields)
        }
    }

    // MARK: - Applying a signature

    private enum ApplyResult {
        case applied
        case retry   // transient failure — try again shortly
        case giveUp  // permanent failure — e.g. signature not in this menu
    }

    private func openMenu(of popup: AXUIElement) -> AXUIElement? {
        AX.children(of: popup).first { AX.role(of: $0) == "AXMenu" }
    }

    // MARK: - Auto-Cc

    /// Adds `address` to the compose window's Cc field if it isn't there
    /// already. A token field renders each recipient as a pill (a child
    /// AXTextField), so dedupe reads the existing tokens. Setting the
    /// field's value tokenizes instantly, but the message model only picks
    /// the recipient up on focus-out — so the field is focused briefly and
    /// focus is then handed back to wherever it was.
    ///
    /// Both halves of this deliberately go through `tokenAddress`: a pill
    /// Mail has resolved against Contacts reads back as "Name <addr>", not
    /// as the bare address, and comparing those strings whole makes an
    /// address that is already present look missing.
    private func ensureCc(_ address: String, controls: ComposeControls, forEmail email: String) {
        guard let ccField = controls.cc else {
            report("No Cc field found for \(email)", failure: true)
            return
        }

        let existingAddresses = AX.children(of: ccField)
            .compactMap { AX.stringValue(of: $0) }
            .map(Self.tokenAddress)
            .filter { !$0.isEmpty }
        let want = Self.tokenAddress(address)
        guard !existingAddresses.contains(where: { $0.caseInsensitiveCompare(want) == .orderedSame }) else {
            return
        }

        // Never fight the user for a field they're editing right now.
        var previousFocus: AXUIElement?
        if let axApp,
           let rawFocus = AX.attribute(axApp, kAXFocusedUIElementAttribute),
           CFGetTypeID(rawFocus) == AXUIElementGetTypeID() {
            let focused = rawFocus as! AXUIElement
            if CFEqual(focused, ccField) { return }
            previousFocus = focused
        }

        // Bare addresses only. Setting this attribute replaces the whole
        // field, and Mail's parser mishandles a comma-separated list that
        // contains angle brackets: "A <a@x>, b@x" comes back as a *single*
        // recipient whose display name is "A , b@x". Verified against Mail
        // 16.0 — quoting the display name doesn't help, and neither does a
        // semicolon or a newline separator. A list of plain addresses is
        // the one form that tokenizes back into one pill per recipient.
        let combined = (existingAddresses + [want]).joined(separator: ", ")
        guard AXUIElementSetAttributeValue(ccField, kAXValueAttribute as CFString, combined as CFTypeRef) == .success else {
            report("Couldn't set Cc for \(email)", failure: true)
            log("Couldn't set Cc \(address) for \(email)")
            return
        }

        // Commit the tokens to the message model: focus in, focus away.
        _ = AXUIElementSetAttributeValue(ccField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(120_000)
        if let restoreTarget = previousFocus ?? controls.subject {
            _ = AXUIElementSetAttributeValue(restoreTarget, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }

        log("Added Cc \(address) for \(email)")
        onStatus?("Added Cc \(address) for \(email)")
    }

    /// Blink-free safety net: well after an apply, re-read the Signature
    /// popup with fresh elements. Only a genuine miss re-applies (which
    /// then blinks once more — the acceptable cost of a real failure).
    private func scheduleVerification(windowKey: AXElementKey, window: AXUIElement, email: String, target: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isRunning else { return }
                guard self.lastSenderByWindow[windowKey] == email else { return } // sender moved on
                guard let compose = self.discoverControls(in: window),
                      let current = AX.stringValue(of: compose.signature) else { return } // window gone/rebuilding
                if current != target {
                    self.log("Post-apply check for \(email): expected '\(target)', found '\(current)' — reapplying")
                    self.lastSenderByWindow[windowKey] = nil
                    self.scheduleScan(after: 0.05)
                }
            }
        }
    }

    private func apply(signatureName: String, to popup: AXUIElement, in window: AXUIElement, forEmail email: String) -> ApplyResult {
        // Empty string in the config means "no signature" — Mail's popup
        // calls that item "None".
        let target = signatureName.isEmpty ? "None" : signatureName

        // A menu left open on this popup (from an interrupted attempt) would
        // turn our press into a toggle-close. Clear it first.
        if let stale = openMenu(of: popup) {
            AX.cancel(stale)
            usleep(100_000)
        }

        guard AX.press(popup) else {
            log("Couldn't press Signature popup for \(email) — will retry")
            onStatus?("Couldn't open Signature popup — retrying")
            return .retry
        }

        // The menu appears asynchronously after the press. Check immediately
        // and re-check every 5ms so the menu is on screen as briefly as
        // possible — the whole open/select round trip is a frame or two.
        var menu: AXUIElement?
        for _ in 0..<200 {
            if let found = openMenu(of: popup) {
                menu = found
                break
            }
            usleep(5_000)
        }
        guard let menu else {
            log("Signature menu didn't open for \(email) — will retry")
            onStatus?("Signature menu didn't open — retrying")
            return .retry
        }

        guard let item = AX.children(of: menu).first(where: { AX.title(of: $0) == target }) else {
            AX.cancel(menu)
            log("Signature '\(target)' not in popup for \(email) — is it attached to this account?")
            report("'\(target)' not in Signature menu for \(email)", failure: true)
            return .giveUp
        }

        AX.press(item)

        // A press on a found menu item is trusted — no synchronous
        // re-verification. Mail updates the popup's readable value on its
        // own (slow, unpredictable) schedule after a signature swap, so
        // verifying "too soon" reported phantom failures and triggered a
        // redundant second menu blink on every single From change. The
        // swallowed-press failure mode is already caught above (menu never
        // opened), and a delayed, blink-free post-apply check in tick()
        // covers the rare genuine miss.
        log("Applied '\(target)' for \(email)")
        onStatus?("Applied '\(target)' for \(email)")
        return .applied
    }

    // MARK: - Helpers

    /// Invisible Unicode formatting marks (bidi isolates etc.) that Mail
    /// wraps around addresses in some fields — they break string equality
    /// against the plain address from the config.
    nonisolated private static let formattingMarks = CharacterSet(charactersIn:
        "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")

    nonisolated static func cleanAddress(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { !formattingMarks.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }

    /// The address inside a Cc/To token's value. Mail renders a pill it has
    /// resolved against Contacts as "Name <addr>" (with bidi isolates around
    /// the address) and an unresolved one as the bare address, so the two
    /// forms have to be reduced to the same thing before they're compared.
    /// The brackets are the delimiter rather than "the word with an @",
    /// because a display name can contain one ("@dave <dave@example.com>").
    nonisolated static func tokenAddress(_ raw: String) -> String {
        let cleaned = cleanAddress(raw)
        if let open = cleaned.lastIndex(of: "<") {
            let rest = cleaned[cleaned.index(after: open)...]
            if let close = rest.firstIndex(of: ">") {
                return String(rest[..<close]).trimmingCharacters(in: .whitespaces)
            }
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "<>,").union(.whitespaces))
    }

    /// Extracts the address from From-popup values like
    /// "Dave Hamilton – dave@example.com" or "Name <dave@example.com>".
    nonisolated static func emailAddress(in sender: String) -> String? {
        for token in sender.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            guard token.contains("@") else { continue }
            // Strip the invisible marks *before* trimming punctuation, not
            // after. A mark sitting outside the bracket blocks the trim —
            // "\u{200E}<dave@example.com>" came back as "<dave@example.com",
            // which matches no mapping, so the alias silently got nothing.
            return cleanAddress(String(token))
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>,"))
        }
        return nil
    }

    private func log(_ message: String) {
        Log.engine.note(message)
    }
}

/// C callback for AXObserver — context comes back through refcon.
private let ottographAXCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let engine = Unmanaged<SignatureEngine>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String // CFString isn't Sendable; String is
    MainActor.assumeIsolated { engine.handleNotification(name) }
}

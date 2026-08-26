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
final class SignatureEngine {
    private let store: ConfigStore
    private var timer: Timer?
    private var lastSenderByWindow: [AXElementKey: String] = [:]
    private var retryState: [AXElementKey: (email: String, attempts: Int)] = [:]
    private var axApp: AXUIElement?
    private var axAppPID: pid_t = -1
    private var observer: AXObserver?

    private static let maxApplyAttempts = 4

    private(set) var isRunning = false

    /// Human-readable status for the menu bar UI.
    var onStatus: ((String) -> Void)?

    init(store: ConfigStore) {
        self.store = store
    }

    deinit {
        teardownObserver()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if !Self.ensureAccessibilityPermission() {
            onStatus?("Accessibility permission needed (System Settings → Privacy & Security → Accessibility)")
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = store.config.pollSeconds
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.tick()
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
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
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
            onStatus?("Accessibility permission needed (System Settings → Privacy & Security → Accessibility)")
            return
        }

        if axApp == nil || axAppPID != mail.processIdentifier {
            teardownObserver()
            axApp = AXUIElementCreateApplication(mail.processIdentifier)
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
            guard let compose = composePopups(in: window) else { continue }

            let key = AXElementKey(element: window)
            seenWindows.insert(key)
            observeFromPopup(compose.from)

            guard let senderValue = AX.stringValue(of: compose.from),
                  let email = Self.emailAddress(in: senderValue)?.lowercased() else { continue }

            guard email != lastSenderByWindow[key] else { continue }

            guard let signatureName = store.config.signatures[email] else {
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

            switch apply(signatureName: signatureName, to: compose.signature, in: window, forEmail: email) {
            case .applied, .giveUp:
                lastSenderByWindow[key] = email
                retryState[key] = nil
            case .retry:
                var state = retryState[key] ?? (email: email, attempts: 0)
                if state.email != email { state = (email: email, attempts: 0) }
                state.attempts += 1
                if state.attempts >= Self.maxApplyAttempts {
                    lastSenderByWindow[key] = email
                    retryState[key] = nil
                    onStatus?("Gave up applying signature for \(email)")
                    log("Gave up applying signature for \(email) after \(state.attempts) attempts")
                } else {
                    // Leave lastSenderByWindow unchanged so the next scan
                    // sees the same sender "change" and tries again.
                    retryState[key] = state
                    scheduleScan(after: 0.35)
                }
            }
        }

        // Forget windows that no longer exist.
        lastSenderByWindow = lastSenderByWindow.filter { seenWindows.contains($0.key) }
        retryState = retryState.filter { seenWindows.contains($0.key) }
    }

    // MARK: - Compose window discovery

    private struct ComposePopups {
        let from: AXUIElement
        let signature: AXUIElement
    }

    /// Roles we never need to descend into — prunes the (large) subtrees of
    /// the main viewer window and the compose body so scans stay cheap.
    private static let prunedRoles: Set<String> = [
        "AXTable", "AXOutline", "AXList", "AXWebArea",
        "AXStaticText", "AXTextArea", "AXImage", "AXMenu",
    ]

    /// Returns the From and Signature popups if this window is a compose
    /// window (i.e. it has a From popup), else nil.
    private func composePopups(in window: AXUIElement) -> ComposePopups? {
        var popups: [AXUIElement] = []
        collectPopups(in: window, depth: 0, into: &popups)
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

        guard let fromPopup, let signaturePopup else { return nil }
        return ComposePopups(from: fromPopup, signature: signaturePopup)
    }

    private func collectPopups(in element: AXUIElement, depth: Int, into popups: inout [AXUIElement]) {
        guard depth < 15 else { return }
        for child in AX.children(of: element) {
            let role = AX.role(of: child)
            if role == "AXPopUpButton" {
                popups.append(child)
                continue
            }
            if Self.prunedRoles.contains(role) { continue }
            collectPopups(in: child, depth: depth + 1, into: &popups)
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
            onStatus?("Signature menu didn't open — retrying")
            return .retry
        }

        guard let item = AX.children(of: menu).first(where: { AX.title(of: $0) == target }) else {
            AX.cancel(menu)
            log("Signature '\(target)' not in popup for \(email) — is it attached to this account?")
            onStatus?("'\(target)' not in Signature menu for \(email)")
            return .giveUp
        }

        AX.press(item)

        // Confirm the selection actually took before declaring victory.
        // Applying a signature makes Mail rebuild part of the compose
        // header, which can leave our held popup reference stale and
        // reading a phantom old value — so on a mismatch, re-discover the
        // popup and trust only a *fresh* read. Retrying on the stale read
        // caused a redundant second menu blink on every From change.
        usleep(150_000)
        if AX.stringValue(of: popup) == target {
            log("Applied '\(target)' for \(email)")
            onStatus?("Applied '\(target)' for \(email)")
            return .applied
        }
        if let freshValue = composePopups(in: window).map({ AX.stringValue(of: $0.signature) }),
           freshValue != nil, freshValue != target {
            onStatus?("Signature didn't take — retrying")
            return .retry
        }
        // Fresh read matches (or the window is mid-rebuild): the press on a
        // found menu item almost certainly landed. Don't blink again.
        log("Applied '\(target)' for \(email)")
        onStatus?("Applied '\(target)' for \(email)")
        return .applied
    }

    // MARK: - Helpers

    /// Extracts the address from From-popup values like
    /// "Dave Hamilton – dave@example.com" or "Name <dave@example.com>".
    static func emailAddress(in sender: String) -> String? {
        for token in sender.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            guard token.contains("@") else { continue }
            return token.trimmingCharacters(in: CharacterSet(charactersIn: "<>,"))
        }
        return nil
    }

    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(stamp)] \(message)")
    }
}

/// C callback for AXObserver — context comes back through refcon.
private let ottographAXCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let engine = Unmanaged<SignatureEngine>.fromOpaque(refcon).takeUnretainedValue()
    engine.handleNotification(notification as String)
}

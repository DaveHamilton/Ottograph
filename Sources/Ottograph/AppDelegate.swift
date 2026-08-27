import AppKit
import Carbon.HIToolbox
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private lazy var engine = SignatureEngine(store: store)
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private var sendDelayedItem: NSMenuItem?
    private var hotKey: HotKey?
    private var sendTakeoverHotKey: HotKey?
    private var settingsController: SettingsWindowController?

    /// Sparkle needs a real bundle to read SUFeedURL and SUPublicEDKey out
    /// of. `swift run` has no Info.plist at all, so the updater simply
    /// doesn't exist there rather than starting and failing at launch.
    private let updater: SPUStandardUpdaterController? = {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        toggleMenuItem.target = self
        toggleMenuItem.state = .on
        menu.addItem(toggleMenuItem)
        let sendItem = NSMenuItem(title: sendDelayedTitle, action: #selector(sendDelayed), keyEquivalent: "")
        sendItem.target = self
        menu.addItem(sendItem)
        sendDelayedItem = sendItem
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if let updater {
            let check = menu.addItem(
                withTitle: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            check.target = updater
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ottograph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        installEditMenu()

        engine.onStatus = { [weak self] status in
            self?.statusMenuItem.title = status
            self?.sendDelayedItem?.title = self?.sendDelayedTitle ?? "Send Delayed"
            self?.updateSendTakeover() // config may have hot-reloaded
        }
        engine.onFailure = { [weak self] message in
            guard let self, self.store.config.notifyFailures else { return }
            Notifier.post(title: "Ottograph", body: message)
        }
        Notifier.requestAuthorization()
        engine.start()

        // ⌃⌥⌘S — "send, but give me time to regret it"
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_S),
            carbonModifiers: UInt32(cmdKey | optionKey | controlKey)
        ) { [weak self] in
            self?.sendDelayed()
        }

        // Optional ⇧⌘D takeover: registered only while Mail is frontmost so
        // Mail's Send shortcut routes to delayed send without stealing ⇧⌘D
        // from any other app.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        updateSendTakeover()
    }

    @objc private func frontAppChanged(_ notification: Notification) {
        updateSendTakeover()
    }

    private func updateSendTakeover() {
        let mailIsFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.mail"
        if store.config.takeOverSend && mailIsFront {
            guard sendTakeoverHotKey == nil else { return }
            sendTakeoverHotKey = HotKey(
                keyCode: UInt32(kVK_ANSI_D),
                carbonModifiers: UInt32(cmdKey | shiftKey)
            ) { [weak self] in
                self?.sendDelayed()
            }
        } else {
            sendTakeoverHotKey = nil
        }
    }

    private var sendDelayedTitle: String {
        let seconds = store.config.sendDelay
        let amount = seconds.truncatingRemainder(dividingBy: 60) == 0
            ? "\(Int(seconds) / 60) Minute\(Int(seconds) / 60 == 1 ? "" : "s")"
            : "\(Int(seconds)) Seconds"
        return "Send in \(amount)  (⌃⌥⌘S)"
    }

    @objc private func sendDelayed() {
        DelayedSend.schedule(afterSeconds: store.config.sendDelay) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .scheduled(let when):
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let time = formatter.string(from: when)
                self.statusMenuItem.title = "Sending at \(time) — cancel in Send Later"
                print("[DelayedSend] scheduled for \(time)")
                if self.store.config.notifyScheduled {
                    Notifier.post(
                        title: "Scheduled, not sent",
                        body: "Sending at \(time). Open Mail's Send Later mailbox to edit or cancel."
                    )
                }
            case .failed(let message):
                self.statusMenuItem.title = message
                print("[DelayedSend] \(message)")
                if self.store.config.notifyFailures {
                    Notifier.post(title: "Ottograph couldn't schedule that message", body: message)
                }
            }
        }
    }

    @objc private func toggleEnabled() {
        if engine.isRunning {
            engine.stop()
            toggleMenuItem.state = .off
        } else {
            engine.start()
            toggleMenuItem.state = .on
        }
        // A paused Ottograph should look paused, not merely act paused.
        statusItem.button?.image = MenuBarIcon.make(paused: !engine.isRunning)
    }

    @objc private func showSettings() {
        if settingsController == nil {
            // Settings saves continuously, so this only refreshes what the
            // menu shows — it deliberately doesn't announce every save.
            settingsController = SettingsWindowController(store: store) { [weak self] in
                guard let self else { return }
                self.sendDelayedItem?.title = self.sendDelayedTitle
            }
        }
        settingsController?.show()
    }

    /// An accessory (menu bar only) app has no menu bar of its own, so
    /// nothing supplies the standard Edit-menu key equivalents and text
    /// fields in the Settings window can't cut/copy/paste/undo. Installing
    /// a main menu fixes that: it stays invisible under this activation
    /// policy, but its key equivalents are still dispatched down the
    /// responder chain.
    private func installEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}

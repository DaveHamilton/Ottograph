import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private lazy var engine = SignatureEngine(store: store)
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private var loginMenuItem: NSMenuItem?
    private var sendDelayedItem: NSMenuItem?
    private var hotKey: HotKey?
    private var sendTakeoverHotKey: HotKey?
    private var settingsController: SettingsWindowController?

    /// SMAppService (login items) only works from a real .app bundle,
    /// not when running the bare executable via `swift run`.
    private var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

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
        if isBundledApp {
            let item = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
            item.target = self
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(item)
            loginMenuItem = item
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
        DelayedSend.schedule(afterSeconds: store.config.sendDelay) { [weak self] status in
            self?.statusMenuItem.title = status
            print("[DelayedSend] \(status)")
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
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusMenuItem.title = "Login item error: \(error.localizedDescription)"
        }
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store) { [weak self] in
                guard let self else { return }
                self.sendDelayedItem?.title = self.sendDelayedTitle
                self.statusMenuItem.title = "Settings saved"
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

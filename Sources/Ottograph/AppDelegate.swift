import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private lazy var engine = SignatureEngine(store: store)
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "signature",
                accessibilityDescription: "Ottograph"
            )
        }

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        toggleMenuItem.target = self
        toggleMenuItem.state = .on
        menu.addItem(toggleMenuItem)
        menu.addItem(withTitle: "Open Config File", action: #selector(openConfig), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ottograph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        engine.onStatus = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        engine.start()
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

    @objc private func openConfig() {
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    @objc private func reloadConfig() {
        store.reloadIfChanged(force: true)
        statusMenuItem.title = "Config reloaded"
    }
}

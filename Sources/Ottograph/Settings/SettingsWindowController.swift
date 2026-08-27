import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in a plain NSWindow (the app uses the
/// AppKit lifecycle, so there's no SwiftUI Settings scene to lean on).
@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: SettingsModel

    init(store: ConfigStore, onSaved: @escaping () -> Void) {
        let model = SettingsModel(store: store)
        model.onSaved = onSaved
        self.model = model

        let host = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "Ottograph Settings"
        window.setContentSize(NSSize(width: 720, height: 600))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Re-reads the config so a reopened window shows current state, then
    /// refreshes the pickable lists from Mail (deferred so the window is
    /// on screen before any Automation permission prompt appears).
    func show() {
        model.load()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [model] in
            model.refreshFromMail()
        }
    }
}

import AppKit
import SwiftUI
import Sparkle

/// Hosts the SwiftUI settings view in a plain NSWindow (the app uses the
/// AppKit lifecycle, so there's no SwiftUI Settings scene to lean on).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel

    init(store: ConfigStore, updater: SPUUpdater?, onSaved: @escaping () -> Void) {
        let model = SettingsModel(store: store, updater: updater)
        model.onSaved = onSaved
        self.model = model

        let host = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "Ottograph Settings"
        window.setContentSize(NSSize(width: 720, height: 600))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
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

    /// Catches an edit that was typed but never committed — closing the
    /// window is as much a commit as tabbing out of the field.
    func windowWillClose(_ notification: Notification) {
        model.save()
    }
}

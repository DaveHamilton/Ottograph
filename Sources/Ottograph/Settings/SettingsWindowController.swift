import AppKit
import SwiftUI
import Sparkle

/// Hosts the SwiftUI settings view in a plain NSWindow (the app uses the
/// AppKit lifecycle, so there's no SwiftUI Settings scene to lean on).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    private let host: NSHostingController<SettingsView>
    private var hasSizedWindow = false

    init(store: ConfigStore, updater: SPUUpdater?, onSaved: @escaping () -> Void) {
        let model = SettingsModel(store: store, updater: updater)
        model.onSaved = onSaved
        self.model = model

        let host = NSHostingController(rootView: SettingsView(model: model))
        // The window's minimum tracks the view's, so it can't be shrunk to
        // where the content is clipped. That minimum is the layout with
        // the mapping list at its own minimum — the one thing that gives.
        host.sizingOptions = .minSize
        self.host = host
        let window = NSWindow(contentViewController: host)
        window.title = "Ottograph Settings"
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
        if !hasSizedWindow {
            // A fixed 720×600 used to be the opening size, and the content
            // had quietly outgrown it: the "Alias Mappings" heading and the
            // version line were cropped, one at each end. Measure the
            // height the content needs at this width instead — after
            // load(), so it's the mapping list being measured and not the
            // empty state — and open at that, or 600 if it needs less.
            let needed = host.sizeThatFits(in: NSSize(width: 720, height: 0))
            window?.setContentSize(NSSize(width: 720, height: max(600, needed.height.rounded(.up))))
            hasSizedWindow = true
        }
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

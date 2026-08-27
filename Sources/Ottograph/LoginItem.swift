import AppKit
import ServiceManagement

/// Start-at-login registration. This is a system-level action rather than a
/// value in Ottograph's config, which is why Settings applies it the moment
/// it's toggled instead of waiting for Save.
@MainActor
enum LoginItem {
    /// SMAppService needs a real .app bundle; `swift run` builds can't
    /// register themselves.
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        isSupported && SMAppService.mainApp.status == .enabled
    }

    /// No-op when already in the requested state, so re-syncing the UI
    /// can't cause a spurious register/unregister.
    static func set(_ enabled: Bool) throws {
        guard isSupported, enabled != isEnabled else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

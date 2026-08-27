import Foundation

/// Identifies a focusable field in the Settings window. Settings saves when
/// focus leaves a field (or on Return) rather than on every keystroke, so
/// a half-typed address is never written to the config.
enum SettingsField: Hashable {
    case alias(UUID)
    case signature(UUID)
    case autoCc(UUID)
    case pollSeconds
    case sendDelaySeconds
}

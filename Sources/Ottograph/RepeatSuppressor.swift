import Foundation

/// Drops a message that repeats inside `window`.
///
/// Both the log and the notifications need this, and for the same reason:
/// the engine re-evaluates every tick, so a condition that persists — a
/// missing Accessibility grant is the classic — reports itself once a
/// second for as long as it lasts. Unsuppressed that is ~1800 identical
/// lines per half hour, which is exactly the window Copy Diagnostics
/// captures, so the one feature meant to explain a problem would bury the
/// explanation under repetitions of it.
///
/// Repeats are dropped rather than counted: what matters is that the
/// condition is present and roughly when it started, and a line a minute
/// says that without crowding out everything around it.
struct RepeatSuppressor {
    private var lastSeen: [String: Date] = [:]
    let window: TimeInterval

    init(window: TimeInterval = 60) {
        self.window = window
    }

    /// True the first time a message is seen, and again once `window` has
    /// passed — so a persistent condition still leaves a heartbeat rather
    /// than falling silent and looking resolved.
    mutating func allows(_ message: String, now: Date = Date()) -> Bool {
        if let last = lastSeen[message], now.timeIntervalSince(last) < window {
            return false
        }
        lastSeen[message] = now
        return true
    }
}

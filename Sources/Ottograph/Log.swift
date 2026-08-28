import Foundation
import os

/// Diagnostics that survive a Finder launch.
///
/// `print()` writes to stdout, and an app launched from Finder has no
/// stdout — so every log line this app produced in normal use went
/// straight to /dev/null. That matters more here than in most apps:
/// Ottograph automates another app's interface, the README asks people to
/// report it when something looks wrong, and until now a report could only
/// ever be "it stopped working." Unified logging can be read after the
/// fact, by the user, on their own machine:
///
///     log show --last 1h --predicate 'subsystem == "com.davehamilton.Ottograph"'
///
/// Messages are logged `.public` deliberately. Unified logging redacts
/// interpolated strings by default, which would replace every alias and
/// signature name with `<private>` — exactly the words that make a report
/// actionable. What's logged is the user's own addresses, on the user's
/// own Mac, and never message content: the engine prunes `AXTextArea`
/// before it ever reaches a compose body.
struct Log {
    /// Falls back to a literal only for `swift run`, which has no bundle.
    /// Keeping the two in sync matters — the predicate above is what
    /// people will be asked to paste.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.davehamilton.Ottograph"

    /// A bare executable has no Console story and a terminal right there,
    /// so the dev loop keeps its stdout. The bundled app doesn't bother.
    private static let echoesToStdout = Bundle.main.bundleIdentifier == nil

    private let logger: os.Logger

    init(category: String) {
        logger = os.Logger(subsystem: Self.subsystem, category: category)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        echo(message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        echo(message)
    }

    private func echo(_ message: String) {
        guard Self.echoesToStdout else { return }
        // Built per line rather than cached: ISO8601DateFormatter isn't
        // Sendable, and this only runs in the dev loop.
        print("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
    }
}

extension Log {
    /// The signature/auto-Cc engine.
    static let engine = Log(category: "engine")
    /// Delayed send, which drives a different part of Mail entirely.
    static let send = Log(category: "send")
}

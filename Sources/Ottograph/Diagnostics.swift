import AppKit

/// Everything a useful bug report needs, on the clipboard in one click.
///
/// Ottograph drives another app's interface, so "it stopped working"
/// nearly always turns on details the user has no reason to know: which
/// macOS, which Mail, whether the Accessibility grant survived, and what
/// the engine actually logged before it gave up. Asking people to compose
/// a `log show` predicate themselves is asking too much, so this does it.
enum Diagnostics {
    /// The subsystem `Log` writes under — the two have to agree or this
    /// quietly returns an empty log, which is worse than no button at all.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.davehamilton.Ottograph"
    private static let window = "30m"

    static func report() async -> String {
        let header = """
        Ottograph \(versionDescription)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "NO — the engine can do nothing without it")
        Mail: \(mailDescription)

        Log, last \(window):
        """
        // `log show` reads the whole system log store and can take a few
        // seconds on a busy Mac — never on the main thread, which is also
        // serving the menu bar item this was clicked from.
        let body = await Task.detached(priority: .userInitiated) { recentLog() }.value
        return header + "\n" + body
    }

    private static var versionDescription: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return "(dev build — no bundle)" }
        return version
    }

    private static var mailDescription: String {
        guard let mail = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.mail").first else {
            return "not running"
        }
        let version = mail.bundleURL
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        return "running\(version.map { " (\($0))" } ?? "")"
    }

    /// Non-zero exit or missing output is reported rather than swallowed —
    /// an empty section reads as "nothing went wrong", which is a lie.
    private static func recentLog() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--last", window, "--style", "compact",
            "--predicate", "subsystem == \"\(subsystem)\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 {
                return "(log show exited \(process.terminationStatus))"
            }
            return text.isEmpty ? "(nothing logged in the last \(window))" : text
        } catch {
            return "(couldn't run log show: \(error.localizedDescription))"
        }
    }
}

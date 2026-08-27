import AppKit

/// Reads lists out of Mail (signature names, account addresses) via Apple
/// events, so Settings can offer them instead of making you type them.
/// This is the one place Ottograph uses Apple events — the engine itself
/// is pure Accessibility — so it's also the only thing that needs the
/// Automation permission, and it degrades to free-text entry without it.
enum MailIntrospection {
    enum Failure: Error {
        case mailNotRunning
        case notAuthorized
        case scriptError(Int)
    }

    static func signatureNames() throws -> [String] {
        try runListScript("""
        tell application "Mail"
            set out to {}
            repeat with s in signatures
                set end of out to (name of s)
            end repeat
            set AppleScript's text item delimiters to linefeed
            return out as text
        end tell
        """)
    }

    static func accountAddresses() throws -> [String] {
        try runListScript("""
        tell application "Mail"
            set out to {}
            repeat with acct in accounts
                try
                    set addrs to email addresses of acct
                    if addrs is not missing value then
                        repeat with a in addrs
                            set end of out to (a as text)
                        end repeat
                    end if
                end try
            end repeat
            set AppleScript's text item delimiters to linefeed
            return out as text
        end tell
        """)
    }

    /// Runs a script that returns newline-separated values; the result is
    /// de-duplicated (case-insensitively) and sorted.
    private static func runListScript(_ source: String) throws -> [String] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else {
            throw Failure.mailNotRunning
        }
        guard let script = NSAppleScript(source: source) else {
            throw Failure.scriptError(0)
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            throw code == -1743 ? Failure.notAuthorized : Failure.scriptError(code)
        }

        var seen = Set<String>()
        var values: [String] = []
        for line in (result.stringValue ?? "").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            values.append(trimmed)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

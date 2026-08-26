import Foundation

/// Ottograph's user configuration, stored as JSON in
/// ~/Library/Application Support/Ottograph/config.json
struct Config: Codable {
    /// How often (seconds) to check Mail's frontmost compose window.
    var pollSeconds: Double

    /// Map of From address (the alias) → Mail signature name.
    /// An empty string as the value means "remove the signature".
    var signatures: [String: String]

    /// Map of From address (the alias) → address to auto-add to Cc when
    /// that alias is selected. Optional so older configs keep working.
    var autoCc: [String: String]?

    static let defaultConfig = Config(
        pollSeconds: 1.0,
        signatures: [
            "you@example.com": "Signature Name As It Appears In Mail Settings",
            "alias@example.com": "Another Signature Name",
        ],
        autoCc: [
            "feedback@example.com": "you@example.com",
        ]
    )
}

final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ottograph", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("config.json")

    private(set) var config: Config = .defaultConfig
    private var lastModified: Date?

    init() {
        ensureFileExists()
        reloadIfChanged(force: true)
    }

    private func ensureFileExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Self.fileURL.path) else { return }
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Config.defaultConfig) {
            try? data.write(to: Self.fileURL)
        }
    }

    /// Reloads the config if the file's modification date changed.
    /// Returns true if a reload happened and parsed successfully.
    @discardableResult
    func reloadIfChanged(force: Bool = false) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path)
        let modified = attrs?[.modificationDate] as? Date
        guard force || modified != lastModified else { return false }
        lastModified = modified

        guard let data = try? Data(contentsOf: Self.fileURL),
              let parsed = try? JSONDecoder().decode(Config.self, from: data) else {
            return false
        }
        let normalized = Dictionary(
            parsed.signatures.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedCc = parsed.autoCc.map { cc in
            Dictionary(cc.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        config = Config(
            pollSeconds: max(0.25, parsed.pollSeconds),
            signatures: normalized,
            autoCc: normalizedCc
        )
        return true
    }
}

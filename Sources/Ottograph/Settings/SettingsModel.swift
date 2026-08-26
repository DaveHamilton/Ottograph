import AppKit
import Observation

/// Editable view-state for the Settings window, loaded from and saved back
/// to the JSON config. The signature column uses a UI convention: empty
/// text = "don't manage this alias's signature", the literal "None" =
/// "select the None signature" (stored as "" in the config).
@MainActor @Observable
final class SettingsModel {
    struct Row: Identifiable {
        let id = UUID()
        var alias = ""
        var signature = ""
        var autoCc = ""
    }

    var rows: [Row] = []
    var pollSeconds: Double = 1.0
    var sendDelaySeconds: Double = 120
    var signatureNames: [String] = []
    var signatureLoadStatus = ""
    var saveStatus = ""

    /// Called after a successful save so the app can refresh menu titles.
    var onSaved: (() -> Void)?

    private let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
        load()
    }

    func load() {
        store.reloadIfChanged(force: true)
        let config = store.config
        let ccMap = config.autoCc ?? [:]
        let aliases = Set(config.signatures.keys).union(ccMap.keys)
        rows = aliases.sorted().map { alias in
            let stored = config.signatures[alias]
            let uiSignature: String
            switch stored {
            case nil: uiSignature = ""
            case "": uiSignature = "None"
            case let name?: uiSignature = name
            }
            return Row(alias: alias, signature: uiSignature, autoCc: ccMap[alias] ?? "")
        }
        pollSeconds = config.pollSeconds
        sendDelaySeconds = config.sendDelay
        saveStatus = ""
    }

    func addRow() {
        rows.append(Row())
    }

    func removeRow(id: Row.ID) {
        rows.removeAll { $0.id == id }
    }

    func save() {
        var signatures: [String: String] = [:]
        var autoCc: [String: String] = [:]
        for row in rows {
            let alias = row.alias.trimmingCharacters(in: .whitespaces).lowercased()
            guard !alias.isEmpty else { continue }
            let signature = row.signature.trimmingCharacters(in: .whitespaces)
            if !signature.isEmpty {
                signatures[alias] = signature == "None" ? "" : signature
            }
            let cc = row.autoCc.trimmingCharacters(in: .whitespaces)
            if !cc.isEmpty {
                autoCc[alias] = cc
            }
        }
        let newConfig = Config(
            pollSeconds: max(0.25, pollSeconds),
            signatures: signatures,
            autoCc: autoCc.isEmpty ? nil : autoCc,
            sendDelaySeconds: sendDelaySeconds
        )
        do {
            try store.save(newConfig)
            saveStatus = "Saved — Ottograph is using the new settings"
            onSaved?()
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Reads signature names from Mail via Apple events. Optional
    /// convenience: needs the one-time Automation permission, and Mail
    /// must already be running (this never launches it).
    func loadSignaturesFromMail() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else {
            signatureLoadStatus = "Open Mail first"
            return
        }
        guard let script = NSAppleScript(source: #"tell application "Mail" to get name of every signature"#) else {
            return
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            signatureLoadStatus = code == -1743
                ? "Allow Ottograph → Mail in System Settings → Privacy & Security → Automation"
                : "Couldn't read signatures (error \(code))"
            return
        }
        var names: [String] = []
        var seen = Set<String>()
        if result.numberOfItems > 0 {
            for index in 1...result.numberOfItems {
                if let name = result.atIndex(index)?.stringValue, seen.insert(name).inserted {
                    names.append(name)
                }
            }
        } else if let single = result.stringValue, !single.isEmpty {
            names = [single]
        }
        signatureNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        signatureLoadStatus = "\(signatureNames.count) signature\(signatureNames.count == 1 ? "" : "s") loaded"
    }
}

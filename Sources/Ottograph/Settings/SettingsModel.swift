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
    var takeOverSend = false
    var notifyScheduled = false
    var notifyFailures = true

    /// Not part of the config file — a system registration, so it applies
    /// the moment it's toggled rather than waiting for Save.
    var startAtLogin = false
    var loginItemStatus = ""
    let loginItemSupported = LoginItem.isSupported
    var signatureNames: [String] = []
    var emailAddresses: [String] = []
    var mailLoadStatus = ""
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
        takeOverSend = config.takeOverSend
        notifyScheduled = config.notifyScheduled
        notifyFailures = config.notifyFailures
        startAtLogin = LoginItem.isEnabled
        loginItemStatus = ""
        saveStatus = ""
    }

    func addRow() {
        rows.append(Row())
    }

    /// Addresses offered in a row's alias picker: everything from Mail
    /// except aliases already claimed by *other* rows. (The auto-Cc picker
    /// stays unfiltered — the same address can be cc'd from many aliases.)
    func aliasChoices(for rowID: Row.ID) -> [String] {
        let taken = Set(
            rows.filter { $0.id != rowID }
                .map { $0.alias.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
        return emailAddresses.filter { !taken.contains($0.lowercased()) }
    }

    func removeRow(id: Row.ID) {
        rows.removeAll { $0.id == id }
    }

    func save() {
        var signatures: [String: String] = [:]
        var autoCc: [String: String] = [:]
        var seenAliases = Set<String>()
        var duplicates = Set<String>()
        for row in rows {
            let alias = row.alias.trimmingCharacters(in: .whitespaces).lowercased()
            guard !alias.isEmpty else { continue }
            if !seenAliases.insert(alias).inserted { duplicates.insert(alias) }
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
            sendDelaySeconds: sendDelaySeconds,
            takeOverSendShortcut: takeOverSend,
            notifyOnScheduledSend: notifyScheduled,
            notifyOnFailure: notifyFailures
        )
        do {
            try store.save(newConfig)
            // Deliberately no reload here: rows are sorted on load, and
            // re-sorting mid-edit would make them jump around while typing.
            saveStatus = duplicates.isEmpty
                ? "Changes are saved as you make them."
                : "\(duplicates.sorted().joined(separator: ", ")) is mapped more than once — only the last row for each counts."
            onSaved?()
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Applies the login-item toggle immediately (it isn't config data),
    /// re-syncing the checkbox if the system refuses.
    func applyLoginItem() {
        do {
            try LoginItem.set(startAtLogin)
            loginItemStatus = ""
        } catch {
            loginItemStatus = "Couldn't change login item: \(error.localizedDescription)"
            startAtLogin = LoginItem.isEnabled
        }
    }

    /// Pulls signature names and account addresses from Mail so both
    /// columns are pickable. Runs whenever the window opens; failures are
    /// non-fatal — the fields stay free-text.
    func refreshFromMail() {
        do {
            signatureNames = try MailIntrospection.signatureNames()
            emailAddresses = try MailIntrospection.accountAddresses()
            mailLoadStatus = "\(emailAddresses.count) addresses, \(signatureNames.count) signatures from Mail"
        } catch MailIntrospection.Failure.mailNotRunning {
            mailLoadStatus = "Open Mail and reopen Settings to pick from your addresses and signatures"
        } catch MailIntrospection.Failure.notAuthorized {
            mailLoadStatus = "Allow Ottograph → Mail in System Settings → Privacy & Security → Automation to pick from lists"
        } catch {
            mailLoadStatus = "Couldn't read Mail's addresses and signatures"
        }
    }
}

import AppKit
import Observation
import Sparkle

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

    /// Sparkle keeps this in its own UserDefaults, deliberately not in
    /// config.json: the engine hot-reloads that file and has no business
    /// knowing about updates, and a config write could stomp Sparkle's
    /// own state. Mirrored here so SwiftUI can observe it.
    var automaticUpdates = false
    var lastUpdateCheck: Date?

    /// Called after a successful save so the app can refresh menu titles.
    var onSaved: (() -> Void)?

    private let store: ConfigStore
    private let updater: SPUUpdater?

    /// No updater under `swift run` — there's no Info.plist for Sparkle to
    /// read a feed out of, so the whole section is hidden rather than
    /// shown as dead controls.
    var updatesSupported: Bool { updater != nil }

    init(store: ConfigStore, updater: SPUUpdater? = nil) {
        self.store = store
        self.updater = updater
        automaticUpdates = updater?.automaticallyChecksForUpdates ?? false
        lastUpdateCheck = updater?.lastUpdateCheckDate
        load()
    }

    func applyAutomaticUpdates() {
        updater?.automaticallyChecksForUpdates = automaticUpdates
    }

    /// Sparkle drives its own UI from here; the only thing to do
    /// afterwards is re-read the timestamp it stamps on completion.
    func checkForUpdatesNow() {
        guard let updater else { return }
        updater.checkForUpdates()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.lastUpdateCheck = updater.lastUpdateCheckDate
        }
    }

    var lastUpdateCheckDescription: String {
        guard let lastUpdateCheck else { return "never checked for updates" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "last checked \(formatter.localizedString(for: lastUpdateCheck, relativeTo: Date()))"
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

    /// Returns the new row's id so the view can scroll it into view.
    @discardableResult
    func addRow() -> Row.ID {
        let row = Row()
        rows.append(row)
        return row.id
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

    /// True when a row names a signature Mail doesn't have. A typo here
    /// would otherwise stay invisible until the alias is next used in a
    /// compose window, surfacing as a failure notification long after the
    /// mistake — with the list of real names sitting right there in the
    /// picker the whole time.
    ///
    /// Only meaningful once Mail's list has actually loaded: with Mail
    /// closed, or Automation declined, `signatureNames` is empty and every
    /// row would otherwise be flagged wrong.
    func namesUnknownSignature(_ row: Row) -> Bool {
        let name = row.signature.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "None", !signatureNames.isEmpty else { return false }
        return !signatureNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
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

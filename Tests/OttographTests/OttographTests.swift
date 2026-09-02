import Foundation
import Testing

@testable import Ottograph

// MARK: - Reading the sender out of Mail's From popup

@Test("From popup values yield the bare address")
func parsesSenderFormats() {
    #expect(SignatureEngine.emailAddress(in: "Dave Hamilton – dave@example.com") == "dave@example.com")
    #expect(SignatureEngine.emailAddress(in: "Dave Hamilton <dave@example.com>") == "dave@example.com")
    #expect(SignatureEngine.emailAddress(in: "dave@example.com") == "dave@example.com")
    #expect(SignatureEngine.emailAddress(in: "Dave, Hamilton <dave@example.com>,") == "dave@example.com")
}

@Test("A From value with no address yields nil rather than nonsense")
func rejectsNonAddresses() {
    #expect(SignatureEngine.emailAddress(in: "") == nil)
    #expect(SignatureEngine.emailAddress(in: "No Address Here") == nil)
}

@Test("Bidi marks Mail wraps around stored addresses are stripped")
func stripsFormattingMarks() {
    // Mail hands these back around addresses in token fields. Left in,
    // they break equality against the plain address from the config —
    // which is what made auto-Cc add a duplicate on every re-switch.
    let wrapped = "\u{2068}dave@example.com\u{2069}"
    #expect(SignatureEngine.cleanAddress(wrapped) == "dave@example.com")
    #expect(SignatureEngine.cleanAddress("  dave@example.com  ") == "dave@example.com")
    #expect(SignatureEngine.emailAddress(in: "Dave \u{200E}<dave@example.com>") == "dave@example.com")
}


// MARK: - Reading a Cc pill

@Test("A Contacts-resolved Cc pill reduces to the same address as a bare one")
func parsesCcTokenFormats() {
    // Mail renders a pill it resolved against Contacts as "Name <addr>",
    // with bidi isolates around the address, and an unresolved one as the
    // bare address. Comparing those strings whole made an address that was
    // already in the field look missing, so auto-Cc re-added it — and the
    // rewrite folded the pill's name into the next recipient, leaving
    // "Otto Graph , otto@example.com <otto@example.com>".
    #expect(SignatureEngine.tokenAddress("otto@example.com") == "otto@example.com")
    #expect(SignatureEngine.tokenAddress("Otto Graph <otto@example.com>") == "otto@example.com")
    #expect(
        SignatureEngine.tokenAddress("Otto Graph <\u{2066}otto@example.com\u{2069}>")
            == "otto@example.com"
    )
    #expect(SignatureEngine.tokenAddress("  \u{2068}otto@example.com\u{2069}  ") == "otto@example.com")
}

@Test("A display name containing an @ doesn't get mistaken for the address")
func tokenAddressPrefersTheBrackets() {
    #expect(SignatureEngine.tokenAddress("@otto <otto@example.com>") == "otto@example.com")
    #expect(SignatureEngine.tokenAddress("Otto <Graph> <otto@example.com>") == "otto@example.com")
}

@Test("A pill with nothing bracketed falls back to the whole cleaned value")
func tokenAddressFallsBack() {
    #expect(SignatureEngine.tokenAddress("Otto Graph") == "Otto Graph")
    #expect(SignatureEngine.tokenAddress("<otto@example.com>,") == "otto@example.com")
    #expect(SignatureEngine.tokenAddress("") == "")
}

// MARK: - Config

@Test("Optional settings absent from an older config fall back, not crash")
func decodesConfigWithoutOptionals() throws {
    let json = Data("""
    {"pollSeconds": 1.0, "signatures": {"dave@example.com": "Work"}}
    """.utf8)
    let config = try JSONDecoder().decode(Config.self, from: json)
    #expect(config.signatures["dave@example.com"] == "Work")
    #expect(config.autoCc == nil)
    #expect(config.sendDelay == 120)
    #expect(config.takeOverSend == false)
    #expect(config.notifyFailures == true)      // on by default
    #expect(config.notifyScheduled == false)    // off by default
}

@Test("The delayed-send window can't be set short enough to be useless")
func clampsSendDelay() throws {
    var config = Config.defaultConfig
    config.sendDelaySeconds = 1
    #expect(config.sendDelay == 10)
    config.sendDelaySeconds = 600
    #expect(config.sendDelay == 600)
}

@Test("A fresh install starts genuinely empty")
func defaultConfigIsEmpty() {
    #expect(Config.defaultConfig.signatures.isEmpty)
    #expect(Config.defaultConfig.autoCc == nil)
}

@Test("Addresses are matched case-insensitively via normalisation on load")
func normalisesAddressCase() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let json = Data("""
    {"pollSeconds": 0.01,
     "signatures": {"Dave@Example.COM": "Work"},
     "autoCc": {"Dave@Example.COM": "team@example.com"}}
    """.utf8)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try json.write(to: directory.appendingPathComponent("config.json"))

    let store = ConfigStore(directory: directory)
    #expect(store.config.signatures["dave@example.com"] == "Work")
    #expect(store.config.autoCc?["dave@example.com"] == "team@example.com")
    // Scanning faster than this would be all cost and no benefit.
    #expect(store.config.pollSeconds == 0.25)
}

@Test("A saved config survives the round trip through disk")
func roundTripsThroughDisk() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ConfigStore(directory: directory)
    var config = Config.defaultConfig
    config.signatures = ["dave@example.com": "Work", "otto@example.com": ""]
    config.autoCc = ["dave@example.com": "team@example.com"]
    try store.save(config)

    let reopened = ConfigStore(directory: directory)
    #expect(reopened.config.signatures["dave@example.com"] == "Work")
    // The empty string is load-bearing: it means "apply None", which is
    // not the same as having no mapping at all.
    #expect(reopened.config.signatures["otto@example.com"] == "")
    #expect(reopened.config.autoCc?["dave@example.com"] == "team@example.com")
}

// MARK: - Settings ↔ config conversion

/// The UI says "None"; the config stores "". An empty *field* means
/// something different again — don't manage this alias's signature at all.
/// Three states across two representations, converted in both directions,
/// and a regression here is silent: the config still parses, it just stops
/// meaning what the user chose.
@MainActor
@Test("None, empty, and a real name survive a Settings round trip")
func settingsRoundTripsSignatureStates() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ConfigStore(directory: directory)
    let model = SettingsModel(store: store)
    model.rows = [
        SettingsModel.Row(alias: "work@example.com", signature: "Work", autoCc: ""),
        SettingsModel.Row(alias: "none@example.com", signature: "None", autoCc: ""),
        SettingsModel.Row(alias: "cconly@example.com", signature: "", autoCc: "team@example.com"),
    ]
    model.save()

    #expect(store.config.signatures["work@example.com"] == "Work")
    #expect(store.config.signatures["none@example.com"] == "")
    #expect(store.config.signatures["cconly@example.com"] == nil)
    #expect(store.config.autoCc?["cconly@example.com"] == "team@example.com")

    let reloaded = SettingsModel(store: store)
    let byAlias = Dictionary(uniqueKeysWithValues: reloaded.rows.map { ($0.alias, $0) })
    #expect(byAlias["work@example.com"]?.signature == "Work")
    #expect(byAlias["none@example.com"]?.signature == "None")
    #expect(byAlias["cconly@example.com"]?.signature == "")
    #expect(byAlias["cconly@example.com"]?.autoCc == "team@example.com")
}

@MainActor
@Test("Aliases are lowercased and trimmed on save")
func settingsNormalisesAliases() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = SettingsModel(store: ConfigStore(directory: directory))
    model.rows = [SettingsModel.Row(alias: "  Dave@Example.COM ", signature: " Work ", autoCc: "")]
    model.save()
    #expect(model.rows.count == 1)
    #expect(ConfigStore(directory: directory).config.signatures["dave@example.com"] == "Work")
}

@MainActor
@Test("An alias claimed by one row is not offered to another")
func aliasPickerExcludesTakenAddresses() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = SettingsModel(store: ConfigStore(directory: directory))
    model.emailAddresses = ["dave@example.com", "otto@example.com"]
    model.rows = [
        SettingsModel.Row(alias: "dave@example.com"),
        SettingsModel.Row(alias: ""),
    ]
    #expect(model.aliasChoices(for: model.rows[1].id) == ["otto@example.com"])
    // Its own address stays in its own list, or picking it again is
    // impossible after a stray edit.
    #expect(model.aliasChoices(for: model.rows[0].id).contains("dave@example.com"))
}

@MainActor
@Test("A signature name Mail doesn't have is flagged — but only once Mail has been read")
func flagsUnknownSignatureNames() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let model = SettingsModel(store: ConfigStore(directory: directory))
    let typo = SettingsModel.Row(alias: "dave@example.com", signature: "Wrok")

    // Mail not read yet: flagging everything would be noise, not help.
    #expect(model.namesUnknownSignature(typo) == false)

    model.signatureNames = ["Work", "Personal"]
    #expect(model.namesUnknownSignature(typo) == true)
    #expect(model.namesUnknownSignature(SettingsModel.Row(signature: "Work")) == false)
    #expect(model.namesUnknownSignature(SettingsModel.Row(signature: "work")) == false)
    #expect(model.namesUnknownSignature(SettingsModel.Row(signature: "")) == false)
    // "None" is Ottograph's own word for the Mail menu item, not a
    // signature Mail would ever list.
    #expect(model.namesUnknownSignature(SettingsModel.Row(signature: "None")) == false)
}

// MARK: - Repeat suppression

/// The engine re-evaluates every tick, so a condition that persists reports
/// itself once a second. Copy Diagnostics captures a 30-minute window, so
/// unsuppressed that is ~1800 identical lines burying whatever else is in
/// there — the failure mode this exists to prevent.
@Test("A repeated message is dropped inside the window and allowed after it")
func suppressesRepeats() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var suppressor = RepeatSuppressor(window: 60)
    // Bound to locals because #expect wraps its expression in a closure
    // with an immutable capture, so it can't call a mutating method.
    let first = suppressor.allows("needs Accessibility", now: start)
    let afterASecond = suppressor.allows("needs Accessibility", now: start.addingTimeInterval(1))
    let justInside = suppressor.allows("needs Accessibility", now: start.addingTimeInterval(59))
    let atTheWindow = suppressor.allows("needs Accessibility", now: start.addingTimeInterval(60))
    let justAfter = suppressor.allows("needs Accessibility", now: start.addingTimeInterval(61))

    #expect(first)
    #expect(afterASecond == false)
    #expect(justInside == false)
    // A persistent condition still leaves a heartbeat: falling permanently
    // silent would read as resolved.
    #expect(atTheWindow)
    #expect(justAfter == false)
}

@Test("Different messages don't suppress each other")
func suppressesPerMessage() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var suppressor = RepeatSuppressor(window: 60)
    let accessibility = suppressor.allows("needs Accessibility", now: start)
    let signature = suppressor.allows("'BBM Shorts' not in Signature menu", now: start)
    let accessibilityAgain = suppressor.allows("needs Accessibility", now: start.addingTimeInterval(1))

    #expect(accessibility)
    #expect(signature)
    #expect(accessibilityAgain == false)
}

// MARK: -

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ottograph-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Recognising the compose window's controls

// These attribute values are copied from `Scripts/ax-probe.swift` run
// against Mail 16.0 with the Format bar showing — the configuration that
// produced the first bug report.

@Test("Compose controls are recognised by their AXIdentifier")
func classifiesByIdentifier() {
    #expect(ComposeControl.classify(identifier: "popup_from", label: nil) == .from)
    #expect(ComposeControl.classify(identifier: "popup_signature", label: nil) == .signature)
    #expect(ComposeControl.classify(identifier: "Mail.ccField", label: nil) == .cc)
    #expect(ComposeControl.classify(identifier: "Mail.subjectField", label: nil) == .subject)
    // Real controls we don't drive must not be mistaken for ones we do.
    #expect(ComposeControl.classify(identifier: "popup_priority", label: nil) == nil)
    #expect(ComposeControl.classify(identifier: "Mail.toField", label: nil) == nil)
    #expect(ComposeControl.classify(identifier: "Mail.bccField", label: nil) == nil)
    #expect(ComposeControl.classify(identifier: "Mail.replyToField", label: nil) == nil)
}

@Test("Without identifiers, the label element identifies the control")
func classifiesByLabel() {
    #expect(ComposeControl.classify(identifier: nil, label: "From:") == .from)
    #expect(ComposeControl.classify(identifier: nil, label: "Signature:") == .signature)
    #expect(ComposeControl.classify(identifier: nil, label: "Cc:") == .cc)
    #expect(ComposeControl.classify(identifier: nil, label: "Subject:") == .subject)
    #expect(ComposeControl.classify(identifier: nil, label: "To:") == nil)
}

@Test("The Format bar's popups are not the Signature popup")
func ignoresFormatBarPopups() {
    // Font, style and size: no identifier, no label, a value that isn't
    // an address. The old rule took the first of these as the Signature
    // popup, pressed it, and reported the signature missing from the
    // account. They sit before the header controls in the tree, so
    // "first match wins" made this the common case, not the rare one.
    #expect(ComposeControl.classify(identifier: nil, label: nil) == nil)
    #expect(ComposeControl.classify(identifier: nil, label: "") == nil)
}

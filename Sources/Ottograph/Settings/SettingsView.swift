import SwiftUI

/// Settings apply as you make them — Mac preferences don't have a Save
/// button. Toggles and picker choices save on the spot; text fields save
/// when you press Return or move focus away, so a half-typed address is
/// never written to the config (the engine reads that file live).
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @FocusState private var focused: SettingsField?
    /// The row just added, until the list has scrolled to it.
    @State private var rowToReveal: SettingsModel.Row.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alias Mappings")
                .font(.headline)
            Text("Each row maps a From address to the signature Ottograph applies when you pick it, plus an optional address to add to Cc. Leave the signature blank to manage only the Cc; enter “None” to remove the signature for that alias.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.rows.isEmpty {
                ContentUnavailableView {
                    Label("No aliases mapped yet", systemImage: "signature")
                } description: {
                    Text("Add a mapping for each From address that should get its own signature. With Mail running, your addresses and signature names appear as pickers.")
                } actions: {
                    Button("Add Mapping", systemImage: "plus") { _ = model.addRow() }
                }
                .frame(minHeight: 180)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach($model.rows) { $row in
                            MappingRowView(
                                row: $row,
                                signatureNames: model.signatureNames,
                                aliasChoices: model.aliasChoices(for: row.id),
                                ccChoices: model.emailAddresses,
                                signatureIsUnknown: model.namesUnknownSignature(row),
                                focused: $focused,
                                onCommit: model.save,
                                onDelete: {
                                    model.removeRow(id: row.id)
                                    model.save()
                                }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 180)
                    .onChange(of: rowToReveal) { _, id in
                        // A row added below the fold used to appear nowhere:
                        // the list stayed scrolled to the top and the new,
                        // empty row was out of sight. Bring it into view.
                        // Deferred a turn so the row exists in the list
                        // before we ask to scroll to it.
                        guard let id else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(id, anchor: .bottom)
                            // The list estimates the height of a row it
                            // hasn't laid out yet, so that first scroll
                            // lands with the new row just past the fold.
                            // Now that it's on screen and measured, once
                            // more lands it.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                                rowToReveal = nil
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Add Mapping", systemImage: "plus") {
                    rowToReveal = model.addRow()
                }
                Text(model.mailLoadStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Fallback scan interval:")
                    TextField("seconds", value: $model.pollSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .focused($focused, equals: .pollSeconds)
                        .onSubmit(model.save)
                    Text("seconds (event-driven reactions are instant; this is the safety net)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Delayed-send window:")
                    TextField("seconds", value: $model.sendDelaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .focused($focused, equals: .sendDelaySeconds)
                        .onSubmit(model.save)
                    Text("seconds before a ⌃⌥⌘S message actually sends")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $model.takeOverSend) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take over Mail's Send shortcut (⇧⌘D)")
                    Text("While Mail is frontmost, ⇧⌘D triggers delayed send instead of sending immediately. Outside a compose window it still does what Mail does — Message > Send Again. ⌃⌥⌘S always works; Send in the toolbar and Message menu still sends now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: model.takeOverSend) { model.save() }

            Toggle("Notify when something goes wrong", isOn: $model.notifyFailures)
                .onChange(of: model.notifyFailures) { model.save() }
            Toggle("Notify when a message is scheduled instead of sent", isOn: $model.notifyScheduled)
                .onChange(of: model.notifyScheduled) { model.save() }

            Toggle("Start Ottograph at login", isOn: $model.startAtLogin)
                .disabled(!model.loginItemSupported)
                .onChange(of: model.startAtLogin) { model.applyLoginItem() }

            // Footer for the settings above, and only those: it belongs
            // under what it describes. Below the updates section it would
            // read as covering the auto-update toggle, which is the one
            // control here that doesn't go through the config file at all.
            HStack(alignment: .firstTextBaseline) {
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Only as a fallback: an unbundled build has no updater, so
                // the section below is hidden and the version would
                // otherwise not appear anywhere.
                if !model.updatesSupported {
                    Spacer(minLength: 12)
                    Text(versionLine)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            if model.updatesSupported {
                Divider()

                // The manual check lives in the menu bar menu too — that's
                // the app menu for a menu-bar-only app, and where macOS
                // users look for it. This pairing is the settings half of
                // the convention: the preference, plus enough state that
                // the button isn't just a duplicate command.
                HStack(alignment: .firstTextBaseline) {
                    Toggle("Automatically check for updates", isOn: $model.automaticUpdates)
                        .onChange(of: model.automaticUpdates) { model.applyAutomaticUpdates() }
                    Spacer(minLength: 12)
                    Button("Check Now", action: model.checkForUpdatesNow)
                }
                // What you're running and how current it is are the same
                // question, so they share a line rather than sitting in
                // opposite corners.
                Text("\(versionLine) — \(model.lastUpdateCheckDescription)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        // Width only. A minHeight here doesn't mean "at least as tall as
        // the content": the frame clamps the *proposal* and reports that,
        // so a content that needs more overflows and is clipped at both
        // ends — and every measurement of the view reports the clamp. The
        // content's real minimum comes from the mapping list at its own
        // minimum, which the window controller measures.
        .frame(minWidth: 680)
        .onChange(of: focused) { previous, _ in
            // Leaving a field commits it. Saving here rather than on every
            // keystroke keeps partial text out of the config — which
            // matters because the engine would otherwise try to apply a
            // half-typed signature name and report it as a failure.
            if previous != nil { model.save() }
        }
    }

    private var statusLine: String {
        if !model.loginItemStatus.isEmpty { return model.loginItemStatus }
        if !model.saveStatus.isEmpty { return model.saveStatus }
        return model.loginItemSupported
            ? "Changes are saved as you make them."
            : "Changes are saved as you make them. Start at login needs Ottograph installed as an app (Scripts/build-app.sh --install)."
    }

    /// Only a bundled build has an Info.plist to read a version out of.
    /// `swift run` says so rather than showing a blank or inventing one —
    /// and knowing which of the two you're looking at matters when a bug
    /// report says "latest".
    private var versionLine: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return "Ottograph — dev build" }
        return "Ottograph \(version)"
    }
}

import SwiftUI

/// Settings apply as you make them — Mac preferences don't have a Save
/// button. Toggles and picker choices save on the spot; text fields save
/// when you press Return or move focus away, so a half-typed address is
/// never written to the config (the engine reads that file live).
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @FocusState private var focused: SettingsField?

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
                    Button("Add Mapping", systemImage: "plus", action: model.addRow)
                }
                .frame(minHeight: 180)
            } else {
                List {
                    ForEach($model.rows) { $row in
                        MappingRowView(
                            row: $row,
                            signatureNames: model.signatureNames,
                            aliasChoices: model.aliasChoices(for: row.id),
                            ccChoices: model.emailAddresses,
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
            }

            HStack {
                Button("Add Mapping", systemImage: "plus", action: model.addRow)
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
                    Text("While Mail is frontmost, ⇧⌘D triggers delayed send instead of sending immediately. ⌃⌥⌘S always works; Send in the toolbar and Message menu still sends now.")
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

            Divider()

            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 560)
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
}

import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alias Mappings")
                .font(.headline)
            Text("Each row maps a From address to the signature Ottograph applies when you pick it, plus an optional address to add to Cc. Leave the signature blank to manage only the Cc; enter “None” to remove the signature for that alias.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($model.rows) { $row in
                    MappingRowView(
                        row: $row,
                        signatureNames: model.signatureNames,
                        aliasChoices: model.aliasChoices(for: row.id),
                        ccChoices: model.emailAddresses
                    ) {
                        model.removeRow(id: row.id)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 180)

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
                    Text("seconds (event-driven reactions are instant; this is the safety net)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Delayed-send window:")
                    TextField("seconds", value: $model.sendDelaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
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

            Toggle("Notify when something goes wrong", isOn: $model.notifyFailures)
            Toggle("Notify when a message is scheduled instead of sent", isOn: $model.notifyScheduled)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Start Ottograph at login", isOn: $model.startAtLogin)
                    .disabled(!model.loginItemSupported)
                    .onChange(of: model.startAtLogin) {
                        model.applyLoginItem()
                    }
                Text(loginItemNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text(model.saveStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Revert", action: model.load)
                Button("Save", action: model.save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 560)
    }

    /// Start at login is a system registration rather than a config value,
    /// so unlike everything above it, it doesn't wait for Save.
    private var loginItemNote: String {
        if !model.loginItemStatus.isEmpty { return model.loginItemStatus }
        return model.loginItemSupported
            ? "Takes effect immediately — the settings above apply when you click Save."
            : "Available once Ottograph is running as an installed app (Scripts/build-app.sh --install)."
    }
}

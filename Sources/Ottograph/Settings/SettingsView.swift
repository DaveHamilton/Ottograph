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
                    MappingRowView(row: $row, signatureNames: model.signatureNames) {
                        model.removeRow(id: row.id)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 180)

            HStack {
                Button("Add Mapping", systemImage: "plus", action: model.addRow)
                Button("Load Signature Names from Mail", action: model.loadSignaturesFromMail)
                Text(model.signatureLoadStatus)
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
        .frame(minWidth: 680, minHeight: 440)
    }
}

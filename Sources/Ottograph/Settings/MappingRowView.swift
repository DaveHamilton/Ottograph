import SwiftUI

/// One editable alias mapping: From address, signature, optional auto-Cc.
struct MappingRowView: View {
    @Binding var row: SettingsModel.Row
    let signatureNames: [String]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("alias@example.com", text: $row.alias)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 190)

            HStack(spacing: 2) {
                TextField("Signature name", text: $row.signature)
                    .textFieldStyle(.roundedBorder)
                if !signatureNames.isEmpty {
                    Menu {
                        Button("None (remove signature)") { row.signature = "None" }
                        Divider()
                        ForEach(signatureNames, id: \.self) { name in
                            Button(name) { row.signature = name }
                        }
                    } label: {
                        Label("Choose signature", systemImage: "chevron.up.chevron.down")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .frame(minWidth: 180)

            TextField("Auto-Cc (optional)", text: $row.autoCc)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 170)

            Button("Remove mapping", systemImage: "minus.circle.fill", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

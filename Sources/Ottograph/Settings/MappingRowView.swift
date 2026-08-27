import SwiftUI

/// One editable alias mapping: From address, signature, optional auto-Cc.
/// Each field is free-text with an optional picker of values read from Mail.
struct MappingRowView: View {
    @Binding var row: SettingsModel.Row
    let signatureNames: [String]
    /// Mail's addresses minus those already mapped in other rows.
    let aliasChoices: [String]
    /// All of Mail's addresses — the same one may be cc'd from many aliases.
    let ccChoices: [String]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PickableField(
                text: $row.alias,
                prompt: "alias@example.com",
                choices: aliasChoices,
                pickerLabel: "Choose address"
            )
            .frame(minWidth: 190)

            PickableField(
                text: $row.signature,
                prompt: "Signature name",
                choices: signatureNames,
                pickerLabel: "Choose signature",
                extraChoice: ("None (remove signature)", "None")
            )
            .frame(minWidth: 180)

            PickableField(
                text: $row.autoCc,
                prompt: "Auto-Cc (optional)",
                choices: ccChoices,
                pickerLabel: "Choose Cc address"
            )
            .frame(minWidth: 170)

            Button("Remove mapping", systemImage: "minus.circle.fill", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

/// A text field with a dropdown of known values beside it. The field stays
/// editable — the picker is a shortcut, not a constraint.
private struct PickableField: View {
    @Binding var text: String
    let prompt: String
    let choices: [String]
    let pickerLabel: String
    var extraChoice: (label: String, value: String)?

    var body: some View {
        HStack(spacing: 2) {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
            if !choices.isEmpty || extraChoice != nil {
                Menu {
                    if let extraChoice {
                        Button(extraChoice.label) { text = extraChoice.value }
                        Divider()
                    }
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { text = choice }
                    }
                } label: {
                    Label(pickerLabel, systemImage: "chevron.up.chevron.down")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

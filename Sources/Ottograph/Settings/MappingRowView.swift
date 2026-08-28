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
    /// Mail has no signature by this name — flagged here, where the typo
    /// happened, rather than as a notification at compose time.
    let signatureIsUnknown: Bool
    @FocusState.Binding var focused: SettingsField?
    /// Called for discrete edits (picking from a menu, pressing Return)
    /// that should save without waiting for focus to move.
    let onCommit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PickableField(
                text: $row.alias,
                prompt: "alias@example.com",
                choices: aliasChoices,
                pickerLabel: "Choose address",
                field: .alias(row.id),
                focused: $focused,
                onCommit: onCommit
            )
            .frame(minWidth: 190)

            PickableField(
                text: $row.signature,
                prompt: "Signature name",
                choices: signatureNames,
                pickerLabel: "Choose signature",
                field: .signature(row.id),
                focused: $focused,
                onCommit: onCommit,
                extraChoice: ("None (remove signature)", "None")
            )
            .frame(minWidth: 180)

            // Always in the layout, only sometimes visible: appearing and
            // disappearing would shift the Cc field sideways mid-edit.
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .opacity(signatureIsUnknown ? 1 : 0)
                .help("Mail has no signature named “\(row.signature.trimmingCharacters(in: .whitespaces))”. Pick one from the list — and note it has to be attached to this alias's account to be applied.")
                .accessibilityHidden(!signatureIsUnknown)
                .accessibilityLabel("Unknown signature name")

            PickableField(
                text: $row.autoCc,
                prompt: "Auto-Cc (optional)",
                choices: ccChoices,
                pickerLabel: "Choose Cc address",
                field: .autoCc(row.id),
                focused: $focused,
                onCommit: onCommit
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
    let field: SettingsField
    @FocusState.Binding var focused: SettingsField?
    let onCommit: () -> Void
    var extraChoice: (label: String, value: String)?

    var body: some View {
        HStack(spacing: 2) {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: field)
                .onSubmit(onCommit)
            if !choices.isEmpty || extraChoice != nil {
                Menu {
                    if let extraChoice {
                        Button(extraChoice.label) { select(extraChoice.value) }
                        Divider()
                    }
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { select(choice) }
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

    private func select(_ value: String) {
        text = value
        onCommit()
    }
}

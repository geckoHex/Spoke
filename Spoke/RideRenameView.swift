import SwiftUI

struct RideRenameView: View {
    @Binding var name: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename Ride")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Ride name")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpokeStyle.secondaryText)
                HStack {
                    TextField("", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            isNameFocused = false
                            save()
                        }
                        .accessibilityLabel("Ride name")

                    if isNameFocused && !name.isEmpty {
                        Button {
                            name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SpokeStyle.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear ride name")
                    }
                }
                .padding(12)
                .background(SpokeStyle.elevatedSurface, in: .rect(cornerRadius: 8))
            }

            Button("Save", action: save)
                .buttonStyle(SpokePrimaryButtonStyle())
                .disabled(!canSave)

            Button("Cancel") { dismiss() }
                .buttonStyle(SpokeSecondaryButtonStyle())
        }
        .foregroundStyle(SpokeStyle.text)
        .padding(24)
        .background {
            SpokeStyle.surface
                .ignoresSafeArea()
                .onTapGesture { isNameFocused = false }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(SpokeStyle.surface)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard canSave else { return }
        onSave()
        dismiss()
    }
}

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
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Ride name")
                    .font(.subheadline)
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
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear ride name")
                    }
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 8))
            }

            Button("Save", action: save)
                .buttonStyle(SpokePrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)

            Button("Cancel") { dismiss() }
                .buttonStyle(SpokePrimaryButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(24)
        .background {
            Color(uiColor: .secondarySystemBackground)
                .ignoresSafeArea()
                .onTapGesture { isNameFocused = false }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard canSave else { return }
        onSave()
        dismiss()
    }
}

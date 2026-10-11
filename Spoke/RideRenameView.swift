import SwiftUI

struct RideRenameView: View {
    @Binding var name: String
    let onSave: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var hasSaveError = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SpokeSheet(title: "Rename Ride") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ride name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SpokeStyle.secondaryText)

                    HStack {
                        TextField("", text: $name)
                            .focused($isNameFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { isNameFocused = false }
                            .accessibilityLabel("Ride name")

                        if isNameFocused && !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(SpokeStyle.secondaryText)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear ride name")
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                    .frame(minHeight: 52)
                    .background(SpokeStyle.elevatedSurface, in: .rect(cornerRadius: SpokeStyle.controlRadius))
                }

                Button("Save", action: save)
                    .buttonStyle(SpokePrimaryButtonStyle())
                    .disabled(!canSave)
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.vertical, 12)
            .background {
                SpokeStyle.surface
                    .onTapGesture { isNameFocused = false }
            }
        }
        .background {
            SpokeStyle.surface
                .onTapGesture { isNameFocused = false }
        }
        .alert("Name wasn’t saved", isPresented: $hasSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your changes are still here. Please try saving again.")
        }
    }

    private func save() {
        guard canSave else { return }
        if onSave() { dismiss() }
        else { hasSaveError = true }
    }
}

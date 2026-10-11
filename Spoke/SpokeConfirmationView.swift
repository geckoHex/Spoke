import SwiftUI

struct SpokeConfirmationView: View {
    let title: String
    let message: String
    let actionTitle: String
    let onConfirm: () -> Bool
    @State private var hasSaveError = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SpokeSheet(title: title) {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .font(.body)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    Button(actionTitle, role: .destructive) {
                        if onConfirm() { dismiss() }
                        else { hasSaveError = true }
                    }
                    .buttonStyle(SpokePrimaryButtonStyle())

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SpokeSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.vertical, 12)
        }
        .alert("Ride wasn’t deleted", isPresented: $hasSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your ride is still saved. Please try again.")
        }
    }
}

import SwiftUI

struct SpokeConfirmationView: View {
    let title: String
    let message: String
    let actionTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Button(actionTitle, role: .destructive) {
                dismiss()
                onConfirm()
            }
            .buttonStyle(SpokePrimaryButtonStyle())

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SpokePrimaryButtonStyle())
        }
        .foregroundStyle(.white)
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

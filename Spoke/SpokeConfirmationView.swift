import SwiftUI

struct SpokeConfirmationView: View {
    let title: String
    let message: String
    let actionTitle: String
    let onConfirm: () -> Void

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
                        dismiss()
                        onConfirm()
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
    }
}

import SwiftUI

struct SpokeSheet<Content: View>: View {
    let title: String
    var detents: Set<PresentationDetent> = [.large]
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SpokeStyle.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(SpokeStyle.surface, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") {
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(SpokeToolbarButtonStyle())
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        }
        .foregroundStyle(SpokeStyle.text)
        .tint(SpokeStyle.accent)
        .preferredColorScheme(.dark)
        .presentationBackground(SpokeStyle.surface)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

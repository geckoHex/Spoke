import SwiftUI

struct SpokeSheet<Content: View>: View {
    let title: String
    var fillsHeight = false
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 0
    @State private var topInset: CGFloat = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Group {
                    if fillsHeight {
                        content
                    } else {
                        ScrollView {
                            content
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { contentHeight = $0 }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollDismissesKeyboard(.interactively)
                        .accessibilityIdentifier("sheetContent")
                    }
                }
                .onChange(of: geometry.safeAreaInsets.top, initial: true) {
                    topInset = geometry.safeAreaInsets.top
                }
            }
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
        .presentationDetents(
            fillsHeight || contentHeight == 0 ? [.large] : [.height(contentHeight + topInset)]
        )
        .presentationDragIndicator(.visible)
    }
}

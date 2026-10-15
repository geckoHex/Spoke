import SwiftUI

enum AppTab: String, CaseIterable {
    case home, ride, history, stats, settings

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .home: "house"
        case .ride: "bicycle"
        case .history: "clock.arrow.circlepath"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home, .stats, .settings: symbol + ".fill"
        case .ride, .history: symbol
        }
    }
}

struct SpokeTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: selection == tab ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selection == tab ? SpokeStyle.text : SpokeStyle.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(SpokeStyle.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(SpokeStyle.separator).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spokeTabBar")
    }
}

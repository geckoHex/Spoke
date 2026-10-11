import SwiftUI

extension RideRouteMotion {
    var color: Color {
        switch self {
        case .normalOrFaster: SpokeStyle.primaryAction
        case .slower: SpokeStyle.text
        case .stopped: SpokeStyle.secondaryText
        }
    }

    var strokeStyle: StrokeStyle {
        switch self {
        case .normalOrFaster: StrokeStyle(lineWidth: 5, lineCap: .round)
        case .slower: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 6])
        case .stopped: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 7])
        }
    }

    var mapStrokeStyle: StrokeStyle {
        var style = strokeStyle
        // MapKit renders patterned strokes wider than solid strokes at the same nominal width.
        if !style.dash.isEmpty { style.lineWidth = 3 }
        return style
    }
}

struct RideRouteLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { items }
                VStack(alignment: .leading, spacing: 10) { items }
            }
            Text("Pace compared with this ride’s usual speed.")
                .foregroundStyle(SpokeStyle.secondaryText)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var items: some View {
        Group {
            item("Usual / faster", motion: .normalOrFaster)
            item("Slower", motion: .slower)
            item("Stopped", motion: .stopped)
        }
    }

    private func item(_ title: String, motion: RideRouteMotion) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                path.addLine(to: CGPoint(x: 24, y: 3))
            }
            .stroke(motion.color, style: motion.strokeStyle)
            .frame(width: 24, height: 6)
            .accessibilityHidden(true)
            Text(title).foregroundStyle(SpokeStyle.text)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct RideEndpointMarker: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SpokeStyle.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(SpokeStyle.background, in: Capsule())
            .padding(.vertical, 6)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityIdentifier("routeEndpoint\(title)")
    }
}

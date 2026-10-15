import MapKit
import SwiftData
import SwiftUI

struct StatsExplorationMap: View {
    let rides: [TrackedRide]
    let startDate: Date
    let now: Date
    @State private var exploration: RideExploration?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exploration")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            if let exploration {
                if exploration.paths.isEmpty {
                    Text("A ride with a recorded route will show the streets you explore here.")
                        .font(.subheadline)
                        .foregroundStyle(SpokeStyle.secondaryText)
                } else {
                    Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                        ForEach(exploration.paths.filter { !$0.isNew }) { path in
                            MapPolyline(coordinates: path.coordinates)
                                .stroke(SpokeStyle.secondaryText, style: StrokeStyle(lineWidth: 3, dash: [4, 4]))
                        }
                        ForEach(exploration.paths.filter(\.isNew)) { path in
                            MapPolyline(coordinates: path.coordinates)
                                .stroke(SpokeStyle.danger, lineWidth: 4)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 240)
                    .accessibilityLabel("Exploration map")
                    .accessibilityValue("Solid red streets were first ridden in the last 30 days. Dashed gray streets were ridden before.")
                    .accessibilityIdentifier("statsExplorationMap")

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { legend }
                        VStack(alignment: .leading, spacing: 8) { legend }
                    }
                    .font(.caption)
                    Text("First-time streets estimated from your saved GPS routes.")
                        .font(.caption)
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
            } else {
                ProgressView("Comparing saved routes")
            }
        }
        .task(id: rides.map(\.persistentModelID)) {
            exploration = RideExploration(rides: rides, since: startDate, now: now)
        }
    }

    @ViewBuilder private var legend: some View {
        Label {
            Text("First ridden")
        } icon: {
            Rectangle().fill(SpokeStyle.danger).frame(width: 20, height: 3)
        }
        Label {
            Text("Ridden before")
        } icon: {
            HStack(spacing: 3) {
                Rectangle().frame(width: 8, height: 3)
                Rectangle().frame(width: 8, height: 3)
            }.foregroundStyle(SpokeStyle.secondaryText)
        }
    }
}

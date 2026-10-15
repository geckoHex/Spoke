import SwiftUI

struct StatsTimeBreakdown: View {
    let stats: RideStatistics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let time = stats.timeBreakdown
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speed distribution")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if time.recorded > 0 {
                    ForEach(RideSpeedBand.allCases) { band in
                        VStack(spacing: 6) {
                            HStack {
                                Text(band.label)
                                Spacer()
                                Text(RideMetrics.duration(time.secondsByBand[band.rawValue]))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            ProgressView(value: time.secondsByBand[band.rawValue], total: time.recorded)
                                .tint(SpokeStyle.danger)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text("A ride with continuous GPS recording will show time at each speed here.")
                        .font(.subheadline)
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
            }
            .accessibilityIdentifier("statsSpeedDistribution")

            if time.recorded > 0 {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Moving vs. stopped")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Rectangle().fill(SpokeStyle.danger)
                                .frame(width: geometry.size.width * time.moving / time.recorded)
                            Rectangle().fill(SpokeStyle.secondaryText)
                        }
                    }
                    .frame(height: 12)
                    .accessibilityHidden(true)
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                        : AnyLayout(HStackLayout(alignment: .top))
                    layout {
                        timeLabel("Moving", duration: time.moving)
                        timeLabel("Stopped", duration: time.stopped)
                    }
                    Text("Stopped is 1 mph or less. Pauses and GPS gaps are excluded.")
                        .font(.caption)
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
                .accessibilityIdentifier("statsMovingStopped")
            }

            Text("\(RideMetrics.duration(time.recorded)) of \(RideMetrics.duration(stats.duration)) riding time measured from GPS.")
                .font(.caption)
                .foregroundStyle(SpokeStyle.secondaryText)
        }
    }

    private func timeLabel(_ title: String, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(SpokeStyle.secondaryText)
            Text(RideMetrics.duration(duration)).font(.headline).monospacedDigit()
            Text((duration / stats.timeBreakdown.recorded).formatted(.percent.precision(.fractionLength(0))))
                .font(.caption).foregroundStyle(SpokeStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatsActivityCalendar: View {
    let stats: RideStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly activity")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(0..<7) { index in
                    Text(stats.weekdaySymbols[index])
                        .font(.caption)
                        .foregroundStyle(SpokeStyle.secondaryText)
                        .accessibilityHidden(true)
                }
                ForEach(0..<stats.calendarLeadingDays, id: \.self) { _ in
                    Color.clear.frame(height: 24).accessibilityHidden(true)
                }
                ForEach(stats.days) { day in
                    Rectangle()
                        .fill(color(for: day))
                        .frame(width: 24, height: 24)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityValue(day.rideCount == 0 ? "No rides" : "\(day.rideCount) rides, \(RideMetrics.distance(day.distanceInMeters))")
                }
            }
            HStack(spacing: 6) {
                Text("Less")
                ForEach([0.65, 0.77, 0.89, 1.0], id: \.self) { opacity in
                    Rectangle().fill(SpokeStyle.danger.opacity(opacity)).frame(width: 12, height: 12)
                }
                Text("More distance")
            }
            .font(.caption)
            .foregroundStyle(SpokeStyle.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brighter squares mean more distance ridden")
        }
        .accessibilityIdentifier("statsActivityCalendar")
    }

    private func color(for day: RideStatistics.Day) -> Color {
        guard day.rideCount > 0 else { return SpokeStyle.elevatedSurface }
        let maximum = stats.days.map(\.distanceInMeters).max() ?? 0
        let intensity = maximum > 0 ? day.distanceInMeters / maximum : 0
        return SpokeStyle.danger.opacity(0.65 + 0.35 * intensity)
    }
}

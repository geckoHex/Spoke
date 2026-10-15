import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query(filter: #Predicate<TrackedRide> { $0.endedAt != nil })
    private var rides: [TrackedRide]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let stats = RideStatistics(rides: rides, now: context.date)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stats")
                                .font(SpokeStyle.pageTitle)
                                .tracking(-0.8)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("statsTitle")
                            Text("Last 30 days")
                                .font(.headline)
                            Text("\(stats.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(context.date.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.subheadline)
                                .foregroundStyle(SpokeStyle.secondaryText)
                        }

                        if stats.rideCount == 0 {
                            ContentUnavailableView(
                                "No rides in the last 30 days",
                                systemImage: "chart.bar.xaxis",
                                description: Text("Finish a ride to see your speed, distance, and riding trends here.")
                            )
                        } else {
                            speedChart(stats)
                            Divider().overlay(SpokeStyle.separator)
                            distanceChart(stats)
                            Divider().overlay(SpokeStyle.separator)
                            rideSummary(stats)
                            Divider().overlay(SpokeStyle.separator)
                            peakPerformance(stats)
                        }
                    }
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .background(SpokeStyle.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func speedChart(_ stats: RideStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeading("Average ride speed", value: stats.averageSpeed.map { RideMetrics.speedInMilesPerHour($0) } ?? "—")

            if stats.averageSpeed != nil {
                Chart(stats.days) { day in
                    if let speed = day.averageSpeed {
                        LineMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Average speed (mph)", speed)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(SpokeStyle.primaryAction)
                        .symbol(.square)
                        .symbolSize(28)
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(RideMetrics.speedInMilesPerHour(speed))
                    }
                }
                .chartXScale(domain: stats.startDate...stats.endDate)
                .chartYScale(domain: 0...max(1, (stats.days.compactMap(\.averageSpeed).max() ?? 0) * 1.15))
                .modifier(StatsChartAxes())
                .frame(height: 170)
                .accessibilityLabel("Daily average ride speed")
                .accessibilityIdentifier("statsSpeedChart")

                Text("Daily average (mph)")
                    .font(.caption)
                    .foregroundStyle(SpokeStyle.secondaryText)
            } else {
                Text("Speed will appear after a ride with a recorded route and riding time.")
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
            }
        }
    }

    private func distanceChart(_ stats: RideStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeading("Distance ridden", value: RideMetrics.distance(stats.distanceInMeters))

            Chart(stats.days) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Distance (mi)", day.distanceInMeters / 1_609.344)
                )
                .foregroundStyle(SpokeStyle.primaryAction)
                .cornerRadius(0)
                .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                .accessibilityValue(RideMetrics.distance(day.distanceInMeters))
            }
            .chartXScale(domain: stats.startDate...stats.endDate)
            .chartYScale(domain: 0...max(1, (stats.days.map(\.distanceInMeters).max() ?? 0) / 1_609.344 * 1.15))
            .modifier(StatsChartAxes())
            .frame(height: 150)
            .accessibilityLabel("Daily distance ridden")
            .accessibilityIdentifier("statsDistanceChart")

            Text("Daily distance (mi)")
                .font(.caption)
                .foregroundStyle(SpokeStyle.secondaryText)
        }
    }

    private func rideSummary(_ stats: RideStatistics) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your riding")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                alignment: .leading,
                spacing: 24
            ) {
                metric("Rides", value: stats.rideCount.formatted())
                metric("Active days", value: stats.activeDays.formatted())
                metric("Riding time", value: RideMetrics.duration(stats.duration))
                metric("Average ride time", value: RideMetrics.duration(stats.averageDuration))
                metric("Average distance", value: RideMetrics.distance(stats.averageDistance))
            }
        }
    }

    private func peakPerformance(_ stats: RideStatistics) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Peak performance")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                alignment: .leading,
                spacing: 24
            ) {
                metric("Top speed", value: stats.topSpeed.map { RideMetrics.speedInMilesPerHour($0) } ?? "—")
                metric("Fastest ride average", value: stats.fastestRide.map { RideMetrics.speedInMilesPerHour($0) } ?? "—")
                metric("Longest distance", value: stats.longestRide.map { RideMetrics.distance($0) } ?? "—")
                metric("Longest riding time", value: stats.longestDuration.map { RideMetrics.duration($0) } ?? "—")
            }
        }
    }

    private func chartHeading(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(SpokeStyle.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Text(value)
                .font(.largeTitle.bold())
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(SpokeStyle.secondaryText)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct StatsChartAxes: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                        .foregroundStyle(SpokeStyle.separator)
                    AxisValueLabel()
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
            }
    }
}

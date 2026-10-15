import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query(filter: #Predicate<TrackedRide> { $0.endedAt != nil })
    private var rides: [TrackedRide]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period: RideStatisticsPeriod = .thisMonth

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let stats = RideStatistics(rides: rides, period: period, now: context.date)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stats")
                                .font(SpokeStyle.pageTitle)
                                .tracking(-0.8)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("statsTitle")
                            periodPicker
                                .padding(.vertical, 8)
                            Text("\(stats.startDate.formatted(.dateTime.month(.abbreviated).day().year())) – \(context.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                                .font(.subheadline)
                                .foregroundStyle(SpokeStyle.secondaryText)
                                .accessibilityIdentifier("statsDateRange")
                        }

                        if stats.rideCount == 0 {
                            ContentUnavailableView(
                                "No rides in this period",
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
                            StatsActivityCalendar(stats: stats)
                            Divider().overlay(SpokeStyle.separator)
                            StatsTimeBreakdown(stats: stats)
                            Divider().overlay(SpokeStyle.separator)
                            StatsExplorationMap(rides: rides, startDate: stats.startDate, now: context.date)
                                .id(stats.startDate)
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

    private var periodPicker: some View {
        Picker("Time period", selection: $period) {
            ForEach(RideStatisticsPeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("statsPeriodPicker")
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
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day().year()))
                        .accessibilityValue(RideMetrics.speedInMilesPerHour(speed))
                    }
                }
                .chartXScale(domain: stats.startDate...stats.endDate)
                .chartYScale(domain: 0...max(1, (stats.days.compactMap(\.averageSpeed).max() ?? 0) * 1.15))
                .modifier(StatsChartAxes(dayCount: stats.days.count))
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
                .accessibilityLabel(day.date.formatted(.dateTime.month().day().year()))
                .accessibilityValue(RideMetrics.distance(day.distanceInMeters))
            }
            .chartXScale(domain: stats.startDate...stats.endDate)
            .chartYScale(domain: 0...max(1, (stats.days.map(\.distanceInMeters).max() ?? 0) / 1_609.344 * 1.15))
            .modifier(StatsChartAxes(dayCount: stats.days.count))
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
                record("Top speed", value: stats.topSpeed.map { RideMetrics.speedInMilesPerHour($0) } ?? "—", ride: stats.topSpeedRide, id: "statsTopSpeed")
                record("Fastest ride average", value: stats.fastestRide.map { RideMetrics.speedInMilesPerHour($0) } ?? "—", ride: stats.fastestAverageRide, id: "statsFastestAverage")
                record("Longest distance", value: stats.longestRide.map { RideMetrics.distance($0) } ?? "—", ride: stats.longestDistanceRide, id: "statsLongestDistance")
                record("Longest riding time", value: stats.longestDuration.map { RideMetrics.duration($0) } ?? "—", ride: stats.longestTimeRide, id: "statsLongestTime")
            }
        }
    }

    @ViewBuilder private func record(_ title: String, value: String, ride: TrackedRide?, id: String) -> some View {
        if let ride {
            NavigationLink {
                RideHistoryDetailView(ride: ride)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    metric(title, value: value)
                    HStack {
                        Text(ride.startedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(SpokeStyle.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open ride details")
            .accessibilityIdentifier(id)
        } else {
            metric(title, value: value)
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
    let dayCount: Int

    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: dayCount > 366
                                   ? .dateTime.month(.abbreviated).year()
                                   : .dateTime.month(.abbreviated).day())
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

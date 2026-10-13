//
//  HomeView.swift
//  Spoke
//

import SwiftData
import SwiftUI

struct HomeView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController
    let onStartRide: () -> Void
    let onShowRide: () -> Void
    let onEndRide: () -> Void

    @Query(sort: \TrackedRide.startedAt, order: .reverse)
    private var rides: [TrackedRide]
    @State private var selectedRide: TrackedRide?

    @State private var weatherModel =
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            && ProcessInfo.processInfo.arguments.contains("--weather-fixture")
        ? RideUITestFixture.weatherModel() : HomeWeatherModel()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentDate = max(context.date, Date.now)
                let timeOfDay = TimeOfDay(date: currentDate)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HomeGreeting(timeOfDay: timeOfDay, name: displayName)

                        HomeWeatherView(
                            date: currentDate,
                            snapshot: weatherModel.snapshot,
                            isLoading: weatherModel.isLoading,
                            isUnavailable: weatherModel.isUnavailable,
                            isDeveloperModeEnabled: settings?.developerModeEnabled == true,
                            onExpireAndReload: {
                                Task { await weatherModel.refresh() }
                            }
                        )

                        HomeRideActivity(rides: completedRides, date: currentDate) {
                            selectedRide = $0
                        }
                    }
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .background(SpokeStyle.background)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    rideAction(date: currentDate)
                        .padding(.horizontal, SpokeStyle.pageInset)
                        .padding(.vertical, 12)
                        .background(SpokeStyle.background)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedRide) { ride in
                RideHistoryDetailView(ride: ride)
            }
        }
        .task {
            await weatherModel.maintainWeather()
        }
    }

    @ViewBuilder
    private func rideAction(date: Date) -> some View {
        if let ride = rideSession.activeRide {
            VStack(spacing: 12) {
                Button(action: onShowRide) {
                    HStack {
                        Label(ride.isPaused ? "Ride paused" : rideSession.locationStatus.title, systemImage: "bicycle")
                        Spacer()
                        Text(RideMetrics.duration(ride.elapsedDuration(at: date)))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpokeStyle.text)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View current ride")
                .accessibilityValue(ride.isPaused ? "Paused" : rideSession.locationStatus.title)

                RideControlsView(
                    ride: ride,
                    onPauseToggle: { rideSession.togglePause() },
                    onEnd: onEndRide
                )
            }
        } else {
            Button(action: onStartRide) {
                Text("Start Ride")
            }
            .buttonStyle(SpokePrimaryButtonStyle(minHeight: 64))
            .anchorPreference(key: RideStartButtonPreference.self, value: .bounds) {
                [.home: $0]
            }
        }
    }

    private var completedRides: [TrackedRide] {
        rides.filter { $0.endedAt != nil }
    }

    private var displayName: String {
        let trimmedName = settings?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName ?? ""
    }
}

private struct HomeRideActivity: View {
    let rides: [TrackedRide]
    let date: Date
    let onOpenRide: (TrackedRide) -> Void

    private var recentRides: [TrackedRide] {
        rides.filter {
            RideMetrics.startedInLastSevenDays($0, relativeTo: date)
        }
    }

    private var totalDistance: Double {
        recentRides.reduce(0) { result, ride in
            result + RideMetrics.distanceInMeters(for: ride)
        }
    }

    private var totalDuration: TimeInterval {
        recentRides.reduce(0) { result, ride in
            result + ride.elapsedDuration()
        }
    }

    private var rideCountDescription: String {
        let count = recentRides.count
        return "\(count) \(count == 1 ? "ride" : "rides")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            weeklySummary

            Divider().overlay(SpokeStyle.separator)

            if let latestRide = rides.first {
                Button {
                    onOpenRide(latestRide)
                } label: {
                    latestRideRow(latestRide)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lastRide")
            } else {
                Text("No completed rides yet")
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 Days")
                    .font(.headline)
                    .foregroundStyle(SpokeStyle.text)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text(rideCountDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpokeStyle.secondaryText)
            }

            HStack(alignment: .top, spacing: 24) {
                activityMetric(
                    value: RideMetrics.distance(totalDistance),
                    label: "Distance"
                )

                activityMetric(
                    value: compactDuration(totalDuration),
                    label: "Ride Time"
                )
            }
        }
    }

    private func activityMetric(
        value: String,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(SpokeStyle.secondaryText)

            Text(value)
                .font(.largeTitle.bold())
                .foregroundStyle(SpokeStyle.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func latestRideRow(_ ride: TrackedRide) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Last Ride")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpokeStyle.text)

                Text(
                    ride.startedAt,
                    format: .dateTime
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                )
                .font(.caption)
                .foregroundStyle(SpokeStyle.secondaryText)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 5) {
                Text(
                    RideMetrics.distance(
                        RideMetrics.distanceInMeters(for: ride)
                    )
                )
                .font(.headline)
                .foregroundStyle(SpokeStyle.text)
                .monospacedDigit()

                Text(compactDuration(ride.elapsedDuration()))
                    .font(.caption)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpokeStyle.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func compactDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}

private struct HomeWeatherView: View {
    let date: Date
    let snapshot: HomeWeatherSnapshot?
    let isLoading: Bool
    let isUnavailable: Bool
    let isDeveloperModeEnabled: Bool
    let onExpireAndReload: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var weatherIconSize: CGFloat = 44

    @ViewBuilder
    var body: some View {
        if isDeveloperModeEnabled {
            weatherContent
                .contentShape(.rect)
                .onTapGesture(count: 5, perform: onExpireAndReload)
        } else {
            weatherContent
        }
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                weatherSummary

                Spacer(minLength: 12)

                weatherIcon
            }

            if isUnavailable || snapshot?.isStale(at: date) == true {
                HStack(spacing: 12) {
                    Text(isLoading ? "Updating weather…" : (snapshot == nil ? "Couldn’t load weather" : "Weather may be out of date"))
                        .font(.caption)
                        .foregroundStyle(SpokeStyle.text.opacity(0.9))
                    Spacer(minLength: 0)
                    Button(isLoading ? "Updating…" : "Retry", action: onExpireAndReload)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SpokeStyle.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isLoading)
                        .accessibilityLabel("Retry weather")
                }
            }

            if let snapshot {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        windLabel(snapshot: snapshot)

                        Text("\(snapshot.isStale(at: date) || isUnavailable ? "Last updated" : "Updated") \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(SpokeStyle.text.opacity(0.9))
                    }

                    Spacer(minLength: 8)

                    HomeWeatherAttribution(snapshot: snapshot)
                }
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: 156,
            alignment: .leading
        )
        .background {
            GeometryReader { geometry in
                Image(HomeWeatherBackground.imageName(
                    at: date,
                    sunrise: snapshot?.sunrise,
                    sunset: snapshot?.sunset
                ))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(SpokeStyle.accent.opacity(0.16))
                    .overlay(.black.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: SpokeStyle.cardRadius))
    }

    @ViewBuilder
    private var weatherSummary: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.temperature)
                    .font(.system(size: temperatureSize, weight: .bold))
                    .foregroundStyle(SpokeStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(snapshot.condition)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpokeStyle.text.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)
        } else {
            Text(isUnavailable ? "Weather unavailable" : "Loading weather")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SpokeStyle.text.opacity(0.9))
                .frame(minHeight: weatherIconSize + 8, alignment: .center)
        }
    }

    @ViewBuilder
    private func windLabel(snapshot: HomeWeatherSnapshot) -> some View {
        if let windSpeed = snapshot.windSpeed,
           let windDirection = snapshot.windDirection
        {
            Label {
                Text("\(windSpeed) \(windDirection)")
            } icon: {
                Image(systemName: "wind")
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SpokeStyle.text.opacity(0.9))
            .accessibilityLabel("Wind, \(windSpeed), \(windDirection)")
        }
    }

    @ViewBuilder
    private var weatherIcon: some View {
        if let snapshot {
            Image(systemName: plainWeatherSymbolName(snapshot.symbolName))
                .font(.system(size: weatherIconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(SpokeStyle.text)
                .symbolEffect(
                    .wiggle.byLayer,
                    options: .repeat(.periodic(delay: 3)).speed(0.55),
                    isActive: !reduceMotion
                )
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityHidden(true)
        } else if isLoading || !isUnavailable {
            ProgressView()
                .controlSize(.large)
                .tint(SpokeStyle.text)
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityLabel("Loading")
        } else {
            Image(systemName: "cloud")
                .font(.system(size: weatherIconSize - 8, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(SpokeStyle.text.opacity(0.9))
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityHidden(true)
        }
    }

    private func plainWeatherSymbolName(_ symbolName: String) -> String {
        for suffix in [".circle.fill", ".circle", ".fill"]
        where symbolName.hasSuffix(suffix) {
            return String(symbolName.dropLast(suffix.count))
        }

        return symbolName
    }
}

private struct HomeWeatherAttribution: View {
    let snapshot: HomeWeatherSnapshot

    var body: some View {
        Link(destination: snapshot.legalPageURL) {
            AsyncImage(url: snapshot.attributionMarkURL) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 10, alignment: .trailing)
            } placeholder: {
                Text("Apple Weather")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SpokeStyle.text.opacity(0.9))
            }
            .frame(minWidth: 72, minHeight: 44, alignment: .bottomTrailing)
            .contentShape(.rect)
        }
        .accessibilityLabel("Apple Weather attribution")
    }
}

private struct HomeGreeting: View {
    let timeOfDay: TimeOfDay
    let name: String

    var body: some View {
        Text(timeOfDay.salutation + (name.isEmpty ? "" : ", \(name)"))
            .font(.title.bold())
            .foregroundStyle(SpokeStyle.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private enum TimeOfDay {
    case morning
    case afternoon
    case evening

    init(date: Date) {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<12:
            self = .morning
        case 12..<17:
            self = .afternoon
        default:
            self = .evening
        }
    }

    var salutation: String {
        switch self {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        }
    }
}


#Preview {
    HomeView(
        settings: AppSettings(),
        rideSession: RideSessionController(),
        onStartRide: {},
        onShowRide: {},
        onEndRide: {}
    )
    .modelContainer(
        for: [
            TrackedRide.self,
            RideRoutePoint.self,
            RideSoundtrackEntry.self,
        ],
        inMemory: true
    )
    .preferredColorScheme(.dark)
}

//
//  HomeView.swift
//  Spoke
//

import SwiftData
import SwiftUI

struct HomeView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController
    let onRideStarted: () -> Void
    let onEndRide: () -> Void

    @Query(sort: \TrackedRide.startedAt, order: .reverse)
    private var rides: [TrackedRide]

    @State private var weatherModel = HomeWeatherModel()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentDate = max(context.date, Date.now)
                let timeOfDay = TimeOfDay(date: currentDate)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HomeGreeting(timeOfDay: timeOfDay, name: displayName)

                        HomeWeatherView(
                            snapshot: weatherModel.snapshot,
                            isLoading: weatherModel.isLoading,
                            isUnavailable: weatherModel.isUnavailable,
                            isDeveloperModeEnabled: settings?.developerModeEnabled == true,
                            onExpireAndReload: {
                                Task { await weatherModel.expireCacheAndReload() }
                            }
                        )

                        HomeRideActivity(rides: completedRides, date: currentDate)
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
        }
        .task {
            await weatherModel.maintainWeather()
        }
    }

    @ViewBuilder
    private func rideAction(date: Date) -> some View {
        if let ride = rideSession.activeRide {
            VStack(spacing: 12) {
                Button(action: onRideStarted) {
                    HStack {
                        Label(ride.isPaused ? "Ride paused" : "Ride in progress", systemImage: "bicycle")
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

                RideControlsView(
                    ride: ride,
                    onPauseToggle: { rideSession.togglePause() },
                    onEnd: onEndRide
                )
            }
        } else {
            Button {
                guard rideSession.startRide() != nil else { return }
                onRideStarted()
            } label: {
                Label("Start Ride", systemImage: "figure.outdoor.cycle")
            }
            .buttonStyle(SpokePrimaryButtonStyle(minHeight: 64))
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

    private var ridesThisWeek: [TrackedRide] {
        rides.filter {
            RideMetrics.startedInLastSevenDays($0, relativeTo: date)
        }
    }

    private var totalDistance: Double {
        ridesThisWeek.reduce(0) { result, ride in
            result + RideMetrics.distanceInMeters(for: ride)
        }
    }

    private var totalDuration: TimeInterval {
        ridesThisWeek.reduce(0) { result, ride in
            result + ride.elapsedDuration()
        }
    }

    private var rideCountDescription: String {
        let count = ridesThisWeek.count
        return "\(count) \(count == 1 ? "ride" : "rides")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            weeklySummary

            Divider()
                .overlay(SpokeStyle.separator)

            if let latestRide = rides.first {
                latestRideRow(latestRide)
            } else {
                Label("No completed rides yet", systemImage: "figure.outdoor.cycle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No completed rides yet")
            }
        }
        .spokeCard()
        .accessibilityElement(children: .contain)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SpokeStyle.text)

                Spacer()

                Text(rideCountDescription)
                    .font(.headline)
                    .foregroundStyle(SpokeStyle.secondaryText)
            }

            HStack(alignment: .top, spacing: 24) {
                activityMetric(
                    value: RideMetrics.distance(totalDistance),
                    label: "Distance",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )

                activityMetric(
                    value: compactDuration(totalDuration),
                    label: "Ride Time",
                    systemImage: "timer"
                )
            }
        }
    }

    private func activityMetric(
        value: String,
        label: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SpokeStyle.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(SpokeStyle.text)
                    .accessibilityHidden(true)

                Text(label)
                    .foregroundStyle(SpokeStyle.secondaryText)
            }
            .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func latestRideRow(_ ride: TrackedRide) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SpokeStyle.text)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Last Ride")
                    .font(.headline)
                    .foregroundStyle(SpokeStyle.text)

                Text(
                    ride.startedAt,
                    format: .dateTime
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                )
                .font(.subheadline)
                .foregroundStyle(SpokeStyle.secondaryText)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 5) {
                Text(
                    RideMetrics.distance(
                        RideMetrics.distanceInMeters(for: ride)
                    )
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(SpokeStyle.text)
                .monospacedDigit()

                Text(compactDuration(ride.elapsedDuration()))
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .monospacedDigit()
            }
        }
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
    let snapshot: HomeWeatherSnapshot?
    let isLoading: Bool
    let isUnavailable: Bool
    let isDeveloperModeEnabled: Bool
    let onExpireAndReload: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 68
    @ScaledMetric(relativeTo: .largeTitle) private var weatherIconSize: CGFloat = 62

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

            if let snapshot {
                HStack(alignment: .center, spacing: 12) {
                    windLabel(snapshot: snapshot)

                    Spacer(minLength: 8)

                    HomeWeatherAttribution(snapshot: snapshot)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(
            maxWidth: .infinity,
            minHeight: 192,
            alignment: .leading
        )
        .background {
            Image("ForestLandscape")
                .resizable()
                .scaledToFill()
                .overlay(SpokeStyle.background.opacity(0.38))
                .accessibilityHidden(true)
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)
        } else {
            Text(isUnavailable ? "Weather unavailable" : "Loading weather")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SpokeStyle.secondaryText)
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
            .foregroundStyle(SpokeStyle.secondaryText)
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
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityHidden(true)
        } else if isLoading || !isUnavailable {
            ProgressView()
                .controlSize(.large)
                .tint(SpokeStyle.accent)
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityLabel("Loading")
        } else {
            Image(systemName: "cloud")
                .font(.system(size: weatherIconSize - 8, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(SpokeStyle.secondaryText)
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
            } placeholder: {
                Text("Apple Weather")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SpokeStyle.secondaryText)
            }
            .frame(width: 72, height: 10, alignment: .trailing)
        }
        .offset(y: 3)
        .accessibilityLabel("Apple Weather attribution")
    }
}

private struct HomeGreeting: View {
    let timeOfDay: TimeOfDay
    let name: String

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeOfDay.salutation + (name.isEmpty ? "" : ","))
                .font(name.isEmpty ? .largeTitle.bold() : .title3.weight(.medium))
                .foregroundStyle(name.isEmpty ? SpokeStyle.text : SpokeStyle.secondaryText)

            if !name.isEmpty {
                Text(name)
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundStyle(SpokeStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timeOfDay.salutation + (name.isEmpty ? "" : ", \(name)"))
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
        onRideStarted: {},
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

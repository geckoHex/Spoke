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
    let onRideSummaryDone: (TrackedRide) -> Void

    @Query(sort: \TrackedRide.startedAt, order: .reverse)
    private var rides: [TrackedRide]

    @State private var completedRide: TrackedRide?
    @State private var weatherModel = HomeWeatherModel()
    @Namespace private var rideControlNamespace

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentDate = max(context.date, Date.now)
                let timeOfDay = TimeOfDay(date: currentDate)

                ZStack(alignment: .top) {
                    Color.black
                        .ignoresSafeArea()

                    HomeSkyGradient(period: HomeSkyPeriod(date: currentDate))

                    GeometryReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 22) {
                                    HomeGreeting(
                                        timeOfDay: timeOfDay,
                                        name: displayName
                                    )

                                    HomeWeatherView(
                                        snapshot: weatherModel.snapshot,
                                        isLoading: weatherModel.isLoading,
                                        isUnavailable: weatherModel.isUnavailable,
                                        isDeveloperModeEnabled:
                                            settings?.developerModeEnabled == true,
                                        onExpireAndReload: {
                                            Task {
                                                await weatherModel.expireCacheAndReload()
                                            }
                                        }
                                    )
                                }

                                Spacer(minLength: 24)

                                HomeRideActivity(
                                    rides: completedRides,
                                    date: currentDate
                                )

                                Spacer(minLength: 24)

                                rideAction(date: currentDate)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: max(proxy.size.height - 44, 0),
                                alignment: .topLeading
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 28)
                            .padding(.bottom, 16)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
        }
        .sheet(isPresented: isShowingSummary) {
            if let completedRide {
                RideSummaryView(
                    ride: completedRide,
                    onDone: {
                        self.completedRide = nil
                        onRideSummaryDone(completedRide)
                    }
                )
            }
        }
        .task {
            await weatherModel.maintainWeather()
        }
    }

    private var isShowingSummary: Binding<Bool> {
        Binding(
            get: { completedRide != nil },
            set: { isPresented in
                if !isPresented {
                    completedRide = nil
                }
            }
        )
    }

    private func endRide() {
        completedRide = rideSession.endRide()
    }

    @ViewBuilder
    private func rideAction(date: Date) -> some View {
        if let ride = rideSession.activeRide {
            ActiveRideControl(
                ride: ride,
                date: date,
                namespace: rideControlNamespace,
                onPauseToggle: {
                    rideSession.togglePause()
                },
                onEnd: endRide
            )
        } else {
            Button {
                withAnimation(
                    .smooth(duration: 0.45),
                    completionCriteria: .logicallyComplete
                ) {
                    _ = rideSession.startRide()
                } completion: {
                    guard rideSession.activeRide != nil else { return }
                    onRideStarted()
                }
            } label: {
                Label("Start Ride", systemImage: "figure.outdoor.cycle")
            }
            .buttonStyle(SpokePrimaryButtonStyle(minHeight: 56))
            .matchedGeometryEffect(id: "rideTimer", in: rideControlNamespace)
        }
    }

    private var completedRides: [TrackedRide] {
        rides.filter { $0.endedAt != nil }
    }

    private var displayName: String {
        let trimmedName = settings?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "User"
    }
}

private struct HomeRideActivity: View {
    let rides: [TrackedRide]
    let date: Date

    private var ridesThisWeek: [TrackedRide] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }

        return rides.filter { week.contains($0.startedAt) }
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
                .overlay(.white.opacity(0.12))

            if let latestRide = rides.first {
                latestRideRow(latestRide)
            } else {
                Label("No completed rides yet", systemImage: "figure.outdoor.cycle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No completed rides yet")
            }
        }
        .homeCard()
        .accessibilityElement(children: .contain)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(rideCountDescription)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.55))
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
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(label)
                    .foregroundStyle(.white.opacity(0.55))
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
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Last Ride")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(
                    ride.startedAt,
                    format: .dateTime
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 5) {
                Text(
                    RideMetrics.distance(
                        RideMetrics.distanceInMeters(for: ride)
                    )
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()

                Text(compactDuration(ride.elapsedDuration()))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
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

    @ViewBuilder
    var body: some View {
        if isDeveloperModeEnabled {
            weatherCard
                .contentShape(.rect)
                .onTapGesture(count: 5, perform: onExpireAndReload)
        } else {
            weatherCard
        }
    }

    private var weatherCard: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                weatherIcon

                if let snapshot {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.temperature)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(snapshot.condition)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text(isUnavailable ? "Weather unavailable" : "Loading weather")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer(minLength: 12)
            }
            .padding(.bottom, snapshot == nil ? 0 : 10)

            if let snapshot {
                Link(destination: snapshot.legalPageURL) {
                    AsyncImage(url: snapshot.attributionMarkURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Text("Apple Weather")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(width: 72, height: 10, alignment: .trailing)
                }
                .accessibilityLabel("Apple Weather attribution")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 76)
        .homeCard(padding: 18)
    }

    @ViewBuilder
    private var weatherIcon: some View {
        if let snapshot {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 44)
                .accessibilityHidden(true)
        } else if isLoading || !isUnavailable {
            ProgressView()
                .tint(.white)
                .frame(width: 44)
                .accessibilityLabel("Loading")
        } else {
            Image(systemName: "cloud.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 44)
                .accessibilityHidden(true)
        }
    }
}

private struct HomeGreeting: View {
    let timeOfDay: TimeOfDay
    let name: String

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(timeOfDay.salutation),")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text(name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeOfDay.salutation), \(name)")
    }
}

private extension View {
    func homeCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
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

private struct HomeSkyGradient: View {
    let period: HomeSkyPeriod

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: period.colors,
                startPoint: .topLeading,
                endPoint: .topTrailing
            )
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.82), location: 0.36),
                        .init(color: .clear, location: 0.96),
                    ],
                    startPoint: UnitPoint(x: 0.08, y: 0),
                    endPoint: UnitPoint(x: 0.92, y: 1)
                )
            }
            .frame(
                width: proxy.size.width,
                height: min(max(proxy.size.height * 0.54, 360), 470),
                alignment: .top
            )
            .blur(radius: 22)
            .opacity(0.34)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum HomeSkyPeriod {
    case sunrise
    case day
    case sunset
    case night

    init(date: Date) {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<8:
            self = .sunrise
        case 8..<17:
            self = .day
        case 17..<20:
            self = .sunset
        default:
            self = .night
        }
    }

    var colors: [Color] {
        switch self {
        case .sunrise:
            [
                Color(red: 1, green: 0.25, blue: 0.5),
                Color(red: 1, green: 0.48, blue: 0.16),
            ]
        case .day:
            [
                Color(red: 1, green: 0.78, blue: 0.18),
                Color(red: 0.18, green: 0.55, blue: 1),
            ]
        case .sunset:
            [
                Color(red: 0.55, green: 0.18, blue: 0.85),
                Color(red: 1, green: 0.34, blue: 0.12),
            ]
        case .night:
            [
                Color(red: 0.28, green: 0.12, blue: 0.58),
                Color(red: 0.03, green: 0.12, blue: 0.35),
            ]
        }
    }
}

private struct ActiveRideControl: View {
    let ride: TrackedRide
    let date: Date
    let namespace: Namespace.ID
    let onPauseToggle: () -> Void
    let onEnd: () -> Void

    @State private var isConfirmingEndRide = false

    var body: some View {
        let elapsedSeconds = max(
            Int(ride.elapsedDuration(at: date).rounded(.down)),
            0
        )

        HStack(spacing: 12) {
            timer(elapsedSeconds: elapsedSeconds)

            Button {
                isConfirmingEndRide = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(.white, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End Ride")
            .transition(
                .offset(x: -68)
                    .combined(with: .scale(scale: 0.8, anchor: .trailing))
                    .combined(with: .opacity)
            )

            Button {
                onPauseToggle()
            } label: {
                Image(systemName: ride.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(.white, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ride.isPaused ? "Resume Ride" : "Pause Ride")
            .transition(
                .offset(x: -68)
                    .combined(with: .scale(scale: 0.8, anchor: .trailing))
                    .combined(with: .opacity)
            )
        }
        .alert("End Ride?", isPresented: $isConfirmingEndRide) {
            Button("Cancel", role: .cancel) {}
            Button("End Ride", role: .destructive) {
                onEnd()
            }
        } message: {
            Text("This ride will be saved to your history.")
        }
    }

    private func timer(elapsedSeconds: Int) -> some View {
        ZStack {
            Capsule()
                .fill(.white)

            Text(RideMetrics.duration(TimeInterval(elapsedSeconds)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.black)
                .contentTransition(.numericText(value: Double(elapsedSeconds)))
                .animation(
                    ride.isPaused ? nil : .snappy(duration: 0.35),
                    value: elapsedSeconds
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .matchedGeometryEffect(id: "rideTimer", in: namespace)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride timer")
        .accessibilityValue(
            "\(RideMetrics.duration(TimeInterval(elapsedSeconds))), "
                + (ride.isPaused ? "paused" : "running")
        )
    }
}

struct SpokePrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

#Preview {
    HomeView(
        settings: AppSettings(),
        rideSession: RideSessionController(),
        onRideStarted: {},
        onRideSummaryDone: { _ in }
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

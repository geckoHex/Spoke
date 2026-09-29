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

                    GeometryReader { proxy in
                        let usesCompactSpacing = proxy.size.height < 760

                        VStack(alignment: .leading, spacing: 0) {
                            HomeGreeting(
                                timeOfDay: timeOfDay,
                                name: displayName
                            )

                            Spacer(minLength: usesCompactSpacing ? 10 : 16)

                            HomeWeatherView(
                                snapshot: weatherModel.snapshot,
                                isLoading: weatherModel.isLoading,
                                isUnavailable: weatherModel.isUnavailable,
                                isDeveloperModeEnabled:
                                    settings?.developerModeEnabled == true,
                                usesCompactHeight: usesCompactSpacing,
                                onExpireAndReload: {
                                    Task {
                                        await weatherModel.expireCacheAndReload()
                                    }
                                }
                            )

                            Spacer(minLength: usesCompactSpacing ? 10 : 16)

                            HomeRideActivity(
                                rides: completedRides,
                                date: currentDate
                            )

                            Spacer()
                                .frame(height: usesCompactSpacing ? 8 : 10)

                            rideAction(date: currentDate)
                                .padding(.vertical, 6)
                        }
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .padding(.horizontal, SpokeStyle.pageInset)
                        .padding(.top, usesCompactSpacing ? 16 : 24)
                        .padding(.bottom, 4)
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
                    },
                    onDiscard: {
                        guard rideSession.discardRide(completedRide) else { return }
                        self.completedRide = nil
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
        Group {
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
                        .smooth(duration: 0.55),
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
                    .foregroundStyle(.white)

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
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
    let usesCompactHeight: Bool
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
        VStack(alignment: .leading, spacing: usesCompactHeight ? 12 : 16) {
            HStack(alignment: .top, spacing: 16) {
                weatherSummary

                Spacer(minLength: 12)

                weatherIcon
            }

            if let snapshot {
                HStack(alignment: .center, spacing: 12) {
                    windBadge(snapshot: snapshot)

                    Spacer(minLength: 8)

                    HomeWeatherAttribution(snapshot: snapshot)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, usesCompactHeight ? 16 : 20)
        .frame(
            maxWidth: .infinity,
            minHeight: usesCompactHeight ? 184 : 192,
            alignment: .leading
        )
        .background(
            SpokeStyle.surface,
            in: .rect(cornerRadius: SpokeStyle.cardRadius)
        )
    }

    @ViewBuilder
    private var weatherSummary: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.temperature)
                    .font(.system(size: temperatureSize, weight: .bold))
                    .foregroundStyle(.white)
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
    private func windBadge(snapshot: HomeWeatherSnapshot) -> some View {
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
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(SpokeStyle.elevatedSurface, in: Capsule())
            .accessibilityLabel("Wind, \(windSpeed), \(windDirection)")
        }
    }

    @ViewBuilder
    private var weatherIcon: some View {
        if let snapshot {
            Image(systemName: plainWeatherSymbolName(snapshot.symbolName))
                .font(.system(size: weatherIconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: weatherIconSize + 12, height: weatherIconSize + 12)
                .accessibilityHidden(true)
        } else if isLoading || !isUnavailable {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
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
            Text("\(timeOfDay.salutation),")
                .font(.title.weight(.semibold))
                .foregroundStyle(SpokeStyle.secondaryText)

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

private struct ActiveRideControl: View {
    let ride: TrackedRide
    let date: Date
    let namespace: Namespace.ID
    let onPauseToggle: () -> Void
    let onEnd: () -> Void

    @State private var isStopHoldActive = false
    @State private var stopHoldProgress: CGFloat = 0
    @State private var didCompleteStopHold = false
    @State private var stopMessageDismissTask: Task<Void, Never>?

    var body: some View {
        let elapsedSeconds = max(
            Int(ride.elapsedDuration(at: date).rounded(.down)),
            0
        )

        HStack(spacing: 12) {
            timer(elapsedSeconds: elapsedSeconds)

            Image(systemName: "flag.pattern.checkered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .background(.white, in: Circle())
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Stop Ride")
                .accessibilityHint("Hold for one second to stop the ride")
                .onLongPressGesture(
                    minimumDuration: 1,
                    maximumDistance: 44,
                    perform: completeStopHold,
                    onPressingChanged: updateStopHold
                )
                .transition(
                    .offset(x: -68)
                        .combined(with: .scale(scale: 0.8, anchor: .trailing))
                        .combined(with: .opacity)
                )

            Button {
                onPauseToggle()
            } label: {
                Image(systemName: ride.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(SpokeToolbarButtonStyle(size: 56))
            .accessibilityLabel(ride.isPaused ? "Resume Ride" : "Pause Ride")
            .transition(
                .offset(x: -68)
                    .combined(with: .scale(scale: 0.8, anchor: .trailing))
                    .combined(with: .opacity)
            )
        }
        .onDisappear {
            stopMessageDismissTask?.cancel()
        }
    }

    private func timer(elapsedSeconds: Int) -> some View {
        ZStack {
            GeometryReader { proxy in
                Color.red.opacity(0.78)
                    .frame(width: proxy.size.width * stopHoldProgress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .allowsHitTesting(false)

            if isStopHoldActive {
                Text("Hold to Stop")
                    .font(.headline)
                    .transition(.opacity)
            } else {
                Text(RideMetrics.duration(TimeInterval(elapsedSeconds)))
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(value: Double(elapsedSeconds)))
                    .animation(
                        ride.isPaused ? nil : .snappy(duration: 0.35),
                        value: elapsedSeconds
                    )
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: SpokeStyle.controlRadius, style: .continuous))
        .background(.white, in: RoundedRectangle(cornerRadius: SpokeStyle.controlRadius, style: .continuous))
        .matchedGeometryEffect(id: "rideTimer", in: namespace)
        .animation(.smooth(duration: 0.25), value: isStopHoldActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isStopHoldActive ? "Hold to Stop" : "Ride timer")
        .accessibilityValue(
            isStopHoldActive
                ? "Hold for one second to end the ride"
                : "\(RideMetrics.duration(TimeInterval(elapsedSeconds))), "
                    + (ride.isPaused ? "paused" : "running")
        )
    }

    private func updateStopHold(_ isPressing: Bool) {
        guard !didCompleteStopHold else { return }

        if isPressing {
            stopMessageDismissTask?.cancel()
            stopMessageDismissTask = nil

            withAnimation(.smooth(duration: 0.2)) {
                isStopHoldActive = true
            }

            withAnimation(.linear(duration: 1)) {
                stopHoldProgress = 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                stopHoldProgress = 0
            }

            scheduleStopMessageDismissal()
        }
    }

    private func scheduleStopMessageDismissal() {
        stopMessageDismissTask?.cancel()
        stopMessageDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }

            guard !didCompleteStopHold else { return }

            withAnimation(.smooth(duration: 0.25)) {
                isStopHoldActive = false
            }

            stopMessageDismissTask = nil
        }
    }

    private func completeStopHold() {
        guard !didCompleteStopHold else { return }

        didCompleteStopHold = true
        stopMessageDismissTask?.cancel()
        stopMessageDismissTask = nil
        isStopHoldActive = true
        stopHoldProgress = 1
        onEnd()
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

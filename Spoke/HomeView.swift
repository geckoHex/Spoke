//
//  HomeView.swift
//  Spoke
//

import SwiftUI

struct HomeView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController

    @State private var completedRide: TrackedRide?
    @State private var weatherModel = HomeWeatherModel()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentDate = max(context.date, Date.now)
                let timeOfDay = TimeOfDay(date: currentDate)

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 20) {
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

                        Spacer()

                        if let ride = rideSession.activeRide {
                            ActiveRideControl(
                                ride: ride,
                                date: currentDate,
                                onPauseToggle: {
                                    rideSession.togglePause()
                                },
                                onEnd: endRide
                            )
                        } else {
                            Button("Start Ride") {
                                rideSession.startRide()
                            }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: .capsule)
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .sheet(isPresented: isShowingSummary) {
            if let completedRide {
                RideSummaryView(
                    ride: completedRide,
                    onDone: {
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

    private var displayName: String {
        let trimmedName = settings?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "User"
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
        HStack(spacing: 14) {
            weatherIcon

            if let snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.temperature)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text(snapshot.condition)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 12)

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
                    .frame(width: 92, height: 14, alignment: .trailing)
                }
                .accessibilityLabel("Apple Weather attribution")
            } else {
                Text(isUnavailable ? "Weather unavailable" : "Loading weather")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.65))

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var weatherIcon: some View {
        if let snapshot {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 32, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 38)
                .accessibilityHidden(true)
        } else if isLoading || !isUnavailable {
            ProgressView()
                .tint(.white)
                .frame(width: 38)
                .accessibilityLabel("Loading")
        } else {
            Image(systemName: "cloud.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 38)
                .accessibilityHidden(true)
        }
    }
}

private struct HomeGreeting: View {
    let timeOfDay: TimeOfDay
    let name: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(timeOfDay.color.opacity(0.16))

                Circle()
                    .stroke(timeOfDay.color.opacity(0.3), lineWidth: 1)

                Image(systemName: timeOfDay.symbolName)
                    .font(.system(size: 29, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(timeOfDay.color)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(timeOfDay.salutation),")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))

                Text(name)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
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

    var symbolName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: .orange
        case .afternoon: .yellow
        case .evening: .indigo
        }
    }
}

private struct ActiveRideControl: View {
    let ride: TrackedRide
    let date: Date
    let onPauseToggle: () -> Void
    let onEnd: () -> Void

    @State private var isPressing = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    private let holdDuration = 1.5

    var body: some View {
        let elapsedSeconds = max(
            Int(ride.elapsedDuration(at: date).rounded(.down)),
            0
        )

        HStack(spacing: 12) {
            timer(elapsedSeconds: elapsedSeconds)

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
        }
        .onDisappear {
            holdTask?.cancel()
        }
    }

    private func timer(elapsedSeconds: Int) -> some View {
        ZStack {
            Capsule()
                .fill(.white)

            GeometryReader { proxy in
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: proxy.size.width * holdProgress)
                    .frame(maxHeight: .infinity)
            }
            .clipShape(Capsule())

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
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    beginPressIfNeeded()
                }
                .onEnded { _ in
                    finishPress()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Ride timer")
        .accessibilityValue(
            "\(RideMetrics.duration(TimeInterval(elapsedSeconds))), "
                + (ride.isPaused ? "paused" : "running")
        )
        .accessibilityHint("Hold to end the ride.")
        .accessibilityAction(named: "End Ride") {
            onEnd()
        }
    }

    private func beginPressIfNeeded() {
        guard !isPressing else { return }

        holdTask?.cancel()
        isPressing = true
        holdProgress = 0

        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1
        }

        holdTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(holdDuration))
            } catch {
                return
            }

            guard isPressing else { return }
            isPressing = false
            onEnd()

            withAnimation(.easeOut(duration: 0.15)) {
                holdProgress = 0
            }
        }
    }

    private func finishPress() {
        guard isPressing else { return }

        isPressing = false
        holdTask?.cancel()
        holdTask = nil

        withAnimation(.easeOut(duration: 0.15)) {
            holdProgress = 0
        }
    }
}

#Preview {
    HomeView(
        settings: AppSettings(),
        rideSession: RideSessionController()
    )
        .preferredColorScheme(.dark)
}

//
//  RideView.swift
//  Spoke
//

import SwiftUI
import CoreLocation

struct RideView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController
    let onEndRide: () -> Void

    @State private var resources: RideSessionResources?
    @State private var isShowingSkeleton = true

    var body: some View {
        NavigationStack {
            Group {
                if rideSession.activeRide == nil {
                    ContentUnavailableView {
                        Label("Ready to ride", systemImage: "figure.outdoor.cycle")
                    } description: {
                        Text("Your speed, route, and ride controls in one place.")
                    } actions: {
                        Button {
                            rideSession.startRide()
                        } label: {
                            Label("Start Ride", systemImage: "play.fill")
                        }
                        .buttonStyle(SpokePrimaryButtonStyle(minHeight: 64))
                        .padding(.horizontal, SpokeStyle.pageInset)
                    }
                    .background(SpokeStyle.background)
                } else {
                    ZStack {
                        if let resources {
                            RideDashboardView(
                                settings: settings,
                                rideSession: rideSession,
                                resources: resources
                            )
                        }

                        if resources == nil || isShowingSkeleton {
                            RideSkeletonView()
                                .transition(
                                    .asymmetric(
                                        insertion: .identity,
                                        removal: .opacity
                                    )
                                )
                                .zIndex(1)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(SpokeStyle.background.ignoresSafeArea())
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let ride = rideSession.activeRide {
                    RideControlsView(
                        ride: ride,
                        onPauseToggle: { rideSession.togglePause() },
                        onEnd: onEndRide
                    )
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.vertical, 12)
                    .background(SpokeStyle.background)
                }
            }
        }
        .task(id: rideSession.activeRide != nil) {
            guard rideSession.activeRide != nil else {
                isShowingSkeleton = true
                return
            }

            if resources == nil {
                await Task.yield()

                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    return
                }

                let preparedResources = await Task.detached(priority: .userInitiated) {
                    RideSessionResources()
                }.value

                guard !Task.isCancelled else { return }
                resources = preparedResources
            }

            guard isShowingSkeleton else { return }

            await Task.yield()

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }

            withAnimation(.easeOut(duration: 0.2)) {
                isShowingSkeleton = false
            }
        }
    }
}

private struct RideDashboardView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController

    @EnvironmentObject private var spotifyAuthentication: SpotifyAuthenticationStore
    @StateObject private var spotifyStore = SpotifyNowPlayingStore()
    private let overspeedAlertController: RideOverspeedAlertController
    @State private var developerSpeedInMilesPerHour = 0
    @State private var isDeveloperSpeedometerPressed = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let mapCameraDistance: CLLocationDistance = 700
    private let maximumDeveloperSpeedInMilesPerHour = 45

    init(
        settings: AppSettings?,
        rideSession: RideSessionController,
        resources: RideSessionResources
    ) {
        self.settings = settings
        self.rideSession = rideSession
        overspeedAlertController = resources.overspeedAlertController
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = RideLayoutMetrics(size: proxy.size)
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack(alignment: .top) {
                SpokeStyle.background
                    .ignoresSafeArea()

                if dynamicTypeSize.isAccessibilitySize || (!isLandscape && proxy.size.height < 500) {
                    ScrollView {
                        portraitLayout(metrics: metrics)
                            .frame(minHeight: 620)
                    }
                } else if isLandscape {
                    landscapeLayout(metrics: metrics)
                } else {
                    portraitLayout(metrics: metrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            isDeveloperSpeedometerPressed = false

            Task {
                await overspeedAlertController.stop()
            }
        }
        .task(id: overspeedAlertSpeed) {
            if let speed = overspeedAlertSpeed {
                await overspeedAlertController.update(speedInMilesPerHour: speed)
            } else {
                await overspeedAlertController.stop()
            }
        }
        .task(id: spotifyAuthentication.sessionID) {
            guard spotifyAuthentication.sessionID != nil else {
                spotifyStore.reset()
                return
            }

            await spotifyStore.monitor(
                authentication: spotifyAuthentication,
                onTrackChecked: { track in
                    rideSession.recordSpotifyCheck(track)
                }
            )
        }
    }

    private func portraitLayout(metrics: RideLayoutMetrics) -> some View {
        VStack(spacing: metrics.verticalSpacing) {
            rideStatus

            speedometer
                .frame(height: metrics.speedometerHeight)

            rideProgress

            currentLocationMap
                .frame(maxHeight: .infinity)

            spotifySection
                .frame(minHeight: metrics.spotifyHeight, alignment: .top)
        }
        .padding(.horizontal, SpokeStyle.pageInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private func landscapeLayout(metrics: RideLayoutMetrics) -> some View {
        HStack(spacing: metrics.verticalSpacing) {
            VStack(spacing: metrics.verticalSpacing) {
                rideStatus

                speedometer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                rideProgress
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: metrics.verticalSpacing) {
                currentLocationMap
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                spotifySection
                    .frame(minHeight: metrics.spotifyHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SpokeStyle.pageInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private var rideStatus: some View {
        Label(
            rideSession.activeRide?.isPaused == true ? "Paused" : "Riding",
            systemImage: rideSession.activeRide?.isPaused == true ? "pause.circle.fill" : "record.circle"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(rideSession.activeRide?.isPaused == true ? SpokeStyle.caution : SpokeStyle.accent)
        .frame(minHeight: 24)
    }

    private var overspeedAlertSpeed: Int? {
        rideSession.activeRide?.isPaused == true ? nil : displayedSpeedInMilesPerHour
    }

    private var isDeveloperModeEnabled: Bool {
        settings?.developerModeEnabled == true
    }

    private var displayedSpeedInMilesPerHour: Int {
        isDeveloperModeEnabled
            ? developerSpeedInMilesPerHour
            : rideSession.speedInMilesPerHour
    }

    @ViewBuilder
    private var spotifySection: some View {
        if spotifyAuthentication.sessionID == nil {
            SpotifyStatusView(
                symbol: "music.note",
                message: "Connect Spotify in Settings to see your music."
            )
        } else {
            switch spotifyStore.state {
            case .idle, .loading:
                SpotifyStatusView(symbol: "music.note", message: "Loading Spotify…")
            case .notPlaying:
                SpotifyPausedView()
            case .failed(let message):
                SpotifyStatusView(symbol: "exclamationmark.triangle.fill", message: message)
            case .playing(let track):
                SpotifyNowPlayingView(track: track)
            }
        }
    }

    private var currentLocationMap: some View {
        RideHUDMapView(
            initialMapState: rideSession.currentMapState,
            cameraDistance: mapCameraDistance
        )
        .clipShape(.rect(cornerRadius: SpokeStyle.cardRadius))
        .accessibilityLabel("Current location map")
    }

    private var rideProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 16) {
                progressMetric(
                    "Distance",
                    value: RideMetrics.distance(activeRideDistanceInMeters)
                )
                Rectangle()
                    .fill(SpokeStyle.separator)
                    .frame(width: 1, height: 40)
                progressMetric(
                    "Time",
                    value: RideMetrics.duration(activeRideElapsedDuration(at: max(context.date, .now)))
                )
            }
        }
    }

    private func progressMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpokeStyle.secondaryText)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SpokeStyle.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var activeRideDistanceInMeters: CLLocationDistance {
        guard let activeRide = rideSession.activeRide else { return 0 }
        return RideMetrics.distanceInMeters(for: activeRide)
    }

    private func activeRideElapsedDuration(at date: Date) -> TimeInterval {
        rideSession.activeRide?.elapsedDuration(at: date) ?? 0
    }

    private var speedometer: some View {
        GeometryReader { proxy in
            let arcWidth = min(max(proxy.size.width - 24, 0), proxy.size.height * 2)
            let arcHeight = arcWidth / 2
            let speed = displayedSpeedInMilesPerHour

            ZStack(alignment: .bottom) {
                SpeedometerArc()
                    .stroke(
                        SpokeStyle.elevatedSurface,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                SpeedometerArc()
                    .trim(from: 0, to: min(CGFloat(speed) / 30, 1))
                    .stroke(
                        arcColor(for: speed),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                VStack(spacing: 2) {
                    Text(String(speed))
                        .font(
                            .system(
                                size: min(112, arcWidth * 0.34),
                                weight: .bold
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Text("mph")
                        .font(.headline)
                        .foregroundStyle(SpokeStyle.secondaryText)
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(SpokeStyle.text)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isDeveloperModeEnabled else { return }
                    isDeveloperSpeedometerPressed = true
                }
                .onEnded { _ in
                    guard isDeveloperModeEnabled else { return }
                    isDeveloperSpeedometerPressed = false
                }
        )
        .task(
            id: DeveloperSpeedControlState(
                isEnabled: isDeveloperModeEnabled,
                isPressed: isDeveloperSpeedometerPressed
            )
        ) {
            await runDeveloperSpeedControl()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(displayedSpeedInMilesPerHour) miles per hour")
    }

    private func runDeveloperSpeedControl() async {
        guard isDeveloperModeEnabled else {
            developerSpeedInMilesPerHour = 0
            isDeveloperSpeedometerPressed = false
            return
        }

        while !Task.isCancelled {
            if isDeveloperSpeedometerPressed {
                developerSpeedInMilesPerHour = min(
                    developerSpeedInMilesPerHour + 1,
                    maximumDeveloperSpeedInMilesPerHour
                )
            } else if developerSpeedInMilesPerHour > 0 {
                developerSpeedInMilesPerHour -= 1
            } else {
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
    }

    private func arcColor(for speed: Int) -> Color {
        switch speed {
        case ..<20:
            SpokeStyle.accent
        case 20..<25:
            SpokeStyle.caution
        default:
            SpokeStyle.danger
        }
    }
}

private struct DeveloperSpeedControlState: Equatable {
    let isEnabled: Bool
    let isPressed: Bool
}

private struct RideSkeletonView: View {
    var body: some View {
        GeometryReader { proxy in
            let metrics = RideLayoutMetrics(size: proxy.size)
            let isLandscape = proxy.size.width > proxy.size.height

            Group {
                if isLandscape {
                    landscapeSkeleton(metrics: metrics)
                } else {
                    portraitSkeleton(metrics: metrics)
                }
            }
            .opacity(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SpokeStyle.background)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Ride")
    }

    private func portraitSkeleton(metrics: RideLayoutMetrics) -> some View {
        VStack(spacing: metrics.verticalSpacing) {
            speedometerSkeleton
                .frame(height: metrics.speedometerHeight)

            mapSkeleton
                .frame(maxHeight: .infinity)

            spotifySkeleton
                .frame(height: metrics.spotifyHeight, alignment: .top)
        }
        .padding(.horizontal, SpokeStyle.pageInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private func landscapeSkeleton(metrics: RideLayoutMetrics) -> some View {
        HStack(spacing: metrics.verticalSpacing) {
            VStack(spacing: metrics.verticalSpacing) {
                speedometerSkeleton
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                spotifySkeleton
                    .frame(height: metrics.spotifyHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            mapSkeleton
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, SpokeStyle.pageInset)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private var mapSkeleton: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.white.opacity(0.1))
    }

    private var speedometerSkeleton: some View {
        GeometryReader { proxy in
            let arcWidth = min(max(proxy.size.width - 24, 0), proxy.size.height * 2)
            let arcHeight = arcWidth / 2

            ZStack(alignment: .bottom) {
                SpeedometerArc()
                    .stroke(
                        .white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: min(116, arcWidth * 0.36), height: 54)

                    Capsule()
                        .fill(SpokeStyle.elevatedSurface)
                        .frame(width: 36, height: 10)
                }
                .padding(.bottom, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var spotifySkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.16))
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 10) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(maxWidth: 170)
                    .frame(height: 13)

                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(maxWidth: 104)
                    .frame(height: 11)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

private struct RideLayoutMetrics {
    let topInset: CGFloat = 10
    let bottomInset: CGFloat = 10
    let verticalSpacing: CGFloat = 12
    let spotifyHeight: CGFloat = 76
    let speedometerHeight: CGFloat

    init(size: CGSize) {
        let availableFeatureHeight = max(
            size.height
                - topInset
                - bottomInset
                - (verticalSpacing * 4)
                - 86
                - spotifyHeight,
            0
        )
        speedometerHeight = min(180, max(126, availableFeatureHeight * 0.5))
    }
}

private struct RideSessionResources: Sendable {
    let overspeedAlertController: RideOverspeedAlertController

    nonisolated init() {
        let alertPlayer = RideOverspeedAlertPlayer(
            resourceURL: Bundle.main.url(
                forResource: "overspeed-alert",
                withExtension: "mp3"
            )
        )
        overspeedAlertController = RideOverspeedAlertController(player: alertPlayer)
    }
}

private struct SpeedometerArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let curveOffset = radius * 0.552_284_749_8
        var path = Path()

        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - radius),
            control1: CGPoint(x: center.x - radius, y: center.y - curveOffset),
            control2: CGPoint(x: center.x - curveOffset, y: center.y - radius)
        )
        path.addCurve(
            to: CGPoint(x: center.x + radius, y: center.y),
            control1: CGPoint(x: center.x + curveOffset, y: center.y - radius),
            control2: CGPoint(x: center.x + radius, y: center.y - curveOffset)
        )

        return path
    }
}

#Preview {
    RideView(
        settings: AppSettings(),
        rideSession: RideSessionController(),
        onEndRide: {}
    )
        .environmentObject(SpotifyAuthenticationStore())
        .preferredColorScheme(.dark)
}

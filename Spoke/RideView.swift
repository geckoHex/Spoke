//
//  RideView.swift
//  Spoke
//

import SwiftUI
import CoreLocation
import Combine
import MapKit
import UIKit

struct RideView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController

    @State private var resources: RideSessionResources?
    @State private var isShowingSkeleton = true

    var body: some View {
        NavigationStack {
            Group {
                if rideSession.activeRide == nil {
                    ZStack {
                        Color.black
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            Image(systemName: "figure.outdoor.cycle")
                                .font(.system(size: 52, weight: .medium))

                            Text("No ride active")
                                .font(.title2.weight(.semibold))
                        }
                        .foregroundStyle(.white)

                        VStack {
                            Spacer()

                            Text("Visit the home tab to start a ride")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.bottom, 24)
                        }
                    }
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
                                .transition(.opacity)
                                .zIndex(1)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(Color.black.ignoresSafeArea())
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

    @Environment(\.displayScale) private var displayScale
    @StateObject private var spotifyStore: SpotifyNowPlayingStore
    @StateObject private var mapStore: RideMapSnapshotStore
    private let overspeedAlertController: RideOverspeedAlertController
    @State private var developerSpeedInMilesPerHour = 0
    @State private var isDeveloperSpeedometerPressed = false

    private let mapCameraDistance: CLLocationDistance = 700
    private let maximumDeveloperSpeedInMilesPerHour = 45

    init(
        settings: AppSettings?,
        rideSession: RideSessionController,
        resources: RideSessionResources
    ) {
        self.settings = settings
        self.rideSession = rideSession
        _spotifyStore = StateObject(
            wrappedValue: SpotifyNowPlayingStore(client: resources.spotifyClient)
        )
        _mapStore = StateObject(
            wrappedValue: RideMapSnapshotStore(renderer: resources.mapRenderer)
        )
        overspeedAlertController = resources.overspeedAlertController
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = RideLayoutMetrics(size: proxy.size)
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack(alignment: .top) {
                Color.black
                    .ignoresSafeArea()

                if isLandscape {
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
        .onChange(of: displayedSpeedInMilesPerHour, initial: true) { _, speed in
            Task {
                await overspeedAlertController.update(speedInMilesPerHour: speed)
            }
        }
        .task(id: spotifyCredentials) {
            guard let spotifyCredentials else {
                await spotifyStore.reset()
                return
            }

            await spotifyStore.monitor(credentials: spotifyCredentials) { refreshToken in
                settings?.spotifyRefreshToken = refreshToken
            }
        }
    }

    private func portraitLayout(metrics: RideLayoutMetrics) -> some View {
        VStack(spacing: metrics.verticalSpacing) {
            speedometer
                .frame(height: metrics.speedometerHeight)

            currentLocationMap
                .frame(maxHeight: .infinity)

            spotifySection
                .frame(height: metrics.spotifyHeight, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private func landscapeLayout(metrics: RideLayoutMetrics) -> some View {
        HStack(spacing: metrics.verticalSpacing) {
            VStack(spacing: metrics.verticalSpacing) {
                speedometer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                spotifySection
                    .frame(height: metrics.spotifyHeight, alignment: .top)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            currentLocationMap
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private var spotifyCredentials: SpotifyCredentials? {
        guard let settings else { return nil }
        return SpotifyCredentials(settings: settings)
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
        if spotifyCredentials == nil {
            SpotifyStatusView(
                symbol: "exclamationmark.triangle.fill",
                message: "Spotify credentials are missing. Add them in Settings."
            )
        } else {
            switch spotifyStore.state {
            case .idle, .loading:
                SpotifyStatusView(symbol: "music.note", message: "Loading Spotify…")
            case .notPlaying:
                SpotifyStatusView(symbol: "music.note", message: "Nothing is playing on Spotify.")
            case .failed(let message):
                SpotifyStatusView(symbol: "exclamationmark.triangle.fill", message: message)
            case .playing(let track):
                SpotifyNowPlayingView(track: track)
            }
        }
    }

    private var currentLocationMap: some View {
        GeometryReader { proxy in
            let request = rideSession.currentLocation.map {
                RideMapSnapshotRequest(
                    location: $0,
                    size: proxy.size,
                    scale: displayScale,
                    cameraDistance: mapCameraDistance
                )
            }

            ZStack {
                mapLoadingPlaceholder

                if let image = mapStore.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)

                    Circle()
                        .fill(Color(uiColor: .systemBlue))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 3)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .accessibilityHidden(true)
                }
            }
            .task(id: request) {
                guard let request else { return }
                await mapStore.load(request)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityLabel("Current location map")
    }

    private var mapLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 34, weight: .medium))

            Text("Loading Map")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .opacity(mapStore.image == nil ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    private var speedometer: some View {
        GeometryReader { proxy in
            let arcWidth = min(max(proxy.size.width - 24, 0), proxy.size.height * 2)
            let arcHeight = arcWidth / 2
            let speed = displayedSpeedInMilesPerHour

            ZStack(alignment: .bottom) {
                SpeedometerArc()
                    .stroke(
                        .white.opacity(0.14),
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
                    .animation(.smooth(duration: 0.45), value: speed)

                VStack(spacing: 2) {
                    Text(String(format: "%02d", speed))
                        .font(
                            .system(
                                size: min(92, arcWidth * 0.29),
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(speed)))
                        .animation(.snappy(duration: 0.35), value: speed)

                    Text("mph")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
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
            .green
        case 20..<25:
            .yellow
        default:
            .red
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

            PhaseAnimator([false, true]) { isBright in
                Group {
                    if isLandscape {
                        landscapeSkeleton(metrics: metrics)
                    } else {
                        portraitSkeleton(metrics: metrics)
                    }
                }
                .opacity(isBright ? 0.72 : 0.38)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
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
        .padding(.horizontal, 20)
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
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            mapSkeleton
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, metrics.topInset)
        .padding(.bottom, metrics.bottomInset)
    }

    private var mapSkeleton: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
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
                        .fill(.white.opacity(0.14))
                        .frame(width: 36, height: 10)
                }
                .padding(.bottom, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var spotifySkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
    let topInset: CGFloat = 16
    let bottomInset: CGFloat = 10
    let verticalSpacing: CGFloat = 14
    let spotifyHeight: CGFloat = 96
    let speedometerHeight: CGFloat

    init(size: CGSize) {
        let availableFeatureHeight = max(
            size.height
                - topInset
                - bottomInset
                - (verticalSpacing * 2)
                - spotifyHeight,
            0
        )
        speedometerHeight = min(176, max(116, availableFeatureHeight * 0.305))
    }
}

private struct RideSessionResources: Sendable {
    let spotifyClient: SpotifyAPIClient
    let mapRenderer: RideMapSnapshotRenderer
    let overspeedAlertController: RideOverspeedAlertController

    nonisolated init() {
        spotifyClient = SpotifyAPIClient()
        mapRenderer = RideMapSnapshotRenderer()
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

private struct RideMapSnapshotRequest: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let width: Double
    let height: Double
    let scale: Double
    let cameraDistance: Double

    init(
        location: RideLocationSample,
        size: CGSize,
        scale: CGFloat,
        cameraDistance: CLLocationDistance
    ) {
        latitude = (location.latitude * 10_000).rounded() / 10_000
        longitude = (location.longitude * 10_000).rounded() / 10_000
        width = max(size.width.rounded(.up), 1)
        height = max(size.height.rounded(.up), 1)
        self.scale = scale
        self.cameraDistance = cameraDistance
    }
}

private actor RideMapSnapshotRenderer {
    func render(_ request: RideMapSnapshotRequest) async throws -> UIImage {
        try Task.checkCancellation()

        let options = MKMapSnapshotter.Options()
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll

        options.preferredConfiguration = configuration
        options.camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: request.latitude,
                longitude: request.longitude
            ),
            fromDistance: request.cameraDistance,
            pitch: 0,
            heading: 0
        )
        options.size = CGSize(width: request.width, height: request.height)
        options.scale = request.scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await withTaskCancellationHandler {
            try await snapshotter.start()
        } onCancel: {
            snapshotter.cancel()
        }

        try Task.checkCancellation()
        return snapshot.image
    }
}

private final class RideMapSnapshotStore: ObservableObject {
    @Published private(set) var image: UIImage?

    private let renderer: RideMapSnapshotRenderer

    init(renderer: RideMapSnapshotRenderer) {
        self.renderer = renderer
    }

    func load(_ request: RideMapSnapshotRequest) async {
        do {
            let renderedImage = try await renderer.render(request)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                image = renderedImage
            }
        } catch {
            // Keep the existing snapshot while a newer request is rendered.
        }
    }
}

#Preview {
    RideView(
        settings: AppSettings(),
        rideSession: RideSessionController()
    )
        .preferredColorScheme(.dark)
}

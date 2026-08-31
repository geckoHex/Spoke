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
                    ContentUnavailableView(
                        "No Active Ride",
                        systemImage: "figure.outdoor.cycle",
                        description: Text("Start a ride from Home to see live metrics.")
                    )
                    .background(Color.black)
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
    private let speedAnnouncer: RideSpeedAnnouncer
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
        speedAnnouncer = resources.speedAnnouncer
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
                await speedAnnouncer.stop()
            }
        }
        .onChange(of: displayedSpeedInMilesPerHour, initial: true) { _, speed in
            Task {
                await overspeedAlertController.update(speedInMilesPerHour: speed)
            }
        }
        .task(id: settings?.speakSpeedEnabled == true) {
            guard settings?.speakSpeedEnabled == true else {
                await speedAnnouncer.stop()
                return
            }

            await runSpeedAnnouncements()
        }
        .task(id: spotifyCredentials) {
            guard let spotifyCredentials else {
                await spotifyStore.reset()
                return
            }

            await spotifyStore.monitor(
                credentials: spotifyCredentials,
                onRefreshToken: { refreshToken in
                    settings?.spotifyRefreshToken = refreshToken
                },
                onTrackChecked: { track in
                    rideSession.recordSpotifyCheck(track)
                }
            )
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

    private func runSpeedAnnouncements() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                break
            }

            await speedAnnouncer.play(
                speedInMilesPerHour: displayedSpeedInMilesPerHour
            )
        }

        await speedAnnouncer.stop()
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
                SpotifyPausedView()
            case .failed(let message):
                SpotifyStatusView(symbol: "exclamationmark.triangle.fill", message: message)
            case .playing(let track):
                SpotifyNowPlayingView(track: track)
            }
        }
    }

    private var currentLocationMap: some View {
        GeometryReader { proxy in
            let request = rideSession.currentMapState.map {
                RideMapSnapshotRequest(
                    mapState: $0,
                    routePoints: rideSession.activeRide?.routePoints ?? [],
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
                        .contrast(1.18)

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

                distanceBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
            .task(id: request) {
                guard let request else { return }
                await mapStore.load(request)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Current location map")
    }

    private var distanceBadge: some View {
        let distanceInMeters = activeRideDistanceInMeters

        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedDuration = activeRideElapsedDuration(
                at: max(context.date, Date.now)
            )

            VStack(alignment: .trailing, spacing: 5) {
                Text(RideMetrics.distance(distanceInMeters))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Image(systemName: "stopwatch")

                    Text(RideMetrics.duration(elapsedDuration))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ride progress")
            .accessibilityValue(
                "\(RideMetrics.miles(distanceInMeters)) miles, ride time "
                    + RideMetrics.duration(elapsedDuration)
            )
        }
    }

    private var activeRideDistanceInMeters: CLLocationDistance {
        guard let activeRide = rideSession.activeRide else { return 0 }
        return RideMetrics.distanceInMeters(for: activeRide)
    }

    private func activeRideElapsedDuration(at date: Date) -> TimeInterval {
        rideSession.activeRide?.elapsedDuration(at: date) ?? 0
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
                        style: StrokeStyle(lineWidth: 11, lineCap: .butt)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                SpeedometerArc()
                    .trim(from: 0, to: min(CGFloat(speed) / 30, 1))
                    .stroke(
                        arcColor(for: speed),
                        style: StrokeStyle(lineWidth: 11, lineCap: .butt)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                VStack(spacing: 2) {
                    Text(String(speed))
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

            Group {
                if isLandscape {
                    landscapeSkeleton(metrics: metrics)
                } else {
                    portraitSkeleton(metrics: metrics)
                }
            }
            .opacity(0.55)
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
                        style: StrokeStyle(lineWidth: 11, lineCap: .butt)
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
    let speedAnnouncer: RideSpeedAnnouncer

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
        speedAnnouncer = RideSpeedAnnouncer()
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
    let heading: Double
    let route: [RideMapRouteCoordinate]

    init(
        mapState: RideMapState,
        routePoints: [RideRoutePoint],
        size: CGSize,
        scale: CGFloat,
        cameraDistance: CLLocationDistance
    ) {
        let location = mapState.location
        latitude = (location.latitude * 10_000).rounded() / 10_000
        longitude = (location.longitude * 10_000).rounded() / 10_000
        width = max(size.width.rounded(.up), 1)
        height = max(size.height.rounded(.up), 1)
        self.scale = scale
        self.cameraDistance = cameraDistance
        heading = ((mapState.heading ?? 0) / 5).rounded() * 5
        route = routePoints
            .sorted { $0.recordedAt < $1.recordedAt }
            .map {
                RideMapRouteCoordinate(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            } + [
                RideMapRouteCoordinate(
                    latitude: latitude,
                    longitude: longitude
                )
            ]
    }
}

private struct RideMapRouteCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

private actor RideMapSnapshotRenderer {
    func render(_ request: RideMapSnapshotRequest) async throws -> UIImage {
        try Task.checkCancellation()

        let options = MKMapSnapshotter.Options()
        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .default
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
            heading: request.heading
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
        guard request.route.count > 1 else { return snapshot.image }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = snapshot.image.scale
        rendererFormat.opaque = true

        return UIGraphicsImageRenderer(
            size: snapshot.image.size,
            format: rendererFormat
        ).image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (index, routePoint) in request.route.enumerated() {
                let point = snapshot.point(
                    for: CLLocationCoordinate2D(
                        latitude: routePoint.latitude,
                        longitude: routePoint.longitude
                    )
                )

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.white.withAlphaComponent(0.96).setStroke()
            path.stroke()
        }
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

            image = renderedImage
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

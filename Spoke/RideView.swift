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

    @State private var resources: RideSessionResources?
    @State private var isShowingSkeleton = true

    var body: some View {
        NavigationStack {
            ZStack {
                if let resources {
                    RideDashboardView(settings: settings, resources: resources)
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
        .task {
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

    @Environment(\.displayScale) private var displayScale
    @StateObject private var speedTracker: RideSpeedTracker
    @StateObject private var spotifyStore: SpotifyNowPlayingStore
    @StateObject private var mapStore: RideMapSnapshotStore

    private let mapCameraDistance: CLLocationDistance = 700

    init(settings: AppSettings?, resources: RideSessionResources) {
        self.settings = settings
        _speedTracker = StateObject(
            wrappedValue: RideSpeedTracker(processor: resources.speedProcessor)
        )
        _spotifyStore = StateObject(
            wrappedValue: SpotifyNowPlayingStore(client: resources.spotifyClient)
        )
        _mapStore = StateObject(
            wrappedValue: RideMapSnapshotStore(renderer: resources.mapRenderer)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = RideLayoutMetrics(size: proxy.size)

            ZStack(alignment: .top) {
                Color.black
                    .ignoresSafeArea()

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            speedTracker.start()
        }
        .onDisappear {
            speedTracker.stop()
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

    private var spotifyCredentials: SpotifyCredentials? {
        guard let settings else { return nil }
        return SpotifyCredentials(settings: settings)
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
            let request = speedTracker.currentLocation.map {
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
            let speed = speedTracker.speedInMilesPerHour

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(speedTracker.speedInMilesPerHour) miles per hour")
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

private struct RideSkeletonView: View {
    var body: some View {
        GeometryReader { proxy in
            let metrics = RideLayoutMetrics(size: proxy.size)

            PhaseAnimator([false, true]) { isBright in
                VStack(spacing: metrics.verticalSpacing) {
                    speedometerSkeleton
                        .frame(height: metrics.speedometerHeight)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .frame(maxHeight: .infinity)

                    spotifySkeleton
                        .frame(height: metrics.spotifyHeight, alignment: .top)
                }
                .opacity(isBright ? 0.72 : 0.38)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .padding(.horizontal, 20)
            .padding(.top, metrics.topInset)
            .padding(.bottom, metrics.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Ride")
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
    let speedProcessor: RideSpeedProcessor
    let spotifyClient: SpotifyAPIClient
    let mapRenderer: RideMapSnapshotRenderer

    nonisolated init() {
        speedProcessor = RideSpeedProcessor()
        spotifyClient = SpotifyAPIClient()
        mapRenderer = RideMapSnapshotRenderer()
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

private final class RideSpeedTracker: ObservableObject {
    @Published private(set) var speedInMilesPerHour = 0
    @Published private(set) var currentLocation: RideLocationSample?

    private let processor: RideSpeedProcessor
    private var updateTask: Task<Void, Never>?
    private var sessionGeneration = 0

    init(processor: RideSpeedProcessor) {
        self.processor = processor
    }

    func start() {
        guard updateTask == nil else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        let publish: @MainActor @Sendable (RideSpeedUpdate) -> Void = { [weak self] update in
            guard let self,
                  self.updateTask != nil,
                  self.sessionGeneration == generation
            else { return }

            if let mapLocation = update.mapLocation {
                self.currentLocation = mapLocation
            }
            if let speedInMilesPerHour = update.speedInMilesPerHour {
                self.speedInMilesPerHour = speedInMilesPerHour
            }
        }

        updateTask = Task.detached(priority: .userInitiated) { [processor] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    try Task.checkCancellation()
                    guard let location = update.location else { continue }

                    let processedUpdate = await processor.process(
                        [RideLocationSample(location: location)],
                        now: Date()
                    )
                    await publish(processedUpdate)
                }
            } catch {
                // Cancellation and unavailable location updates both end this session quietly.
            }
        }
    }

    func stop() {
        sessionGeneration += 1
        updateTask?.cancel()
        updateTask = nil
        speedInMilesPerHour = 0
        currentLocation = nil

        Task {
            await processor.reset()
        }
    }
}

private actor RideSpeedProcessor {
    private let metersPerSecondToMilesPerHour = 2.236_936_292_1
    private let maximumLocationAge: TimeInterval = 2
    private let maximumMapHorizontalAccuracy: CLLocationAccuracy = 100
    private let maximumHorizontalAccuracy: CLLocationAccuracy = 25
    private let maximumSpeedAccuracy: CLLocationSpeedAccuracy = 3
    private let maximumCyclingSpeed: CLLocationSpeed = 45
    private let maximumCyclingAcceleration: CLLocationSpeed = 4
    private let smoothingTimeConstant: TimeInterval = 0.35
    private let stationarySpeed: CLLocationSpeed = 0.45

    private var filteredSpeed: CLLocationSpeed?
    private var lastAcceptedSample: RideLocationSample?

    func process(_ samples: [RideLocationSample], now: Date) -> RideSpeedUpdate {
        let mapLocation = samples.last { isValidForMap($0, now: now) }
        var newestFilteredSpeed: CLLocationSpeed?

        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard isValid(sample, now: now), isPlausible(sample) else { continue }

            newestFilteredSpeed = smooth(sample)
            lastAcceptedSample = sample
        }

        let speed = newestFilteredSpeed.map {
            Int(($0 * metersPerSecondToMilesPerHour).rounded())
        }

        return RideSpeedUpdate(
            mapLocation: mapLocation,
            speedInMilesPerHour: speed
        )
    }

    func reset() {
        filteredSpeed = nil
        lastAcceptedSample = nil
    }

    private func isValid(_ sample: RideLocationSample, now: Date) -> Bool {
        let age = now.timeIntervalSince(sample.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && sample.horizontalAccuracy >= 0
            && sample.horizontalAccuracy <= maximumHorizontalAccuracy
            && sample.speed >= 0
            && sample.speed <= maximumCyclingSpeed
            && sample.speedAccuracy >= 0
            && sample.speedAccuracy <= maximumSpeedAccuracy
    }

    private func isValidForMap(_ sample: RideLocationSample, now: Date) -> Bool {
        let age = now.timeIntervalSince(sample.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && sample.horizontalAccuracy >= 0
            && sample.horizontalAccuracy <= maximumMapHorizontalAccuracy
    }

    private func isPlausible(_ sample: RideLocationSample) -> Bool {
        guard let previous = lastAcceptedSample else { return true }

        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }

        let expectedChange = maximumCyclingAcceleration * elapsed
        let uncertainty = sample.speedAccuracy + previous.speedAccuracy

        return abs(sample.speed - previous.speed) <= expectedChange + uncertainty
    }

    private func smooth(_ sample: RideLocationSample) -> CLLocationSpeed {
        let measuredSpeed = sample.speed < stationarySpeed ? 0 : sample.speed

        guard let filteredSpeed,
              let previous = lastAcceptedSample
        else {
            self.filteredSpeed = measuredSpeed
            return measuredSpeed
        }

        let elapsed = max(sample.timestamp.timeIntervalSince(previous.timestamp), 0.05)
        let timeWeight = 1 - exp(-elapsed / smoothingTimeConstant)
        let accuracyRatio = min(sample.speedAccuracy / maximumSpeedAccuracy, 1)
        let accuracyWeight = 1 - (accuracyRatio * 0.25)
        var weight = min(max(timeWeight * accuracyWeight, 0.35), 1)

        if abs(measuredSpeed - filteredSpeed) >= 2 {
            weight = max(weight, 0.8)
        }

        let smoothedSpeed = filteredSpeed + ((measuredSpeed - filteredSpeed) * weight)
        self.filteredSpeed = smoothedSpeed
        return smoothedSpeed
    }
}

private struct RideLocationSample: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
    let speedAccuracy: CLLocationSpeedAccuracy
    let timestamp: Date

    nonisolated init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        timestamp = location.timestamp
    }
}

private struct RideSpeedUpdate: Sendable {
    let mapLocation: RideLocationSample?
    let speedInMilesPerHour: Int?
}

#Preview {
    RideView(settings: AppSettings())
        .preferredColorScheme(.dark)
}

//
//  RideView.swift
//  Spoke
//

import SwiftUI
import CoreLocation
import Combine
import MapKit

struct RideView: View {
    let settings: AppSettings?

    @StateObject private var speedTracker = RideSpeedTracker()
    @StateObject private var spotifyStore = SpotifyNowPlayingStore()
    @State private var shouldCreateMap = false
    @State private var isMapLoaded = false

    private let mapCameraDistance: CLLocationDistance = 700

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let topInset: CGFloat = 20
                let bottomInset: CGFloat = 12
                let verticalSpacing: CGFloat = 16
                let spotifyHeight: CGFloat = 108
                let availableFeatureHeight = max(
                    proxy.size.height
                        - topInset
                        - bottomInset
                        - (verticalSpacing * 2)
                        - spotifyHeight,
                    0
                )
                let speedometerHeight = min(
                    190,
                    max(108, availableFeatureHeight * 0.32)
                )

                ZStack(alignment: .top) {
                    Color.black
                        .ignoresSafeArea()

                    VStack(spacing: verticalSpacing) {
                        speedometer
                            .frame(height: speedometerHeight)

                        currentLocationMap
                            .frame(maxHeight: .infinity)

                        spotifySection
                            .frame(height: spotifyHeight, alignment: .top)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                speedTracker.start()
            }
            .task {
                guard !shouldCreateMap else { return }

                await Task.yield()

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }

                shouldCreateMap = true
            }
            .onDisappear {
                speedTracker.stop()
            }
            .task(id: spotifyCredentials) {
                guard let spotifyCredentials else {
                    spotifyStore.reset()
                    return
                }

                await spotifyStore.monitor(credentials: spotifyCredentials) { refreshToken in
                    settings?.spotifyRefreshToken = refreshToken
                }
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
        ZStack {
            mapLoadingPlaceholder

            if shouldCreateMap {
                CurrentLocationMap(
                    location: speedTracker.currentLocation,
                    cameraDistance: mapCameraDistance
                ) {
                    isMapLoaded = true
                }
                .opacity(isMapLoaded ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white, lineWidth: 2)
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
        .opacity(isMapLoaded ? 0 : 1)
        .accessibilityElement(children: .combine)
    }

    private var speedometer: some View {
        GeometryReader { proxy in
            let arcWidth = min(proxy.size.width, proxy.size.height * 2)
            let arcHeight = arcWidth / 2
            let speed = speedTracker.speedInMilesPerHour

            ZStack(alignment: .bottom) {
                SpeedometerArc()
                    .stroke(
                        .white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcHeight)

                SpeedometerArc()
                    .trim(from: 0, to: min(CGFloat(speed) / 30, 1))
                    .stroke(
                        arcColor(for: speed),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcHeight)
                    .animation(.smooth(duration: 0.45), value: speed)

                VStack(spacing: 2) {
                    Text(String(format: "%02d", speed))
                        .font(
                            .system(
                                size: min(88, arcWidth * 0.29),
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(speed)))
                        .animation(.snappy(duration: 0.35), value: speed)

                    Text("mph")
                        .font(.headline.weight(.semibold))
                }
                .padding(.bottom, 2)
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

private struct CurrentLocationMap: UIViewRepresentable {
    let location: CLLocation?
    let cameraDistance: CLLocationDistance
    let onInitialLoad: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInitialLoad: onInitialLoad)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.showsUserLocation = true
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onInitialLoad = onInitialLoad

        guard let location,
              context.coordinator.lastCenteredLocationTimestamp != location.timestamp
        else { return }

        let shouldAnimate = context.coordinator.lastCenteredLocationTimestamp != nil
        context.coordinator.lastCenteredLocationTimestamp = location.timestamp
        mapView.setCamera(
            MKMapCamera(
                lookingAtCenter: location.coordinate,
                fromDistance: cameraDistance,
                pitch: 0,
                heading: 0
            ),
            animated: shouldAnimate
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onInitialLoad: () -> Void
        var lastCenteredLocationTimestamp: Date?
        private var didCompleteInitialLoad = false

        init(onInitialLoad: @escaping () -> Void) {
            self.onInitialLoad = onInitialLoad
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            completeInitialLoad()
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: any Error) {
            completeInitialLoad()
        }

        private func completeInitialLoad() {
            guard !didCompleteInitialLoad else { return }
            didCompleteInitialLoad = true
            onInitialLoad()
        }
    }
}

private final class RideSpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var speedInMilesPerHour = 0
    @Published private(set) var currentLocation: CLLocation?

    private let locationManager = CLLocationManager()
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
    private var lastAcceptedSample: SpeedSample?
    private var isActive = false
    private var isUpdating = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        isActive = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        isActive = false
        locationManager.stopUpdatingLocation()
        isUpdating = false
        filteredSpeed = nil
        lastAcceptedSample = nil
        speedInMilesPerHour = 0
        currentLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isActive else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            isUpdating = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let newestMapLocation = locations.last(where: isValidForMap) {
            currentLocation = newestMapLocation
        }

        var newestFilteredSpeed: CLLocationSpeed?

        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard isValid(location) else { continue }

            let sample = SpeedSample(location: location)
            guard isPlausible(sample) else { continue }

            newestFilteredSpeed = smooth(sample)
            lastAcceptedSample = sample
        }

        guard let newestFilteredSpeed else { return }

        speedInMilesPerHour = Int(
            (newestFilteredSpeed * metersPerSecondToMilesPerHour).rounded()
        )
    }

    private func startUpdatingLocation() {
        guard isActive, !isUpdating else { return }
        locationManager.startUpdatingLocation()
        isUpdating = true
    }

    private func isValid(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && location.speed >= 0
            && location.speed <= maximumCyclingSpeed
            && location.speedAccuracy >= 0
            && location.speedAccuracy <= maximumSpeedAccuracy
    }

    private func isValidForMap(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)

        return (-1...maximumLocationAge).contains(age)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumMapHorizontalAccuracy
    }

    private func isPlausible(_ sample: SpeedSample) -> Bool {
        guard let previous = lastAcceptedSample else { return true }

        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }

        let expectedChange = maximumCyclingAcceleration * elapsed
        let uncertainty = sample.speedAccuracy + previous.speedAccuracy

        return abs(sample.speed - previous.speed) <= expectedChange + uncertainty
    }

    private func smooth(_ sample: SpeedSample) -> CLLocationSpeed {
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

private struct SpeedSample {
    let speed: CLLocationSpeed
    let speedAccuracy: CLLocationSpeedAccuracy
    let timestamp: Date

    init(location: CLLocation) {
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        timestamp = location.timestamp
    }
}

#Preview {
    RideView(settings: AppSettings())
        .preferredColorScheme(.dark)
}

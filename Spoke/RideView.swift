//
//  RideView.swift
//  Spoke
//

import SwiftUI
import CoreLocation
import Combine

struct RideView: View {
    @StateObject private var speedTracker = RideSpeedTracker()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let boxSide = min(
                    max(proxy.size.width - 40, 0),
                    max((proxy.size.height / 2) - 20, 0)
                )

                ZStack(alignment: .top) {
                    Color.black
                        .ignoresSafeArea()

                    speedBox(side: boxSide)
                        .frame(width: boxSide, height: boxSide)
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                speedTracker.start()
            }
            .onDisappear {
                speedTracker.stop()
            }
        }
    }

    private func speedBox(side: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(String(format: "%02d", speedTracker.speedInMilesPerHour))
                .font(
                    .system(
                        size: min(104, side * 0.3),
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(
                    .numericText(value: Double(speedTracker.speedInMilesPerHour))
                )
                .animation(
                    .snappy(duration: 0.35),
                    value: speedTracker.speedInMilesPerHour
                )

            Text("mph")
                .font(.headline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white, lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(speedTracker.speedInMilesPerHour) miles per hour")
    }
}

private final class RideSpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var speedInMilesPerHour = 0

    private let locationManager = CLLocationManager()
    private let minimumUpdateInterval: TimeInterval = 0.5
    private var lastPublishedAt: Date?
    private var isActive = false
    private var isUpdating = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
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
        lastPublishedAt = nil
        speedInMilesPerHour = 0
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
        guard let location = locations.last,
              location.speed >= 0,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 5
        else {
            return
        }

        let now = Date()
        if let lastPublishedAt,
           now.timeIntervalSince(lastPublishedAt) < minimumUpdateInterval {
            return
        }

        lastPublishedAt = now
        speedInMilesPerHour = Int((location.speed * 2.236_936_292_1).rounded())
    }

    private func startUpdatingLocation() {
        guard isActive, !isUpdating else { return }
        locationManager.startUpdatingLocation()
        isUpdating = true
    }
}

#Preview {
    RideView()
        .preferredColorScheme(.dark)
}

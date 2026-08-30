//
//  RideReplayView.swift
//  Spoke
//

import MapKit
import SwiftUI

struct RideReplayRoute {
    static let playbackDuration: TimeInterval = 10

    struct Point {
        let coordinate: CLLocationCoordinate2D
        let progress: Double
    }

    let points: [Point]

    init(points routePoints: [RideRoutePoint]) {
        let sortedPoints = routePoints.sorted { $0.recordedAt < $1.recordedAt }
        guard let firstPoint = sortedPoints.first else {
            points = []
            return
        }

        let recordedDuration = sortedPoints.last?.recordedAt
            .timeIntervalSince(firstPoint.recordedAt) ?? 0

        if recordedDuration > 0 {
            points = sortedPoints.map { point in
                Point(
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    progress: point.recordedAt
                        .timeIntervalSince(firstPoint.recordedAt) / recordedDuration
                )
            }
        } else {
            let progressDivisor = max(Double(sortedPoints.count - 1), 1)
            points = sortedPoints.enumerated().map { index, point in
                Point(
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    progress: Double(index) / progressDivisor
                )
            }
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    var firstCoordinate: CLLocationCoordinate2D? {
        points.first?.coordinate
    }

    var lastCoordinate: CLLocationCoordinate2D? {
        points.last?.coordinate
    }

    func coordinate(at progress: Double) -> CLLocationCoordinate2D? {
        guard let firstPoint = points.first else { return nil }
        guard progress > 0 else { return firstPoint.coordinate }
        guard progress < 1, let lastPoint = points.last else {
            return points.last?.coordinate
        }

        guard let upperIndex = points.firstIndex(where: { $0.progress >= progress }),
              upperIndex > 0
        else { return lastPoint.coordinate }

        let lowerPoint = points[upperIndex - 1]
        let upperPoint = points[upperIndex]
        let segmentDuration = upperPoint.progress - lowerPoint.progress
        guard segmentDuration > 0 else { return upperPoint.coordinate }

        let segmentProgress = (progress - lowerPoint.progress) / segmentDuration
        let lowerMapPoint = MKMapPoint(lowerPoint.coordinate)
        let upperMapPoint = MKMapPoint(upperPoint.coordinate)
        let interpolatedMapPoint = MKMapPoint(
            x: lowerMapPoint.x + (upperMapPoint.x - lowerMapPoint.x) * segmentProgress,
            y: lowerMapPoint.y + (upperMapPoint.y - lowerMapPoint.y) * segmentProgress
        )
        return interpolatedMapPoint.coordinate
    }
}

struct RideReplayView: View {
    private let route: RideReplayRoute

    @State private var currentCoordinate: CLLocationCoordinate2D?

    init(routePoints: [RideRoutePoint]) {
        let route = RideReplayRoute(points: routePoints)
        self.route = route
        _currentCoordinate = State(initialValue: route.firstCoordinate)
    }

    private var cameraPosition: MapCameraPosition {
        guard !route.coordinates.isEmpty else { return .automatic }

        let rect = route.coordinates.reduce(MKMapRect.null) {
            partialResult,
            coordinate in
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            return partialResult.union(pointRect)
        }
        let horizontalPadding = max(rect.size.width * 0.18, 500)
        let verticalPadding = max(rect.size.height * 0.18, 500)
        return .rect(
            rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        )
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: cameraPosition, interactionModes: []) {
                if let currentCoordinate {
                    Annotation(
                        "Bike position",
                        coordinate: currentCoordinate,
                        anchor: .bottom
                    ) {
                        ReplayBikePin()
                    }
                }
            }
            .mapStyle(
                .standard(
                    elevation: .flat,
                    emphasis: .muted,
                    pointsOfInterest: .excludingAll,
                    showsTraffic: false
                )
            )
            .navigationTitle("Replay")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await playRoute()
        }
    }

    private func playRoute() async {
        guard route.points.count > 1 else { return }

        let clock = ContinuousClock()
        let startedAt = clock.now

        while !Task.isCancelled {
            let elapsed = startedAt.duration(to: clock.now).timeInterval
            let progress = min(elapsed / RideReplayRoute.playbackDuration, 1)
            currentCoordinate = route.coordinate(at: progress)

            guard progress < 1 else { break }

            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
        }

        currentCoordinate = route.lastCoordinate
    }
}

private struct ReplayBikePin: View {
    var body: some View {
        ZStack {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            Image(systemName: "bicycle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .offset(y: -4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bike position")
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

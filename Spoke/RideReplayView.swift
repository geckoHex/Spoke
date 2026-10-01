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
    private let routeSegments: [RideRouteSegment]

    @Environment(\.dismiss) private var dismiss
    @State private var currentCoordinate: CLLocationCoordinate2D?
    @State private var isBikeFacingLeft = false

    init(routePoints: [RideRoutePoint]) {
        let route = RideReplayRoute(points: routePoints)
        self.route = route
        routeSegments = RideRouteSpeed.segments(for: routePoints)
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
        SpokeSheet(title: "Replay") {
            Map(initialPosition: cameraPosition, interactionModes: []) {
                ForEach(Array(routeSegments.enumerated()), id: \.offset) {
                    _, segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.motion.color, lineWidth: 5)
                }

                if let currentCoordinate {
                    Annotation(
                        "",
                        coordinate: currentCoordinate,
                        anchor: .bottom
                    ) {
                        ReplayBikeMarker(isFacingLeft: isBikeFacingLeft)
                            .accessibilityHidden(true)
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
        }
        .task {
            await playRoute()
        }
    }

    private func playRoute() async {
        if route.points.count > 1 {
            let clock = ContinuousClock()
            let startedAt = clock.now

            while !Task.isCancelled {
                let elapsed = startedAt.duration(to: clock.now).timeInterval
                let progress = min(elapsed / RideReplayRoute.playbackDuration, 1)
                let nextCoordinate = route.coordinate(at: progress)

                if let currentCoordinate, let nextCoordinate {
                    let currentX = MKMapPoint(currentCoordinate).x
                    let nextX = MKMapPoint(nextCoordinate).x

                    if nextX != currentX {
                        isBikeFacingLeft = nextX < currentX
                    }
                }

                currentCoordinate = nextCoordinate

                guard progress < 1 else { break }

                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }

        currentCoordinate = route.lastCoordinate

        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return
        }

        dismiss()
    }
}

private struct ReplayBikeMarker: View {
    let isFacingLeft: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ReplayBikePointerShape()
                .fill(SpokeStyle.text)
                .frame(width: 16, height: 12)
                .offset(y: 40)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(SpokeStyle.text)
                .frame(width: 44, height: 44)

            Image(systemName: "bicycle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SpokeStyle.background)
                .frame(width: 44, height: 44)
                .scaleEffect(x: isFacingLeft ? -1 : 1, y: 1)
        }
        .frame(width: 44, height: 52, alignment: .top)
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

private struct ReplayBikePointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension RideRouteMotion {
    var color: Color {
        switch self {
        case .normalOrFaster:
            SpokeStyle.accent
        case .slower:
            SpokeStyle.caution
        case .stopped:
            SpokeStyle.danger
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

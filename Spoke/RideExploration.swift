import MapKit

struct RideExploration {
    struct Path: Identifiable {
        let id: Int
        let isNew: Bool
        var coordinates: [CLLocationCoordinate2D]
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private(set) var paths: [Path] = []

    init(rides: [TrackedRide], since startDate: Date, now: Date) {
        let completed = rides.filter {
            guard let end = $0.endedAt else { return false }
            return $0.startedAt <= now && end >= $0.startedAt && end <= now
        }.sorted { $0.startedAt < $1.startedAt }
        var visited: [Cell: [MKMapPoint]] = [:]

        for ride in completed {
            var additions: [MKMapPoint] = []
            for segment in RideRecordedSegment.segments(for: ride) where segment.distance > 0 {
                guard abs(segment.start.latitude) < 85, abs(segment.end.latitude) < 85 else { continue }
                let start = MKMapPoint(segment.start)
                var end = MKMapPoint(segment.end)
                if abs(end.x - start.x) > MKMapRect.world.width / 2 {
                    end.x += end.x > start.x ? -MKMapRect.world.width : MKMapRect.world.width
                }
                // Do not draw a GPS jump as a newly explored street.
                guard segment.speed <= 60 else { continue }
                let steps = max(1, Int(ceil(segment.distance / 10)))
                var previous = start

                for step in 1...steps {
                    let fraction = Double(step) / Double(steps)
                    let point = MKMapPoint(x: start.x + (end.x - start.x) * fraction,
                                           y: start.y + (end.y - start.y) * fraction)
                    let midpoint = MKMapPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                    // shortcut: Match GPS paths within 20 m; use a street network if parallel-road identity is required.
                    let radius = 20 / MKMetersPerMapPointAtLatitude(midpoint.coordinate.latitude)
                    let cell = Self.cell(for: midpoint)
                    let reach = Int(ceil(radius / Self.cellSize))
                    var isNew = true
                    for x in (cell.x - reach)...(cell.x + reach) {
                        for y in (cell.y - reach)...(cell.y + reach) {
                            if visited[Cell(x: x, y: y), default: []].contains(where: { $0.distance(to: midpoint) <= 20 }) {
                                isNew = false
                            }
                        }
                    }
                    if ride.startedAt >= startDate {
                        if let last = paths.last, last.isNew == isNew,
                           last.coordinates.last?.latitude == previous.coordinate.latitude,
                           last.coordinates.last?.longitude == previous.coordinate.longitude {
                            paths[paths.count - 1].coordinates.append(point.coordinate)
                        } else {
                            paths.append(Path(id: paths.count, isNew: isNew, coordinates: [previous.coordinate, point.coordinate]))
                        }
                    }
                    additions.append(midpoint)
                    previous = point
                }
            }
            for point in additions {
                let cell = Self.cell(for: point)
                // Keep repeated rides from growing the lookup indefinitely.
                if !visited[cell, default: []].contains(where: { $0.distance(to: point) < 5 }) {
                    visited[cell, default: []].append(point)
                }
            }
        }
    }

    private static let cellSize = 256.0

    private static func cell(for point: MKMapPoint) -> Cell {
        Cell(x: Int(floor(point.x / cellSize)), y: Int(floor(point.y / cellSize)))
    }
}

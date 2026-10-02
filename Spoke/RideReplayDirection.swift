import MapKit

struct RideReplayDirection {
    private(set) var isFacingLeft = false
    private var pendingHorizontalDistance: CLLocationDistance = 0

    mutating func update(
        from currentCoordinate: CLLocationCoordinate2D,
        to nextCoordinate: CLLocationCoordinate2D
    ) {
        let current = MKMapPoint(currentCoordinate)
        let next = MKMapPoint(nextCoordinate)
        guard next.x != current.x, (next.x < current.x) != isFacingLeft else {
            pendingHorizontalDistance = 0
            return
        }

        // Count only horizontal travel; north/south movement must not trigger a flip.
        pendingHorizontalDistance += current.distance(
            to: MKMapPoint(x: next.x, y: current.y)
        )
        if pendingHorizontalDistance >= 1.5 {
            isFacingLeft = next.x < current.x
            pendingHorizontalDistance = 0
        }
    }
}

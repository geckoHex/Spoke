import Foundation
import SwiftData

enum RideUITestFixture {
    static func insert(into context: ModelContext) throws {
        let ride = TrackedRide(startedAt: .now.addingTimeInterval(-3_600))
        ride.customName = "Morning Loop"
        ride.endedAt = ride.startedAt.addingTimeInterval(1_200)
        context.insert(ride)
        for (index, coordinate) in [
            (37.770, -122.450), (37.772, -122.450),
            (37.772, -122.448), (37.771, -122.447), (37.769, -122.449)
        ].enumerated() {
            let point = RideRoutePoint(
                latitude: coordinate.0, longitude: coordinate.1, horizontalAccuracy: 5,
                recordedAt: ride.startedAt.addingTimeInterval(Double(index) * 300)
            )
            context.insert(point)
            ride.routePoints.append(point)
        }
        try context.save()
    }
}

import ActivityKit
import Foundation
import OSLog
import UIKit

@MainActor
final class RideLiveActivityController: RideLiveActivityManaging {
    private var pendingUpdate: Task<Void, Never>?
    private var requestedRideID: String?
    private let logger = Logger(subsystem: "com.beckorion.Spoke", category: "LiveActivity")

    func synchronize(_ snapshot: RideLiveActivitySnapshot?, requestIfNeeded: Bool) {
        let previousUpdate = pendingUpdate
        // Keep a late location update from overwriting a pause or resurrecting an ended ride.
        pendingUpdate = Task {
            await previousUpdate?.value
            await reconcile(snapshot, requestIfNeeded: requestIfNeeded)
        }
    }

    func flush() async {
        await pendingUpdate?.value
    }

    private func reconcile(_ snapshot: RideLiveActivitySnapshot?, requestIfNeeded: Bool) async {
        let activities = Activity<RideActivityAttributes>.activities
        var matchingActivity: Activity<RideActivityAttributes>?

        for activity in activities {
            if activity.attributes.rideID == snapshot?.rideID,
               matchingActivity == nil,
               activity.activityState == .active || activity.activityState == .stale {
                matchingActivity = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard let snapshot else {
            requestedRideID = nil
            return
        }

        let content = ActivityContent(
            state: snapshot.state,
            staleDate: snapshot.state.isPaused ? nil : Date.now.addingTimeInterval(15)
        )

        if let matchingActivity {
            requestedRideID = snapshot.rideID
            await matchingActivity.update(content)
        } else if requestIfNeeded,
                  requestedRideID != snapshot.rideID,
                  UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity.request(
                    attributes: RideActivityAttributes(rideID: snapshot.rideID),
                    content: content,
                    pushType: nil
                )
                requestedRideID = snapshot.rideID
            } catch {
                // A disabled or unavailable Live Activity must never prevent ride tracking.
                logger.error("Could not start ride Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

import Foundation
import SwiftData

// The persisted schema before removal of the unused template model.
enum LegacyRideStore {
    @Model
    final class Item {
        var timestamp: Date

        init(timestamp: Date) {
            self.timestamp = timestamp
        }
    }

    @Model
    final class AppSettings {
        @Attribute(.unique) var key: String = "app"
        var name: String = "User"
        var keepScreenOn: Bool = true
        var soundEffectsEnabled: Bool = true
        var developerModeEnabled: Bool = false
        // Retained for SwiftData migration; obsolete pasted credentials are cleared at launch.
        var spotifyClientID: String = ""
        var spotifyClientSecret: String = ""
        var spotifyRefreshToken: String = ""

        init(
            name: String = "User",
            keepScreenOn: Bool = true,
            developerModeEnabled: Bool = false
        ) {
            self.name = name
            self.keepScreenOn = keepScreenOn
            self.developerModeEnabled = developerModeEnabled
        }
    }

    @Model
    final class TrackedRide {
        var liveActivityID: UUID = UUID()
        var startedAt: Date
        var customName: String?
        var note: String?
        var startAddress: String?
        var endAddress: String?
        var endedAt: Date?
        var pausedAt: Date?
        var lastResumedAt: Date?
        var accumulatedPausedDuration: TimeInterval

        @Relationship(deleteRule: .cascade, inverse: \RideRoutePoint.ride)
        var routePoints: [RideRoutePoint]

        @Relationship(deleteRule: .cascade, inverse: \RideSoundtrackEntry.ride)
        var soundtrackEntries: [RideSoundtrackEntry]

        init(startedAt: Date = .now) {
            self.startedAt = startedAt
            customName = nil
            note = nil
            startAddress = nil
            endAddress = nil
            endedAt = nil
            pausedAt = nil
            lastResumedAt = nil
            accumulatedPausedDuration = 0
            routePoints = []
            soundtrackEntries = []
        }

    }

    @Model
    final class RideRoutePoint {
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var recordedAt: Date
        var recordingStartedAt: Date? = nil
        var ride: TrackedRide?

        init(
            latitude: Double,
            longitude: Double,
            horizontalAccuracy: Double,
            recordedAt: Date,
            ride: TrackedRide? = nil
        ) {
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.recordedAt = recordedAt
            self.ride = ride
        }
    }

    @Model
    final class RideSoundtrackEntry {
        var spotifyTrackID: String?
        var albumArtURLString: String?

        @Attribute(.externalStorage)
        var albumArtData: Data?

        var title: String
        var artist: String
        var startedAt: Date
        var ride: TrackedRide?

        init(
            spotifyTrackID: String?,
            albumArtURL: URL?,
            title: String,
            artist: String,
            startedAt: Date,
            ride: TrackedRide? = nil
        ) {
            self.spotifyTrackID = spotifyTrackID
            albumArtURLString = albumArtURL?.absoluteString
            albumArtData = nil
            self.title = title
            self.artist = artist
            self.startedAt = startedAt
            self.ride = ride
        }

    }
}

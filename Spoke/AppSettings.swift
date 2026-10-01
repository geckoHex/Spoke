//
//  AppSettings.swift
//  Spoke
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var key: String = "app"
    var name: String = "User"
    var keepScreenOn: Bool = true
    var liveRideEnabled: Bool = false
    var liveRideVoiceIdentifier: String = ""
    var liveRideSpeedEnabled: Bool = true
    var liveRideStreetsEnabled: Bool = true
    var liveRideCitiesEnabled: Bool = true
    var liveRideDistanceEnabled: Bool = true
    var liveRideClockTimeEnabled: Bool = true
    var liveRideDurationEnabled: Bool = true
    var developerModeEnabled: Bool = false
    var emergencyCheckInMinutes: Int = 3
    var spotifyClientID: String = ""
    var spotifyClientSecret: String = ""
    var spotifyRefreshToken: String = ""

    init(
        name: String = "User",
        keepScreenOn: Bool = true,
        liveRideEnabled: Bool = false,
        liveRideVoiceIdentifier: String = "",
        liveRideSpeedEnabled: Bool = true,
        liveRideStreetsEnabled: Bool = true,
        liveRideCitiesEnabled: Bool = true,
        liveRideDistanceEnabled: Bool = true,
        liveRideClockTimeEnabled: Bool = true,
        liveRideDurationEnabled: Bool = true,
        developerModeEnabled: Bool = false,
        emergencyCheckInMinutes: Int = 3,
        spotifyClientID: String = "",
        spotifyClientSecret: String = "",
        spotifyRefreshToken: String = ""
    ) {
        self.name = name
        self.keepScreenOn = keepScreenOn
        self.liveRideEnabled = liveRideEnabled
        self.liveRideVoiceIdentifier = liveRideVoiceIdentifier
        self.liveRideSpeedEnabled = liveRideSpeedEnabled
        self.liveRideStreetsEnabled = liveRideStreetsEnabled
        self.liveRideCitiesEnabled = liveRideCitiesEnabled
        self.liveRideDistanceEnabled = liveRideDistanceEnabled
        self.liveRideClockTimeEnabled = liveRideClockTimeEnabled
        self.liveRideDurationEnabled = liveRideDurationEnabled
        self.developerModeEnabled = developerModeEnabled
        self.emergencyCheckInMinutes = min(max(emergencyCheckInMinutes, 1), 10)
        self.spotifyClientID = spotifyClientID
        self.spotifyClientSecret = spotifyClientSecret
        self.spotifyRefreshToken = spotifyRefreshToken
    }
}

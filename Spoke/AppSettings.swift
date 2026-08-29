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
    var speakSpeedEnabled: Bool = false
    var developerModeEnabled: Bool = false
    var spotifyClientID: String = ""
    var spotifyClientSecret: String = ""
    var spotifyRefreshToken: String = ""

    init(
        name: String = "User",
        keepScreenOn: Bool = true,
        speakSpeedEnabled: Bool = false,
        developerModeEnabled: Bool = false,
        spotifyClientID: String = "",
        spotifyClientSecret: String = "",
        spotifyRefreshToken: String = ""
    ) {
        self.name = name
        self.keepScreenOn = keepScreenOn
        self.speakSpeedEnabled = speakSpeedEnabled
        self.developerModeEnabled = developerModeEnabled
        self.spotifyClientID = spotifyClientID
        self.spotifyClientSecret = spotifyClientSecret
        self.spotifyRefreshToken = spotifyRefreshToken
    }
}

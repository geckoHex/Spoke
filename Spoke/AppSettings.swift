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

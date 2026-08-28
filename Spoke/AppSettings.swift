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

    init(name: String = "User", keepScreenOn: Bool = true) {
        self.name = name
        self.keepScreenOn = keepScreenOn
    }
}

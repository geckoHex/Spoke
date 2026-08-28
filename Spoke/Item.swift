//
//  Item.swift
//  Spoke
//
//  Created by Beck Orion on 8/27/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

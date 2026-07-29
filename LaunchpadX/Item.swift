//
//  Item.swift
//  LaunchpadX
//
//  Created by 张航 on 2026/7/29.
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

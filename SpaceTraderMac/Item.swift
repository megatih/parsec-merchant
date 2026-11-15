//
//  Item.swift
//  SpaceTraderMac
//
//  Created by Megat Iskandar Hashim on 16/11/2026.
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

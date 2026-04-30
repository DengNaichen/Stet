//
//  Item.swift
//  testvoice
//
//  Created by Naicheng Deng on 2026-04-30.
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

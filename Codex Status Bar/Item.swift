//
//  Item.swift
//  Codex Status Bar
//
//  Created by Gabriel Bandeira on 05/09/26.
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

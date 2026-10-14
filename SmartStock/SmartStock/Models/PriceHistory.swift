//
//  PriceHistory.swift
//  SmartStock
//

import Foundation

struct PricePoint: Hashable, Identifiable {
    let date: Date
    let price: Double

    var id: Date { date }
}

/// A series of prices plus the close it should be compared against.
struct PriceHistory: Hashable {
    let points: [PricePoint]
    /// Close before the first point; drawn as the dashed baseline.
    let previousClose: Double?

    var isUp: Bool {
        guard let last = points.last?.price else { return true }
        return last >= (previousClose ?? points.first?.price ?? last)
    }
}

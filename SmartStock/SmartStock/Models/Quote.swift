//
//  Quote.swift
//  SmartStock
//

import Foundation

/// Response from Finnhub's `/quote` endpoint.
struct Quote: Decodable, Hashable {
    /// Current price.
    let current: Double
    /// Change since previous close.
    let change: Double?
    /// Percent change since previous close.
    let percentChange: Double?
    let high: Double
    let low: Double
    let open: Double
    let previousClose: Double
    let timestamp: TimeInterval

    /// The symbol that actually produced this quote (may be a proxy ETF).
    var sourceSymbol: String = ""

    enum CodingKeys: String, CodingKey {
        case current = "c"
        case change = "d"
        case percentChange = "dp"
        case high = "h"
        case low = "l"
        case open = "o"
        case previousClose = "pc"
        case timestamp = "t"
    }

    /// Finnhub returns all zeros for symbols it doesn't recognize.
    var isEmpty: Bool { current == 0 && previousClose == 0 }
}

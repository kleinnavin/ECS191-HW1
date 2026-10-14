//
//  Position.swift
//  SmartStock
//

import Foundation

/// Shares of an asset the user bought at a given price on a given date.
struct Position: Codable, Identifiable, Hashable {
    var id = UUID()
    let asset: Asset
    /// The day the shares were bought (any time on that day).
    let purchaseDate: Date
    /// Price paid per share.
    let purchasePrice: Double
    /// May be fractional when the user entered a dollar amount.
    let shares: Double

    /// Total amount paid.
    var costBasis: Double { shares * purchasePrice }

    func marketValue(at price: Double) -> Double { shares * price }

    /// Gain or loss since purchase, in dollars.
    func totalGain(at price: Double) -> Double { marketValue(at: price) - costBasis }

    /// Gain or loss since purchase, as a percent of the cost basis.
    func totalGainPercent(at price: Double) -> Double? {
        costBasis > 0 ? totalGain(at: price) / costBasis * 100 : nil
    }

    /// Today's change in the position's value. Shares bought today count
    /// from the purchase price rather than yesterday's close.
    func dayChange(_ quote: Quote) -> Double? {
        if Calendar.current.isDateInToday(purchaseDate) { return totalGain(at: quote.current) }
        return quote.change.map { $0 * shares }
    }

    func dayChangePercent(_ quote: Quote) -> Double? {
        guard let change = dayChange(quote) else { return nil }
        let start = marketValue(at: quote.current) - change
        return start > 0 ? change / start * 100 : nil
    }
}

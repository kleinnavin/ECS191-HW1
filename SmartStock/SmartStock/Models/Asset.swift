//
//  Asset.swift
//  SmartStock
//

import Foundation

/// A financial asset the user is tracking on the home screen.
struct Asset: Codable, Identifiable, Hashable {
    /// Finnhub symbol, e.g. "AAPL" or "^GSPC".
    let symbol: String
    /// Short name shown in bold, e.g. "S&P 500" or "AAPL".
    let title: String
    /// Longer description shown underneath, e.g. "Apple Inc".
    let name: String
    /// Symbol to quote instead when `symbol` is unavailable on the current
    /// Finnhub plan. Finnhub's free tier doesn't serve index quotes, so the
    /// default indices fall back to an ETF that tracks them.
    var proxySymbol: String? = nil
    /// Security type from symbol search, e.g. "Common Stock", "ADR", "ETP"
    /// or "Mutual Fund". `nil` for assets saved before it was recorded.
    var securityType: String? = nil

    var id: String { symbol }

    /// Market indices such as "^GSPC" can be watched but not held as positions.
    var isIndex: Bool { symbol.hasPrefix("^") }

    /// Whether this is a single company's shares, as opposed to a fund;
    /// `nil` when the security type is unknown.
    var isIndividualStock: Bool? {
        switch securityType {
        case "Common Stock", "ADR", "REIT", "Preference", "GDR", "NY Reg Shrs": true
        case "ETP", "Mutual Fund", "Closed-End Fund", "Open-End Fund", "Unit": false
        default: nil
        }
    }

    static let defaults: [Asset] = [
        Asset(symbol: "^DJI", title: "Dow Jones", name: "Dow Jones Industrial Average", proxySymbol: "DIA"),
        Asset(symbol: "^IXIC", title: "NASDAQ", name: "NASDAQ Composite", proxySymbol: "ONEQ"),
        Asset(symbol: "^GSPC", title: "S&P 500", name: "Standard & Poor's 500", proxySymbol: "SPY"),
    ]
}

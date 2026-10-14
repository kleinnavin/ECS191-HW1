//
//  AssetCategory.swift
//  SmartStock
//

import SwiftUI

/// Broad asset class used for the positions allocation chart. Individual
/// stocks are kept apart from funds (ETFs and mutual funds), which are
/// grouped by what they hold. Cases are in legend order, and each keeps its
/// color however many categories are shown.
enum AssetCategory: String, Codable, CaseIterable, Identifiable {
    case usStock, internationalStock
    case usStockFund, internationalStockFund
    case governmentBond, corporateBond, otherBond
    case realAssets, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usStock: "U.S. Stocks"
        case .internationalStock: "International Stocks"
        case .usStockFund: "U.S. Stock Funds"
        case .internationalStockFund: "International Stock Funds"
        case .governmentBond: "Government Bonds"
        case .corporateBond: "Corporate Bonds"
        case .otherBond: "Other Bonds"
        case .realAssets: "Real Estate & Commodities"
        case .other: "Other"
        }
    }

    /// Categorical palette, dark-mode steps, validated for color-blind
    /// separation between neighbors on the app's black background.
    var color: Color {
        switch self {
        case .usStock: Color(hex: 0x3987E5)                 // blue
        case .internationalStock: Color(hex: 0xD95926)      // orange
        case .usStockFund: Color(hex: 0x199E70)             // aqua
        case .internationalStockFund: Color(hex: 0xC98500)  // yellow
        case .governmentBond: Color(hex: 0xD55181)          // magenta
        case .corporateBond: Color(hex: 0x008300)           // green
        case .otherBond: Color(hex: 0x9085E9)               // violet
        case .realAssets: Color(hex: 0xE66767)              // red
        case .other: Color(white: 0.45)                     // neutral catch-all
        }
    }

    /// An individual company's stock, from a country code ("US") or name
    /// ("United States").
    static func stock(country: String) -> AssetCategory {
        let isUS = ["us", "usa", "united states"].contains(country.lowercased())
        return isUS ? .usStock : .internationalStock
    }

    /// A fund's category from descriptive text: a Morningstar category such
    /// as "Foreign Large Blend" or "Long Government", or the fund's name,
    /// which Yahoo often abbreviates ("T. Rowe Price US Trs LongTerm Idx").
    /// `nil` when nothing matches, which for a fund usually means U.S. stocks.
    static func fund(matching text: String) -> AssetCategory? {
        // Pad words with spaces so " corp" matches "corporate" but not "pricorp".
        let words = " " + String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }) + " "
        func has(_ terms: String...) -> Bool { terms.contains { words.contains(" " + $0) } }

        if has("digital asset", "bitcoin", "ether", "crypto", "money market", "allocation", "target date",
               "target retirement") {
            return .other
        }
        if has("real estate", "reit", "commodit", "precious metals ", "gold ", "silver ", "oil "),
           !has("equity", "miners", "stock") {
            return .realAssets
        }
        if has("bond", "bd ", "bnd ", "fixed inc", "fxd inc", "income fund", "treas", "trs ", "tsy ", "gov",
               "muni", "mun ", "inflation protected", "tips ", "infl ", "aggregate", "agg ", "ultrashort",
               "t bill", "high yield", "hi yld", "high yld", "bank loan", "credit", "mortgage", "securitized") {
            if has("gov", "treas", "trs ", "tsy ", "inflation protected", "tips ", "infl ", "t bill", "muni", "mun ") {
                return .governmentBond
            }
            if has("corporate", "corp ", "high yield", "hi yld", "high yld", "bank loan", "investment grade",
                   "inv gr", "credit") {
                return .corporateBond
            }
            return .otherBond
        }
        if has("foreign", "international", "intl", "int l", "emerging", "em mkt", "world", "global", "ex us",
               "developed", "europe", "japan", "china", "india", "pacific", "latin america", "asia", "region") {
            return .internationalStockFund
        }
        return nil
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
